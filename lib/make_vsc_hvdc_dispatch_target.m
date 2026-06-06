function [target, dispatch] = make_vsc_hvdc_dispatch_target(base, target, policy)
% make_vsc_hvdc_dispatch_target - Builds CPF targets with VSC/HVDC dispatch.
% ::
%
%   TARGET = MAKE_VSC_HVDC_DISPATCH_TARGET(BASE, TARGET, POLICY)
%   [TARGET, DISPATCH] = MAKE_VSC_HVDC_DISPATCH_TARGET(...)
%
%   Applies a simple scheduled VSC/HVDC dispatch policy to a CPF target case,
%   leaving load and generation changes already present in TARGET untouched.
%   VSC set points are first copied from BASE, then the requested policy
%   applies explicit PDC_SET and optional QAC_SET deltas.
%
%   POLICY can be a string or a struct with a POLICY or MODE field:
%
%       'constant'
%           Keeps all VSC CPF-transfer set points equal to BASE.
%
%       'pdc_share_load'
%           Uses POLICY.HVDC_SHARE to assign a share of the total active load
%           increment to selected converters. Select converters with
%           POLICY.CONVERTERS or POLICY.BUSES and optionally set
%           POLICY.WEIGHTS.
%
%       'droop_scheduled'
%           Same scheduled PDC_SET change as pdc_share_load, but selected
%           converters must be in VSC_DC_DROOP mode and at least one active
%           VSC_DC_VDC converter must remain present.
%
%   Optional QAC_SET scheduling can use either explicit deltas or a share of
%   the total reactive load increment:
%
%       POLICY.QAC_DELTA
%           Explicit per-converter MVAr deltas with POLICY.QAC_CONVERTERS or
%           POLICY.QAC_BUSES. If no QAC selector is given and the length of
%           QAC_DELTA matches the active-power converter list, the same
%           converter list is used.
%
%       POLICY.QAC_POLICY = 'share_load'
%           Uses POLICY.QAC_SHARE to assign a share of the total reactive load
%           increment to POLICY.QAC_CONVERTERS or POLICY.QAC_BUSES. Optional
%           POLICY.QAC_WEIGHTS controls the split. The equivalent nested form
%           POLICY.QAC = STRUCT('POLICY', 'share_load', ...) is also accepted.
%
%   A positive HVDC share of a positive load increment makes PDC_SET more
%   negative on the selected receiving converters. With the VSC sign
%   convention, this increases AC-side active injection after losses.
%
% See also runcpf_vsc_mtdc, runpf_vsc_mtdc, idx_vsc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 3 || isempty(policy)
    policy = 'constant';
end

base = loadcase(base);
target = loadcase(target);

[~, ~, PD, QD] = idx_bus;
c = idx_vsc;

validate_cases(base, target, c);

mode = policy_mode(policy);
setpoint_cols = [c.PAC_SET c.QAC_SET c.VAC_SET c.PDC_SET ...
    c.VDC_SET c.KDROOP];
target.vsc(:, setpoint_cols) = base.vsc(:, setpoint_cols);

nv = size(base.vsc, 1);
delta_pd = sum(target.bus(:, PD) - base.bus(:, PD));
delta_qd = sum(target.bus(:, QD) - base.bus(:, QD));
hvdc_share = 0;
delta_hvdc_mw = 0;
pdc_idx = zeros(0, 1);
weights = zeros(0, 1);
delta_pdc = zeros(nv, 1);

switch mode
    case 'constant'
        %% nothing else to apply
    case {'pdc_share_load', 'droop_scheduled'}
        hvdc_share = required_scalar_policy_field(policy, 'hvdc_share', mode);
        pdc_idx = selected_converters(policy, base, c, ...
            {'converters', 'converter_idx', 'vsc', 'vsc_idx'}, ...
            {'buses', 'ac_buses', 'vsc_buses'});
        weights = normalized_weights(policy, length(pdc_idx));
        validate_pdc_schedule(mode, base, pdc_idx, c);

        delta_hvdc_mw = hvdc_share * delta_pd;
        delta_pdc(pdc_idx) = -delta_hvdc_mw * weights;
        target.vsc(:, c.PDC_SET) = target.vsc(:, c.PDC_SET) + delta_pdc;
    otherwise
        error('make_vsc_hvdc_dispatch_target: unknown policy ''%s''', mode);
end

