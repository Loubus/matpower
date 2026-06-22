function varargout = vsc_mtdc_cpf_policy_state(op, varargin)
%VSC_MTDC_CPF_POLICY_STATE Incremental CPF policy-state utilities.

switch lower(op)
    case 'init'
        [varargout{1:nargout}] = init_state(varargin{:});
    case 'current_mpc'
        varargout{1} = current_mpc(varargin{:});
    case 'gen_participant_rows'
        varargout{1} = gen_participant_rows(varargin{:});
    case 'hvdc_participant_rows'
        varargout{1} = hvdc_participant_rows(varargin{:});
    case 'lambda_definition'
        varargout{1} = lambda_definition(varargin{:});
    case 'policy_struct'
        varargout{1} = policy_struct_from_names(varargin{:});
    case 'policy_numeric'
        varargout{1} = policy_numeric_field(varargin{:});
    otherwise
        error('vsc_mtdc_cpf_policy_state:unknown_op', ...
            'Unknown CPF policy-state utility ''%s''.', op);
end


function [st, gen_dispatch, hvdc_dispatch] = init_state(b, t, o)
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
st = struct('enabled', 0);
gen_dispatch = [];
hvdc_dispatch = [];
policies = policy_metadata(b, t, o);
if isempty(policies)
    return;
end
st.enabled = 1;
st.policies = policies;
st.structural_base = b;
st.anchor_mpc = b;
st.anchor_lam = 0;
st.load = resolve_load_policy(b, t, policies);
st.load_k = st.load.k;
st.load_delta_pd = b.bus(:, PD) .* st.load_k;
st.load_delta_qd = b.bus(:, QD) .* st.load_k;
st.total_pd_per_lam = sum(st.load_delta_pd);
st.gen = resolve_gen_policy(b, policies, st.total_pd_per_lam);
st.hvdc = resolve_hvdc_policy(b, policies, st.total_pd_per_lam);
st.vsc_slack_q_relief = resolve_vsc_slack_q_relief_policy(b, policies);
st.vsc_capability_margin = resolve_vsc_capability_margin_policy(policies);
st.gen_frozen = false(size(b.gen, 1), 1);
st.hvdc_frozen = false(size(b.vsc, 1), 1);
gen_dispatch = gen_dispatch_report(b, st.gen, st);
hvdc_dispatch = hvdc_dispatch_report(b, st.hvdc, st);


function policies = policy_metadata(b, t, o)
policies = [];
if isfield(o, 'cpf_policies') && ~isempty(o.cpf_policies)
    policies = o.cpf_policies;
elseif isfield(b, 'cpf_policies') && ~isempty(b.cpf_policies)
    policies = b.cpf_policies;
elseif isfield(t, 'cpf_policies') && ~isempty(t.cpf_policies)
    policies = t.cpf_policies;
end


function load = resolve_load_policy(b, t, policies)
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
p = policy_struct_from_names(policies, {'load', 'load_policy', ...
    'load_scaling'});
load = struct('policy', 'multiplicative', 'k', [], ...
    'source', 'target_case');
if ~isempty(p)
    load.policy = lower(policy_text_field(p, {'policy', 'mode'}, ...
        'multiplicative'));
    valid_policy = {'multiplicative', 'proportional_relative_increase', ...
        'relative_load_increase'};
    if ~any(strcmp(load.policy, valid_policy))
        error('runcpf_vsc_mtdc: unsupported CPF load policy ''%s''', ...
            load.policy);
    end
    load.k = policy_numeric_vector_field(p, ...
        {'k', 'load_k', 'load_multiplier', 'load_multipliers', ...
         'relative_load_increment', 'load_increment_scale'}, []);
    if ~isempty(load.k)
        load.source = 'policy';
    end
end
if isempty(load.k)
    load.k = infer_load_multiplier_from_target(b.bus(:, [PD QD]), ...
        t.bus(:, [PD QD]));
end
if isscalar(load.k)
    load.k = repmat(load.k, size(b.bus, 1), 1);
else
    load.k = load.k(:);