[qac_idx, delta_qac, qac] = reactive_schedule(policy, base, target, ...
    pdc_idx, c, QD);
if ~isempty(qac_idx)
    target.vsc(:, c.QAC_SET) = target.vsc(:, c.QAC_SET) + delta_qac;
end

affected = unique([pdc_idx(:); qac_idx(:)]);
dispatch = struct( ...
    'policy',               mode, ...
    'delta_pd',             delta_pd, ...
    'delta_qd',             delta_qd, ...
    'hvdc_share',           hvdc_share, ...
    'delta_hvdc_mw',        delta_hvdc_mw, ...
    'weights_used',         weights(:), ...
    'converter_idx',        pdc_idx(:), ...
    'ac_buses',             base.vsc(pdc_idx, c.VSC_BUS), ...
    'dc_buses',             base.vsc(pdc_idx, c.BUSDC), ...
    'delta_pdc_set',        delta_pdc, ...
    'qac_policy',           qac.policy, ...
    'qac_share',            qac.share, ...
    'delta_qac_mvar',       qac.delta_qac_mvar, ...
    'qac_weights_used',     qac.weights_used(:), ...
    'qac_converter_idx',    qac_idx(:), ...
    'qac_ac_buses',         base.vsc(qac_idx, c.VSC_BUS), ...
    'qac_delta_set',        delta_qac, ...
    'affected_converters',  affected(:), ...
    'affected_ac_buses',    base.vsc(affected, c.VSC_BUS) );


function validate_cases(base, target, c)
if ~isfield(base, 'bus') || ~isfield(target, 'bus') || ...
        ~isfield(base, 'gen') || ~isfield(target, 'gen') || ...
        ~isfield(base, 'vsc') || ~isfield(target, 'vsc')
    error('make_vsc_hvdc_dispatch_target: base and target must be MATPOWER cases with bus, gen and vsc fields');
end
same_size('bus', base.bus, target.bus);
same_size('gen', base.gen, target.gen);
same_size('vsc', base.vsc, target.vsc);

fixed_cols = [c.VSC_BUS c.BUSDC c.VSC_STATUS c.AC_MODE c.DC_MODE ...
    c.LOSS_A:c.REACTOR_RATE_C];
if any(any(base.vsc(:, fixed_cols) ~= target.vsc(:, fixed_cols)))
    error('make_vsc_hvdc_dispatch_target: base and target VSC topology, modes and station data must match');
end


function same_size(name, a, b)
if size(a, 1) ~= size(b, 1) || size(a, 2) ~= size(b, 2)
    error('make_vsc_hvdc_dispatch_target: base and target %s matrices must have the same size', name);
end


function mode = policy_mode(policy)
if ischar(policy)
    mode = lower(policy);
elseif isstruct(policy)
    if isfield(policy, 'policy')
        mode = lower(policy.policy);
    elseif isfield(policy, 'mode')
        mode = lower(policy.mode);
    else
        mode = 'constant';
    end
else
    error('make_vsc_hvdc_dispatch_target: policy must be a string or struct');
end


function val = required_scalar_policy_field(policy, name, mode)
if ~isstruct(policy) || ~isfield(policy, name) || isempty(policy.(name))
    error('make_vsc_hvdc_dispatch_target: policy ''%s'' requires %s', ...
        mode, upper(name));
end
val = policy.(name);
if ~isscalar(val) || ~isnumeric(val) || ~isfinite(val)
    error('make_vsc_hvdc_dispatch_target: %s must be a finite scalar', ...
        upper(name));
end


function idx = selected_converters(policy, mpc, c, idx_fields, bus_fields)
idx = policy_first_field(policy, idx_fields);
if isempty(idx)
    buses = policy_first_field(policy, bus_fields);
    if isempty(buses)
        error('make_vsc_hvdc_dispatch_target: dispatch policy requires converters or buses');
    end
    idx = converter_indices_from_buses(mpc, c, buses);
end
idx = validate_converter_indices(idx, size(mpc.vsc, 1));


function val = policy_first_field(policy, names)
val = [];
if ~isstruct(policy)
    return;
end
for kk = 1:length(names)
    if isfield(policy, names{kk}) && ~isempty(policy.(names{kk}))
        val = policy.(names{kk});
        return;
    end
end


function idx = converter_indices_from_buses(mpc, c, buses)
buses = buses(:);
idx = zeros(length(buses), 1);
for kk = 1:length(buses)
    row = find(mpc.vsc(:, c.VSC_BUS) == buses(kk), 1);
    if isempty(row)
        error('make_vsc_hvdc_dispatch_target: no VSC converter at AC bus %g', buses(kk));
    end
    idx(kk) = row;
end


function idx = validate_converter_indices(idx, nv)
idx = idx(:);
if ~isnumeric(idx) || any(~isfinite(idx)) || any(idx < 1) || ...
        any(idx > nv) || any(idx ~= fix(idx))
    error('make_vsc_hvdc_dispatch_target: converter indices are invalid');
end
if length(unique(idx)) ~= length(idx)
    error('make_vsc_hvdc_dispatch_target: converter indices must be unique');
end


function w = normalized_weights(policy, n)
w = policy_first_field(policy, {'weights', 'weight'});
if isempty(w)
    w = ones(n, 1);
else
    w = w(:);
end
if length(w) ~= n || ~isnumeric(w) || any(~isfinite(w)) || any(w < 0) || ...
        sum(w) <= 0
    error('make_vsc_hvdc_dispatch_target: weights must be non-negative and match the converter list');
end
w = w / sum(w);


function validate_pdc_schedule(mode, mpc, idx, c)
active = find(mpc.vsc(:, c.VSC_STATUS) > 0);
if any(~ismember(idx, active))
    error('make_vsc_hvdc_dispatch_target: scheduled converters must be in service');
end
if any(mpc.vsc(idx, c.DC_MODE) == c.VSC_DC_VDC)
    error('make_vsc_hvdc_dispatch_target: VSC_DC_VDC converters cannot receive scheduled PDC_SET dispatch');
end
if strcmp(mode, 'droop_scheduled')
    if ~any(mpc.vsc(active, c.DC_MODE) == c.VSC_DC_VDC)
        error('make_vsc_hvdc_dispatch_target: droop_scheduled requires at least one active VSC_DC_VDC converter');
    end
    if any(mpc.vsc(idx, c.DC_MODE) ~= c.VSC_DC_DROOP)
        error('make_vsc_hvdc_dispatch_target: droop_scheduled converters must use VSC_DC_DROOP mode');
    end
end


function [idx, delta_qac, info] = reactive_schedule(policy, base, target, ...
        pdc_idx, c, QD)
nv = size(base.vsc, 1);
idx = zeros(0, 1);
delta_qac = zeros(nv, 1);
info = struct('policy', 'none', 'share', 0, 'delta_qac_mvar', 0, ...
    'weights_used', zeros(0, 1));
if ~isstruct(policy)
    return;
end

[qpol, nested] = reactive_policy_struct(policy);
mode = reactive_policy_mode(qpol, nested);
switch mode
    case {'none', 'constant'}
        return;
    case 'delta'
        [idx, dq] = reactive_delta_fields(qpol, nested, base, pdc_idx, c);
    case {'share_load', 'qac_share_load'}
        [idx, dq, info] = reactive_share_load_fields(qpol, nested, base, ...
            target, pdc_idx, c, QD);
    otherwise
        error('make_vsc_hvdc_dispatch_target: unknown QAC policy ''%s''', mode);
end
if length(dq) ~= length(idx)
    error('make_vsc_hvdc_dispatch_target: QAC deltas must match the QAC converter list');
end
idx = validate_converter_indices(idx, nv);
if any(base.vsc(idx, c.VSC_STATUS) <= 0)
    error('make_vsc_hvdc_dispatch_target: QAC scheduled converters must be in service');
end
delta_qac(idx) = dq(:);
if strcmp(info.policy, 'none')
    info.policy = 'delta';
    info.delta_qac_mvar = sum(dq);
end


function [qpol, nested] = reactive_policy_struct(policy)
if isfield(policy, 'qac') && isstruct(policy.qac)
    qpol = policy.qac;
    nested = 1;
else
    qpol = policy;
    nested = 0;
end


function mode = reactive_policy_mode(qpol, nested)
if nested
    mode = policy_first_field(qpol, {'policy', 'mode'});
else
    mode = policy_first_field(qpol, {'qac_policy', 'qac_mode'});