end
if length(load.k) ~= size(b.bus, 1) || any(~isfinite(load.k))
    error('runcpf_vsc_mtdc: CPF load multiplier k must be scalar or one value per bus');
end


function k = infer_load_multiplier_from_target(base_load, target_load)
pd0 = base_load(:, 1);
qd0 = base_load(:, 2);
dp = target_load(:, 1) - pd0;
dq = target_load(:, 2) - qd0;
nb = size(base_load, 1);
k = zeros(nb, 1);
tol = 1e-9;
for ii = 1:nb
    has_p = abs(pd0(ii)) > tol;
    has_q = abs(qd0(ii)) > tol;
    if has_p
        kp = dp(ii) / pd0(ii);
    else
        kp = [];
    end
    if has_q
        kq = dq(ii) / qd0(ii);
    else
        kq = [];
    end
    if has_p && has_q
        if abs(kp - kq) > tol * max(1, max(abs([kp kq])))
            error('runcpf_vsc_mtdc: target load direction must preserve load power factor for CPF policies');
        end
        k(ii) = 0.5 * (kp + kq);
    elseif has_p
        if abs(dq(ii)) > tol
            error('runcpf_vsc_mtdc: cannot infer CPF load multiplier for zero-Q load with nonzero Q target delta');
        end
        k(ii) = kp;
    elseif has_q
        if abs(dp(ii)) > tol
            error('runcpf_vsc_mtdc: cannot infer CPF load multiplier for zero-P load with nonzero P target delta');
        end
        k(ii) = kq;
    elseif abs(dp(ii)) > tol || abs(dq(ii)) > tol
        error('runcpf_vsc_mtdc: cannot infer CPF load multiplier for zero base load with nonzero target delta');
    end
end


function mpc = current_mpc(b, lam, st)
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
mpc = st.anchor_mpc;
mpc = apply_active_set_overrides(mpc, b, st);
mpc.bus(:, PD) = st.structural_base.bus(:, PD) .* (1 + lam * st.load_k);
mpc.bus(:, QD) = st.structural_base.bus(:, QD) .* (1 + lam * st.load_k);
dP_load = incremental_load_change_mw(st, lam);
mpc = apply_gen_policy(mpc, dP_load, st);
mpc = apply_hvdc_policy(mpc, dP_load, st);


function mpc = apply_active_set_overrides(mpc, b, st)
[~, ~, ~, ~, ~, BUS_TYPE, ~, ~, GS, BS, ~, VM] = idx_bus;
[~, ~, BR_R, BR_X, BR_B, ~, ~, ~, TAP, SHIFT, BR_STATUS] = idx_brch;
[~, PG, QG, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;
c = idx_vsc;
tol = 1e-10;
if isfield(b, 'bus') && size(b.bus, 1) == size(mpc.bus, 1)
    mpc.bus(:, [BUS_TYPE GS BS VM]) = b.bus(:, [BUS_TYPE GS BS VM]);
end
if isfield(b, 'branch') && size(b.branch, 1) == size(mpc.branch, 1)
    mpc.branch(:, [BR_R BR_X BR_B TAP SHIFT BR_STATUS]) = ...
        b.branch(:, [BR_R BR_X BR_B TAP SHIFT BR_STATUS]);
end
if isfield(b, 'gen') && size(b.gen, 1) == size(mpc.gen, 1)
    mpc.gen(:, [QG QMAX QMIN VG GEN_STATUS]) = ...
        b.gen(:, [QG QMAX QMIN VG GEN_STATUS]);
    pg_override = abs(b.gen(:, PG) - st.structural_base.gen(:, PG)) > tol;
    mpc.gen(pg_override, PG) = b.gen(pg_override, PG);
end
if isfield(b, 'vsc') && size(b.vsc, 1) == size(mpc.vsc, 1)
    cols = [c.AC_MODE c.PAC_SET c.QAC_SET c.VAC_SET c.PDC_SET ...
        c.VDC_SET c.KDROOP];
    override = abs(b.vsc(:, cols) - st.structural_base.vsc(:, cols)) > tol;
    for kk = 1:length(cols)
        rows = override(:, kk);
        mpc.vsc(rows, cols(kk)) = b.vsc(rows, cols(kk));
    end
end
if isfield(b, 'psse')
    mpc.psse = b.psse;
end


function gen = resolve_gen_policy(mpc, policies, total_pd_per_lam)
p = policy_struct_from_names(policies, {'gen', 'gen_policy', ...
    'gen_dispatch', 'generator_dispatch'});
gen = struct('enabled', 0, 'policy', 'none', 'gen_idx', [], ...
    'weights', [], 'load_share', [], 'amount_mw_per_lambda', []);
if isempty(p)
    return;
end
gen.policy = lower(policy_text_field(p, {'policy', 'mode'}, ...
    'participation'));
if strcmp(gen.policy, 'none') || strcmp(gen.policy, 'constant')
    return;
end
if ~strcmp(gen.policy, 'participation')
    error('runcpf_vsc_mtdc: unsupported CPF generator policy ''%s''', ...
        gen.policy);
end
gen.enabled = 1;
gen.gen_idx = gen_indices(mpc, p);
gen.weights = normalized_weights(p, length(gen.gen_idx), 'generator');
gen.load_share = policy_numeric_field(p, {'load_share', 'share'}, []);
gen.amount_mw_per_lambda = policy_numeric_field(p, ...
    {'amount_mw_per_lambda', 'amount_per_lambda', 'amount_mw'}, []);
if isempty(gen.load_share) && isempty(gen.amount_mw_per_lambda)
    error('runcpf_vsc_mtdc: generator participation policy requires load_share or amount_mw_per_lambda');
end
if isempty(gen.amount_mw_per_lambda)
    gen.amount_mw_per_lambda = gen.load_share * total_pd_per_lam;
end


function hvdc = resolve_hvdc_policy(mpc, policies, total_pd_per_lam)
p = policy_struct_from_names(policies, {'hvdc', 'hvdc_policy', ...
    'vsc_hvdc', 'vsc_hvdc_dispatch'});
nv = size(mpc.vsc, 1);
hvdc = struct('enabled', 0, 'policy', 'none', 'source_idx', [], ...
    'sink_idx', [], 'qac_idx', [], 'qac_gain', zeros(nv, 1), ...
    'transfer_gain', [], 'transfer_mw_per_lambda', [], ...
    'criterion', '', 'relieved_branch', [], ...
    'derating', default_hvdc_derating_policy());
if isempty(p)
    return;
end
hvdc.policy = lower(policy_text_field(p, {'policy', 'mode'}, ...
    'pac_pair_transfer'));
if strcmp(hvdc.policy, 'none') || strcmp(hvdc.policy, 'constant')
    return;
end
if ~strcmp(hvdc.policy, 'pac_pair_transfer')
    error('runcpf_vsc_mtdc: unsupported CPF HVDC policy ''%s''', ...
        hvdc.policy);
end
hvdc.enabled = 1;
hvdc.source_idx = vsc_index(mpc, p, ...
    {'source_converter', 'source_idx', 'from_converter'}, ...
    {'source_bus', 'source_ac_bus', 'from_bus'});
hvdc.sink_idx = vsc_index(mpc, p, ...
    {'sink_converter', 'sink_idx', 'to_converter'}, ...
    {'sink_bus', 'sink_ac_bus', 'to_bus'});
if hvdc.source_idx == hvdc.sink_idx
    error('runcpf_vsc_mtdc: HVDC source and sink converters must differ');
end
validate_pac_rows(mpc, [hvdc.source_idx; hvdc.sink_idx]);
hvdc.transfer_gain = policy_numeric_field(p, ...
    {'gain_mw_per_mw_load', 'transfer_gain_mw_per_mw_load', ...
     'mw_per_mw_load'}, []);
hvdc.transfer_mw_per_lambda = policy_numeric_field(p, ...
    {'transfer_mw_per_lambda', 'transfer_mw'}, []);
if isempty(hvdc.transfer_gain) && isempty(hvdc.transfer_mw_per_lambda)
    error('runcpf_vsc_mtdc: HVDC policy requires gain_mw_per_mw_load or transfer_mw_per_lambda');
end
if isempty(hvdc.transfer_mw_per_lambda)
    hvdc.transfer_mw_per_lambda = hvdc.transfer_gain * total_pd_per_lam;
end
if isempty(hvdc.transfer_gain)
    hvdc.transfer_gain = hvdc.transfer_mw_per_lambda / total_pd_per_lam;
end
[hvdc.qac_idx, qac_gain] = qac_gain_policy(mpc, p, total_pd_per_lam);
hvdc.qac_gain = qac_gain;
hvdc.criterion = policy_text_field(p, {'criterion'}, '');
hvdc.relieved_branch = policy_value_field(p, ...
    {'relieved_branch', 'relieved_ac_branch'}, []);
hvdc.derating = resolve_hvdc_derating_policy(mpc, p, hvdc);


function derating = default_hvdc_derating_policy()
derating = struct('enabled', 0, 'monitor_idx', [], ...
    'start_utilization', 0.90, 'target_utilization', 0.85, ...
    'backoff_lambda_per_step', 0.005, ...
    'min_transfer_scale', 0, 'max_it', 20);


function derating = resolve_hvdc_derating_policy(mpc, hvdc_policy, hvdc)
derating = default_hvdc_derating_policy();
raw = policy_value_field(hvdc_policy, ...
    {'vsc_derating', 'derating', 'dynamic_derating'}, []);
if isempty(raw)
    return;
end
if ~isstruct(raw)
    error('runcpf_vsc_mtdc: HVDC vsc_derating policy must be a struct');
end
derating.enabled = policy_numeric_field(raw, {'enabled'}, 1) ~= 0;
derating.monitor_idx = vsc_indices(mpc, raw, ...
    {'monitor_converters', 'monitor_vsc_idx', 'converters', 'vsc_idx'}, ...
    {'monitor_buses', 'monitor_ac_buses', 'buses', 'ac_buses'});
if isempty(derating.monitor_idx)
    derating.monitor_idx = unique([hvdc.source_idx; hvdc.sink_idx; ...
        hvdc.qac_idx(:)]);
end
derating.start_utilization = policy_numeric_field(raw, ...
    {'start_utilization', 'start_util', 'trigger_utilization'}, ...
    derating.start_utilization);
derating.target_utilization = policy_numeric_field(raw, ...
    {'target_utilization', 'target_util'}, derating.target_utilization);
derating.backoff_lambda_per_step = policy_numeric_field(raw, ...
    {'backoff_lambda_per_step', 'lambda_backoff_step', ...
     'backoff_step_lambda'}, derating.backoff_lambda_per_step);
derating.min_transfer_scale = policy_numeric_field(raw, ...
    {'min_transfer_scale', 'minimum_transfer_scale'}, ...
    derating.min_transfer_scale);
derating.max_it = policy_numeric_field(raw, ...
    {'max_it', 'max_iterations', 'max_deratings_per_step'}, ...
    derating.max_it);
if derating.start_utilization <= 0 || derating.start_utilization > 1
    error('runcpf_vsc_mtdc: HVDC derating start_utilization must be in (0, 1]');
end
if derating.target_utilization < 0 || ...
        derating.target_utilization >= derating.start_utilization
    error('runcpf_vsc_mtdc: HVDC derating target_utilization must be >= 0 and below start_utilization');
end
if derating.backoff_lambda_per_step < 0
    error('runcpf_vsc_mtdc: HVDC derating backoff_lambda_per_step must be nonnegative');
end
if derating.min_transfer_scale < 0 || derating.min_transfer_scale > 1
    error('runcpf_vsc_mtdc: HVDC derating min_transfer_scale must be in [0, 1]');
end
if derating.max_it < 1 || derating.max_it ~= fix(derating.max_it)
    error('runcpf_vsc_mtdc: HVDC derating max_it must be a positive integer');
end


function relief = resolve_vsc_slack_q_relief_policy(mpc, policies)
c = idx_vsc;
p = policy_struct_from_names(policies, {'vsc_slack_q_relief', ...
    'dc_slack_q_relief', 'vsc_ac_support_relief'});
relief = struct('enabled', 0, 'policy', 'none', ...
    'vsc_idx', zeros(0, 1), 'max_saturations', 80);
if isempty(p)
    return;
end
relief.policy = lower(policy_text_field(p, {'policy', 'mode'}, ...
    'dc_slack_ac_q_saturate'));
if strcmp(relief.policy, 'none') || strcmp(relief.policy, 'constant')
    return;
end
if strcmp(relief.policy, 'dc_slack_ac_q_backoff')
    relief.policy = 'dc_slack_ac_q_saturate';
end
if ~strcmp(relief.policy, 'dc_slack_ac_q_saturate')
    error('runcpf_vsc_mtdc: unsupported VSC slack Q relief policy ''%s''', ...
        relief.policy);
end
relief.enabled = 1;
relief.vsc_idx = vsc_indices(mpc, p, ...
    {'converters', 'converter_idx', 'vsc_idx'}, ...
    {'buses', 'ac_buses', 'vsc_buses'});
if isempty(relief.vsc_idx)
    relief.vsc_idx = find(mpc.vsc(:, c.VSC_STATUS) > 0 & ...
        mpc.vsc(:, c.DC_MODE) == c.VSC_DC_VDC);
end
if any(mpc.vsc(relief.vsc_idx, c.DC_MODE) ~= c.VSC_DC_VDC)
    error('runcpf_vsc_mtdc: VSC slack Q relief applies only to VSC_DC_VDC converters');
end
max_saturations = policy_numeric_field(p, ...
    {'max_saturations', 'max_backoff'}, []);
if ~isempty(max_saturations)
    if max_saturations < 1 || max_saturations ~= fix(max_saturations)
        error('runcpf_vsc_mtdc: VSC slack Q relief max_saturations must be a positive integer');
    end
    relief.max_saturations = max_saturations;
end


function margin = resolve_vsc_capability_margin_policy(policies)
p = policy_struct_from_names(policies, ...
    {'vsc_capability', 'capability', 'vsc_saturation'});
    base_fraction = policy_numeric_vector_field(p, ...
        {'saturation_margin_fraction', 'margin_fraction', ...
         'inward_margin_fraction'}, 0);
    step_fraction = policy_numeric_vector_field(p, ...
        {'saturation_margin_step_fraction', 'margin_step_fraction', ...
         'dynamic_margin_step_fraction'}, 0);
    max_fraction = policy_numeric_vector_field(p, ...
        {'saturation_margin_max_fraction', 'margin_max_fraction', ...
         'dynamic_margin_max_fraction'}, base_fraction);
validate_margin_fraction(base_fraction, 'saturation margin fraction');
validate_margin_fraction(step_fraction, 'saturation margin step fraction');
validate_margin_fraction(max_fraction, 'saturation margin max fraction');
if isscalar(step_fraction) && ~isscalar(base_fraction)
    step_fraction = repmat(step_fraction, size(base_fraction));
end
if isscalar(max_fraction) && ~isscalar(base_fraction)
    max_fraction = repmat(max_fraction, size(base_fraction));
end
if any(max_fraction(:) < base_fraction(:))
    error('runcpf_vsc_mtdc: VSC saturation margin max must be >= base margin');
end
margin = struct( ...
    'enabled',          any(step_fraction(:) > 0 & ...
                        max_fraction(:) > base_fraction(:)), ...
    'base_fraction',    base_fraction, ...
    'current_fraction', base_fraction, ...
    'step_fraction',    step_fraction, ...
    'max_fraction',     max_fraction);


function dP = incremental_load_change_mw(st, lam)
[~, ~, ~, ~, ~, ~, PD] = idx_bus;
dP = sum(st.structural_base.bus(:, PD) .* st.load_k * ...
    (lam - st.anchor_lam));


function mpc = apply_gen_policy(mpc, dP_load, st)
[~, PG] = idx_gen;
gen = st.gen;
if ~gen.enabled || dP_load == 0
    return;
end
idx = gen.gen_idx(:);
active = idx(~st.gen_frozen(idx));
if isempty(active)
    return;
end
[~, loc] = ismember(active, idx);
w = gen.weights(loc);
w = w / sum(w);
amount = redispatch_amount_from_load_change(dP_load, gen.load_share, ...
    gen.amount_mw_per_lambda, st.total_pd_per_lam, 'generator');
for kk = 1:length(active)
    g = active(kk);
    mpc.gen(g, PG) = mpc.gen(g, PG) + amount * w(kk);
end


function mpc = apply_hvdc_policy(mpc, dP_load, st)
c = idx_vsc;
hvdc = st.hvdc;
if ~hvdc.enabled || dP_load == 0
    return;
end
transfer = redispatch_amount_from_load_change(dP_load, hvdc.transfer_gain, ...
    hvdc.transfer_mw_per_lambda, st.total_pd_per_lam, 'HVDC');
if ~st.hvdc_frozen(hvdc.source_idx)
    mpc.vsc(hvdc.source_idx, c.PAC_SET) = ...
        mpc.vsc(hvdc.source_idx, c.PAC_SET) - transfer;
end
if ~st.hvdc_frozen(hvdc.sink_idx)
    mpc.vsc(hvdc.sink_idx, c.PAC_SET) = ...
        mpc.vsc(hvdc.sink_idx, c.PAC_SET) + transfer;
end
for kk = 1:length(hvdc.qac_idx)
    row = hvdc.qac_idx(kk);
    if ~st.hvdc_frozen(row)
        mpc.vsc(row, c.QAC_SET) = mpc.vsc(row, c.QAC_SET) + ...
            hvdc.qac_gain(row) * dP_load;
    end
end


function amount = redispatch_amount_from_load_change(dP_load, share, per_lam, ...
        total_pd_per_lam, label)
if ~isempty(share)
    amount = share * dP_load;
elseif total_pd_per_lam == 0
    error('runcpf_vsc_mtdc: %s per-lambda policy requires nonzero active load direction', ...
        label);
else
    amount = per_lam * dP_load / total_pd_per_lam;
end


function rows = gen_participant_rows(st)
if isstruct(st) && isfield(st, 'enabled') && st.enabled && st.gen.enabled
    rows = st.gen.gen_idx(:);
else
    rows = [];
end


function rows = hvdc_participant_rows(st)
if isstruct(st) && isfield(st, 'enabled') && st.enabled && st.hvdc.enabled
    rows = unique([st.hvdc.source_idx; st.hvdc.sink_idx; st.hvdc.qac_idx(:)]);
else
    rows = [];
end


function report = gen_dispatch_report(mpc, gen, ~)
if gen.enabled
    report = struct('policy', gen.policy, 'incremental', 1, ...
        'lambda_definition', 'load_scaling_only', ...
        'gen_idx', gen.gen_idx(:), ...
        'gen_buses', mpc.gen(gen.gen_idx, 1), ...
        'weights_used', gen.weights(:), ...
        'load_share', gen.load_share, ...
        'amount_mw_per_lambda', gen.amount_mw_per_lambda);
else
    report = [];
end


function report = hvdc_dispatch_report(mpc, hvdc, ~)
c = idx_vsc;
if hvdc.enabled
    report = struct('policy', hvdc.policy, 'incremental', 1, ...
        'lambda_definition', 'load_scaling_only', ...
        'criterion', hvdc.criterion, ...
        'relieved_branch', hvdc.relieved_branch, ...
        'source_converter_idx', hvdc.source_idx, ...
        'sink_converter_idx', hvdc.sink_idx, ...
        'source_ac_bus', mpc.vsc(hvdc.source_idx, c.VSC_BUS), ...
        'sink_ac_bus', mpc.vsc(hvdc.sink_idx, c.VSC_BUS), ...
        'gain_mw_per_mw_load', hvdc.transfer_gain, ...
        'transfer_mw_per_lambda', hvdc.transfer_mw_per_lambda, ...
        'uses_pdc_set', 0, ...
        'qac_converter_idx', hvdc.qac_idx(:), ...
        'qac_gain_mvar_per_mw_load', hvdc.qac_gain(:), ...
        'dynamic_derating', hvdc.derating);
else
    report = [];
end


function s = lambda_definition(st)
s = 'load_scaling_only';
if isstruct(st) && isfield(st, 'enabled') && st.enabled && ...
        isfield(st.policies, 'lambda_definition') && ...
        ~isempty(st.policies.lambda_definition)
    s = st.policies.lambda_definition;
end


function p = policy_struct_from_names(policies, names)
p = [];
if ~isstruct(policies)
    return;
end
for kk = 1:length(names)
    if isfield(policies, names{kk}) && ~isempty(policies.(names{kk}))
        p = policies.(names{kk});
        return;
    end
end


function val = policy_value_field(policy, names, default)
val = default;
if ~isstruct(policy)
    return;
end
for kk = 1:length(names)
    if isfield(policy, names{kk}) && ~isempty(policy.(names{kk}))
        val = policy.(names{kk});
        return;
    end
end


function txt = policy_text_field(policy, names, default)
txt = policy_value_field(policy, names, default);
if ~ischar(txt)
    error('runcpf_vsc_mtdc: CPF policy field must be text');
end


function val = policy_numeric_field(policy, names, default)
val = policy_value_field(policy, names, default);
if isempty(val)
    return;
end
if ~isscalar(val) || ~isnumeric(val) || ~isfinite(val)
    error('runcpf_vsc_mtdc: CPF policy numeric field must be a finite scalar');
end


function val = policy_numeric_vector_field(policy, names, default)
val = policy_value_field(policy, names, default);
if isempty(val)
    return;
end
if ~isnumeric(val) || any(~isfinite(val(:)))
    error('runcpf_vsc_mtdc: CPF policy numeric vector field must be finite numeric');
end


function idx = gen_indices(mpc, policy)
[GEN_BUS, ~, ~, ~, ~, ~, ~, GEN_STATUS] = idx_gen;
idx = policy_value_field(policy, {'gens', 'gen_idx', 'generators'}, []);
if isempty(idx)
    buses = policy_value_field(policy, {'gen_buses', 'buses'}, []);
    if isempty(buses)
        error('runcpf_vsc_mtdc: generator policy requires gens or gen_buses');
    end
    buses = buses(:);
    idx = zeros(length(buses), 1);
    for kk = 1:length(buses)
        rows = find(mpc.gen(:, GEN_BUS) == buses(kk) & ...
            mpc.gen(:, GEN_STATUS) > 0 & ~isload(mpc.gen));
        if isempty(rows)
            error('runcpf_vsc_mtdc: no in-service generator at bus %g', ...
                buses(kk));
        elseif length(rows) > 1
            error('runcpf_vsc_mtdc: multiple generators at bus %g; use gen_idx', ...
                buses(kk));
        end
        idx(kk) = rows;
    end
end
idx = idx(:);
if any(idx < 1) || any(idx > size(mpc.gen, 1)) || ...
        any(idx ~= fix(idx)) || length(unique(idx)) ~= length(idx)
    error('runcpf_vsc_mtdc: invalid generator policy indices');
end


function w = normalized_weights(policy, n, label)
w = policy_value_field(policy, {'weights', 'weight'}, []);
if isempty(w)
    w = ones(n, 1);
else
    w = w(:);
end
if length(w) ~= n || any(~isfinite(w)) || any(w < 0) || sum(w) <= 0
    error('runcpf_vsc_mtdc: %s policy weights are invalid', label);
end
w = w / sum(w);


function idx = vsc_index(mpc, policy, idx_names, bus_names)
c = idx_vsc;
idx = policy_value_field(policy, idx_names, []);
if isempty(idx)
    bus = policy_value_field(policy, bus_names, []);
    if isempty(bus)
        error('runcpf_vsc_mtdc: HVDC policy requires converter or bus selectors');
    end
    rows = find(mpc.vsc(:, c.VSC_BUS) == bus);
    if isempty(rows)
        error('runcpf_vsc_mtdc: no VSC converter at AC bus %g', bus);
    elseif length(rows) > 1
        error('runcpf_vsc_mtdc: multiple VSC converters at AC bus %g', bus);
    end
    idx = rows;
end
if ~isscalar(idx) || idx < 1 || idx > size(mpc.vsc, 1) || idx ~= fix(idx)
    error('runcpf_vsc_mtdc: invalid VSC converter index');
end


function idx = vsc_indices(mpc, policy, idx_names, bus_names)
c = idx_vsc;
idx = policy_value_field(policy, idx_names, []);
if isempty(idx)
    buses = policy_value_field(policy, bus_names, []);
    if isempty(buses)
        idx = zeros(0, 1);
        return;
    end
    buses = buses(:);
    idx = zeros(length(buses), 1);
    for kk = 1:length(buses)
        rows = find(mpc.vsc(:, c.VSC_BUS) == buses(kk));
        if isempty(rows)
            error('runcpf_vsc_mtdc: no VSC converter at AC bus %g', ...
                buses(kk));
        elseif length(rows) > 1
            error('runcpf_vsc_mtdc: multiple VSC converters at AC bus %g; use converter index', ...
                buses(kk));
        end
        idx(kk) = rows;
    end
end
idx = idx(:);
if any(idx < 1) || any(idx > size(mpc.vsc, 1)) || ...
        any(idx ~= fix(idx)) || length(unique(idx)) ~= length(idx)
    error('runcpf_vsc_mtdc: invalid VSC converter indices');
end


function validate_pac_rows(mpc, rows)
c = idx_vsc;
if any(mpc.vsc(rows, c.VSC_STATUS) <= 0)
    error('runcpf_vsc_mtdc: HVDC policy converters must be in service');
end
ok = mpc.vsc(rows, c.AC_MODE) == c.VSC_AC_PQ | ...
    mpc.vsc(rows, c.AC_MODE) == c.VSC_AC_PV;
if any(~ok)
    error('runcpf_vsc_mtdc: HVDC Pac redispatch requires VSC_AC_PQ or VSC_AC_PV converters');
end


function [idx, gain] = qac_gain_policy(mpc, policy, total_pd_per_lam)
nv = size(mpc.vsc, 1);
gain = zeros(nv, 1);
raw = policy_value_field(policy, {'qac_gain_mvar_per_mw_load', ...
    'qac_gain_per_mw_load'}, []);
if isempty(raw)
    raw = policy_value_field(policy, {'qac_delta_per_lambda', ...
        'qac_delta'}, []);
    scale = total_pd_per_lam;
    if isempty(raw)
        idx = zeros(0, 1);
        return;
    elseif scale == 0
        error('runcpf_vsc_mtdc: qac_delta requires nonzero load direction');
    else
        raw = raw(:) / scale;
    end
else
    raw = raw(:);
end
idx = policy_value_field(policy, {'qac_converters', ...
    'qac_converter_idx', 'qac_vsc_idx'}, []);
if isempty(idx)
    buses = policy_value_field(policy, {'qac_buses', 'qac_ac_buses'}, []);
    if ~isempty(buses)
        buses = buses(:);
        idx = zeros(length(buses), 1);
        for kk = 1:length(buses)
            idx(kk) = vsc_index(mpc, struct('converter_bus', buses(kk)), ...
                {}, {'converter_bus'});
        end
    end
end
if isempty(idx) && length(raw) == nv
    idx = find(abs(raw) > 0);
    gain = raw;
    return;
elseif isempty(idx)
    error('runcpf_vsc_mtdc: Qac policy requires qac converters or buses');
end
idx = idx(:);
if length(raw) ~= length(idx)
    error('runcpf_vsc_mtdc: Qac policy vector length mismatch');
end
gain(idx) = raw;


function validate_margin_fraction(margin, label)
if ~isnumeric(margin) || any(~isfinite(margin(:))) || ...
        any(margin(:) < 0 | margin(:) > 1)
    error('runcpf_vsc_mtdc: VSC %s must be in [0, 1]', label);
end