end
if isempty(mode)
    if nested
        has_delta = ~isempty(policy_first_field(qpol, ...
            {'delta', 'deltas', 'qac_delta', 'qac_deltas'}));
        has_share = ~isempty(policy_first_field(qpol, ...
            {'share', 'qac_share', 'load_share'}));
    else
        has_delta = ~isempty(policy_first_field(qpol, ...
            {'qac_delta', 'qac_deltas'}));
        has_share = ~isempty(policy_first_field(qpol, ...
            {'qac_share', 'qac_load_share'}));
    end
    if has_delta
        mode = 'delta';
    elseif has_share
        mode = 'share_load';
    else
        mode = 'none';
    end
end
mode = lower(mode);


function [idx, dq] = reactive_delta_fields(qpol, nested, mpc, pdc_idx, c)
idx = zeros(0, 1);
if nested
    dq = policy_first_field(qpol, {'delta', 'deltas', 'qac_delta'});
    if isempty(dq)
        return;
    end
    idx = policy_first_field(qpol, {'converters', 'converter_idx', ...
        'vsc', 'vsc_idx'});
    if isempty(idx)
        buses = policy_first_field(qpol, {'buses', 'ac_buses', ...
            'vsc_buses'});
        if ~isempty(buses)
            idx = converter_indices_from_buses(mpc, c, buses);
        end
    end
else
    dq = policy_first_field(qpol, {'qac_delta', 'qac_deltas'});
    if isempty(dq)
        return;
    end
    idx = policy_first_field(qpol, {'qac_converters', ...
        'qac_converter_idx', 'qac_vsc', 'qac_vsc_idx'});
    if isempty(idx)
        buses = policy_first_field(qpol, {'qac_buses', 'qac_ac_buses', ...
            'qac_vsc_buses'});
        if ~isempty(buses)
            idx = converter_indices_from_buses(mpc, c, buses);
        end
    end
end

dq = dq(:);
if isempty(idx) && length(dq) == length(pdc_idx)
    idx = pdc_idx;
elseif isempty(idx) && length(dq) == size(mpc.vsc, 1)
    idx = find(abs(dq) > 0);
    dq = dq(idx);
elseif isempty(idx)
    error('make_vsc_hvdc_dispatch_target: QAC schedule requires qac converters or qac buses');
end


function [idx, dq, info] = reactive_share_load_fields(qpol, nested, base, ...
        target, pdc_idx, c, QD)
if nested
    qac_share = policy_first_field(qpol, {'share', 'qac_share', ...
        'load_share'});
    idx = policy_first_field(qpol, {'converters', 'converter_idx', ...
        'vsc', 'vsc_idx'});
    bus_fields = {'buses', 'ac_buses', 'vsc_buses'};
    weight_fields = {'weights', 'weight'};
else
    qac_share = policy_first_field(qpol, {'qac_share', 'qac_load_share'});
    idx = policy_first_field(qpol, {'qac_converters', ...
        'qac_converter_idx', 'qac_vsc', 'qac_vsc_idx'});
    bus_fields = {'qac_buses', 'qac_ac_buses', 'qac_vsc_buses'};
    weight_fields = {'qac_weights', 'qac_weight'};
end
if isempty(qac_share) || ~isscalar(qac_share) || ~isnumeric(qac_share) || ...
        ~isfinite(qac_share)
    error('make_vsc_hvdc_dispatch_target: QAC share_load requires QAC_SHARE');
end
if isempty(idx)
    buses = policy_first_field(qpol, bus_fields);
    if ~isempty(buses)
        idx = converter_indices_from_buses(base, c, buses);
    elseif ~isempty(pdc_idx)
        idx = pdc_idx;
    else
        error('make_vsc_hvdc_dispatch_target: QAC share_load requires qac converters or qac buses');
    end
end

weights = policy_first_field(qpol, weight_fields);
if isempty(weights)
    weights = ones(length(idx), 1);
else
    weights = weights(:);
end
if length(weights) ~= length(idx) || ~isnumeric(weights) || ...
        any(~isfinite(weights)) || any(weights < 0) || sum(weights) <= 0
    error('make_vsc_hvdc_dispatch_target: QAC weights must be non-negative and match the QAC converter list');
end
weights = weights / sum(weights);

delta_qac_mvar = qac_share * sum(target.bus(:, QD) - base.bus(:, QD));
dq = delta_qac_mvar * weights;
info = struct('policy', 'share_load', 'share', qac_share, ...
    'delta_qac_mvar', delta_qac_mvar, 'weights_used', weights);
