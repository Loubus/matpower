function varargout = cpf_gen_redispatch_policy_state(op, varargin)
% cpf_gen_redispatch_policy_state - Incremental CPF generator redispatch.
% ::
%
%   TF = CPF_GEN_REDISPATCH_POLICY_STATE('enabled', BASE, TARGET, MPOPT)
%   [SRC, TGT, ST, CHANGED, IDX] = CPF_GEN_REDISPATCH_POLICY_STATE( ...
%       'apply', BASE, CURRENT, TARGET, MPOPT, ST, LAMBDA)
%
% Implements accepted-point incremental generator redispatch policies shared by
% CPF wrappers. The dynamic technology policy allocates rho*dP_load across
% available technologies, then across generators by remaining active-power
% reserve.
%
% See also runcpf_psse, mp.psse_gen_redispatch_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

switch lower(op)
    case 'enabled'
        varargout{1} = policy_enabled(varargin{:});
    case 'apply'
        [varargout{1:nargout}] = apply_policy(varargin{:});
    otherwise
        error('cpf_gen_redispatch_policy_state:unknown_op', ...
            'Unknown generator redispatch policy operation ''%s''.', op);
end

function TorF = policy_enabled(base, target, mpopt)
policy = gen_policy(base, target, mpopt);
TorF = is_dynamic_technology_policy(policy);

function [source, target, state, changed, idx] = apply_policy( ...
        base, current, target, mpopt, state, lam)
source = current;
changed = false;
idx = [];
if nargin < 5 || isempty(state) || ~isstruct(state) || ...
        ~isfield(state, 'initialized') || ~state.initialized
    state = init_state(base, target, mpopt);
end
if ~state.enabled || isempty(current) || ~isfield(current, 'gen') || ...
        ~isfield(current, 'bus')
    return;
end

[~, ~, ~, ~, ~, ~, PD] = idx_bus;
[~, PG] = idx_gen;
current_load = sum(current.bus(:, PD));
dP_load = current_load - state.anchor_load_mw;
dP_sched = state.rho * dP_load;
tol = 1e-9;
if abs(dP_sched) <= tol
    state.anchor_load_mw = current_load;
    state.anchor_lam = lam;
    state.last_report = empty_report(lam, dP_load, dP_sched, size(current.gen, 1));
    return;
end
if state.min_change_mw > 0 && abs(dP_sched) < state.min_change_mw
    state.last_report = empty_report(lam, dP_load, dP_sched, size(current.gen, 1));
    state.last_report.rho = state.rho;
    state.last_report.min_change_mw = state.min_change_mw;
    return;
end

state.gen_frozen = state.gen_frozen | frozen_p_rows(current, size(current.gen, 1));
[delta_pg, report] = allocate_pg(current, state, dP_sched, lam);
idx = find(abs(delta_pg) > tol);
state.anchor_load_mw = current_load;
state.anchor_lam = lam;
state.last_report = report;
state.last_delta_pg = delta_pg;
state.iterations = state.iterations + 1;
if isempty(state.history)
    state.history = report;
else
    state.history(end+1) = report;
end
if isempty(idx)
    return;
end

source.gen(:, PG) = source.gen(:, PG) + delta_pg;
target = update_target_pg(target, source, idx, PG);
state.applied_total_mw = state.applied_total_mw + sum(delta_pg);
changed = true;
source = attach_state(source, state);
target = attach_state(target, state);

function state = init_state(base, target, mpopt)
[~, ~, ~, ~, ~, ~, PD] = idx_bus;
ng = 0;
if isfield(base, 'gen')
    ng = size(base.gen, 1);
end
policy = gen_policy(base, target, mpopt);
state = struct( ...
    'initialized',        true, ...
    'enabled',            is_dynamic_technology_policy(policy), ...
    'policy',             policy, ...
    'rho',                1, ...
    'min_change_mw',      0, ...
    'gen_idx',            zeros(0, 1), ...
    'technology',         {repmat({''}, ng, 1)}, ...
    'technology_weights', struct(), ...
    'exclude_technology', {{'wind'}}, ...
    'anchor_load_mw',     0, ...
    'anchor_lam',         0, ...
    'gen_frozen',         false(ng, 1), ...
    'iterations',         0, ...
    'applied_total_mw',   0, ...
    'last_delta_pg',      zeros(ng, 1), ...
    'last_report',        empty_report(NaN, 0, 0, ng), ...
    'history',            []);
if ~state.enabled || isempty(base) || ~isfield(base, 'bus') || ...
        ~isfield(base, 'gen')
    return;
end
state.rho = policy_numeric(policy, {'rho', 'load_share', 'share'}, 1);
state.min_change_mw = policy_numeric(policy, ...
    {'min_change_mw', 'deadband_mw', 'min_mw'}, 0);
state.gen_idx = selected_generators(policy, base);
state.technology = technology_labels(policy, base, state.gen_idx);
state.technology_weights = technology_weights(policy);
state.exclude_technology = excluded_technologies(policy);
state.anchor_load_mw = sum(base.bus(:, PD));

function policy = gen_policy(base, target, mpopt)
policy = [];
if isfield(mpopt, 'vsc_mtdc') && isstruct(mpopt.vsc_mtdc) && ...
        isfield(mpopt.vsc_mtdc, 'cpf_policies') && ...
        ~isempty(mpopt.vsc_mtdc.cpf_policies) && ...
        isfield(mpopt.vsc_mtdc.cpf_policies, 'gen')
    policy = mpopt.vsc_mtdc.cpf_policies.gen;
elseif isstruct(base) && isfield(base, 'cpf_policies') && ...
        isstruct(base.cpf_policies) && isfield(base.cpf_policies, 'gen')
    policy = base.cpf_policies.gen;
elseif isstruct(target) && isfield(target, 'cpf_policies') && ...
        isstruct(target.cpf_policies) && isfield(target.cpf_policies, 'gen')
    policy = target.cpf_policies.gen;
end

function TorF = is_dynamic_technology_policy(policy)
TorF = false;
if isempty(policy) || ~isstruct(policy)
    return;
end
mode = policy_text(policy, {'policy', 'mode'}, '');
valid = {'technology_dynamic_participation', ...
    'dynamic_technology_participation', 'technology_participation'};
TorF = any(strcmp(normalize_key(mode), valid));

function idx = selected_generators(policy, mpc)
[GEN_BUS, ~, ~, ~, ~, ~, ~, GEN_STATUS] = idx_gen;
idx = policy_value(policy, {'gens', 'gen_idx', 'generators'}, []);
if isempty(idx)
    buses = policy_value(policy, {'gen_buses', 'buses'}, []);
    if ~isempty(buses)
        idx = generator_indices_from_buses(mpc, buses, GEN_BUS, GEN_STATUS);
    end
end
if isempty(idx)
    idx = find(mpc.gen(:, GEN_STATUS) > 0 & ~isload(mpc.gen));
end
idx = validate_generator_indices(idx, mpc, GEN_STATUS);

function idx = generator_indices_from_buses(mpc, buses, GEN_BUS, GEN_STATUS)
buses = buses(:);
idx = zeros(length(buses), 1);
is_load = isload(mpc.gen);
for kk = 1:length(buses)
    rows = find(mpc.gen(:, GEN_BUS) == buses(kk) & ...
        mpc.gen(:, GEN_STATUS) > 0 & ~is_load);
    if isempty(rows)
        error('cpf_gen_redispatch_policy_state:no_generator', ...
            'No in-service generator at bus %g.', buses(kk));
    elseif length(rows) > 1
        error('cpf_gen_redispatch_policy_state:multiple_generators', ...
            'Multiple generators at bus %g; use gens instead.', buses(kk));
    end
    idx(kk) = rows;
end

function idx = validate_generator_indices(idx, mpc, GEN_STATUS)
idx = idx(:);
ng = size(mpc.gen, 1);
if ~isnumeric(idx) || any(~isfinite(idx)) || any(idx < 1) || ...
        any(idx > ng) || any(idx ~= fix(idx))
    error('cpf_gen_redispatch_policy_state:bad_gen_idx', ...
        'Generator indices are invalid.');
end
if length(unique(idx)) ~= length(idx)
    error('cpf_gen_redispatch_policy_state:duplicate_gen_idx', ...
        'Generator indices must be unique.');
end
if any(mpc.gen(idx, GEN_STATUS) <= 0)
    error('cpf_gen_redispatch_policy_state:offline_gen', ...
        'Scheduled generators must be in service.');
end
if any(isload(mpc.gen(idx, :)))
    error('cpf_gen_redispatch_policy_state:dispatchable_load', ...
        'Scheduled rows must be generators, not dispatchable loads.');
end

function tech = technology_labels(policy, mpc, gen_idx)
ng = size(mpc.gen, 1);
tech = repmat({'default'}, ng, 1);
raw = policy_value(policy, ...
    {'technology', 'technologies', 'gen_technology', 'technology_by_gen'}, []);
if isempty(raw) && isfield(mpc, 'gen_technology')
    raw = mpc.gen_technology;
end
if isempty(raw)
    return;
end
raw = cellstr(string(raw(:)));
raw = internal_generator_values(raw, mpc, ng);
if length(raw) == ng
    for k = 1:ng
        tech{k} = normalize_key(raw{k});
    end
elseif length(raw) == length(gen_idx)
    for k = 1:length(gen_idx)
        tech{gen_idx(k)} = normalize_key(raw{k});
    end
else
    error('cpf_gen_redispatch_policy_state:bad_technology', ...
        'Generator technology list must match gens or all generators.');
end

function values = internal_generator_values(values, mpc, ng)
if length(values) == ng || ~isfield(mpc, 'order') || ...
        ~isfield(mpc.order, 'gen') || ...
        ~isfield(mpc.order.gen, 'status') || ...
        ~isfield(mpc.order.gen.status, 'on')
    return;
end
on = mpc.order.gen.status.on(:);
if isfield(mpc.order.gen, 'i2e') && ~isempty(mpc.order.gen.i2e)
    i2e = mpc.order.gen.i2e(:);
    if length(i2e) == ng && length(on) >= max(i2e)
        on = on(i2e);
    end
end
if length(on) == ng && length(values) >= max(on)
    values = values(on);
end

function weights = technology_weights(policy)
weights = struct();
raw = policy_value(policy, {'technology_weights', 'tech_weights'}, []);
if isempty(raw)
    weights.default = 1;
    weights.wind = 0;
    return;
end
if ~isstruct(raw)
    error('cpf_gen_redispatch_policy_state:bad_technology_weights', ...
        'Technology weights must be a struct.');
end
names = fieldnames(raw);
for k = 1:length(names)
    key = normalize_key(names{k});
    val = raw.(names{k});
    if ~isscalar(val) || ~isnumeric(val) || ~isfinite(val) || val < 0
        error('cpf_gen_redispatch_policy_state:bad_technology_weight', ...
            'Technology weight %s must be a nonnegative scalar.', names{k});
    end
    weights.(key) = val;
end

function names = excluded_technologies(policy)
raw = policy_value(policy, {'exclude_technologies', ...
    'excluded_technologies', 'exclude_technology'}, {'wind'});
names = cellstr(string(raw(:)));
for k = 1:length(names)
    names{k} = normalize_key(names{k});
end

function [delta_pg, report] = allocate_pg(mpc, state, dP_sched, lam)
[~, PG] = idx_gen;
ng = size(mpc.gen, 1);
delta_pg = zeros(ng, 1);
direction = sign(dP_sched);
amount_remaining = abs(dP_sched);
reserve = generator_reserve(mpc, state, direction);
eligible = reserve > 1e-8;
tech = state.technology;
tech_names = unique(tech(state.gen_idx));
tech_names = tech_names(:);
tech_reserve = zeros(length(tech_names), 1);
tech_pref = zeros(length(tech_names), 1);
for k = 1:length(tech_names)
    name = tech_names{k};
    rows = strcmp(tech, name);
    tech_reserve(k) = sum(reserve(rows));
    tech_pref(k) = technology_preference(state.technology_weights, name);
    if any(strcmp(name, state.exclude_technology))
        tech_pref(k) = 0;
    end
end
active_tech = tech_reserve > 1e-8 & tech_pref > 0;
tech_applied = zeros(length(tech_names), 1);

while amount_remaining > 1e-8 && any(active_tech)
    pref = tech_pref;
    pref(~active_tech) = 0;
    pref = pref / sum(pref);
    proposed = amount_remaining * pref;
    saturated = active_tech & proposed >= tech_reserve - 1e-8;
    if ~any(saturated)
        tech_applied = tech_applied + proposed;
        amount_remaining = 0;
    else
        tech_applied(saturated) = tech_applied(saturated) + ...
            tech_reserve(saturated);
        amount_remaining = amount_remaining - sum(tech_reserve(saturated));
        tech_reserve(saturated) = 0;
        active_tech(saturated) = false;
    end
end

for k = 1:length(tech_names)
    if tech_applied(k) <= 0
        continue;
    end
    rows = find(eligible & strcmp(tech, tech_names{k}));
    if isempty(rows)
        continue;
    end
    w = reserve(rows) / sum(reserve(rows));
    delta_pg(rows) = direction * tech_applied(k) * w;
end

applied = sum(delta_pg);
report = empty_report(lam, dP_sched / state.rho, dP_sched, ng);
report.lambda = lam;
report.dP_load = dP_sched / state.rho;
report.rho = state.rho;
report.min_change_mw = state.min_change_mw;
report.scheduled_mw = dP_sched;
report.applied_mw = applied;
report.unallocated_mw = dP_sched - applied;
report.gen_idx = find(abs(delta_pg) > 1e-9);
report.delta_pg = delta_pg(report.gen_idx);
report.technology = tech(report.gen_idx);
report.reserve = reserve(report.gen_idx);
report.technology_names = tech_names;
report.technology_applied_mw = direction * tech_applied;
report.technology_available_mw = generator_technology_reserve( ...
    reserve, tech, tech_names);
report.technology_preference = tech_pref;
report.pg_before = mpc.gen(:, PG);
report.pg_after = mpc.gen(:, PG) + delta_pg;

function total = generator_technology_reserve(reserve, tech, tech_names)
total = zeros(length(tech_names), 1);
for k = 1:length(tech_names)
    total(k) = sum(reserve(strcmp(tech, tech_names{k})));
end

function pref = technology_preference(weights, name)
if isfield(weights, name)
    pref = weights.(name);
elseif isfield(weights, 'default')
    pref = weights.default;
else
    pref = 0;
end

function reserve = generator_reserve(mpc, state, direction)
[~, ~, ~, NONE, BUS_I, BUS_TYPE] = idx_bus;
[GEN_BUS, PG, QG, ~, ~, ~, MBASE, GEN_STATUS, PMAX, PMIN] = idx_gen;
ng = size(mpc.gen, 1);
reserve = zeros(ng, 1);
selected = false(ng, 1);
selected(state.gen_idx) = true;
[~, bus_pos] = ismember(mpc.gen(:, GEN_BUS), mpc.bus(:, BUS_I));
for g = state.gen_idx(:)'
    if ~selected(g) || state.gen_frozen(g) || mpc.gen(g, GEN_STATUS) <= 0 || ...
            isload(mpc.gen(g, :)) || bus_pos(g) == 0 || ...
            mpc.bus(bus_pos(g), BUS_TYPE) == NONE
        continue;
    end
    if direction >= 0
        pmax = mpc.gen(g, PMAX);
        if ~isfinite(pmax)
            pmax = Inf;
        end
        cap = capability_pmax_at_q(mpc, g, pmax, MBASE, PG, QG);
        reserve(g) = max(0, min(pmax, cap) - mpc.gen(g, PG));
    else
        pmin = mpc.gen(g, PMIN);
        if ~isfinite(pmin)
            pmin = 0;
        end
        reserve(g) = max(0, mpc.gen(g, PG) - max(0, pmin));
    end
end

function pcap = capability_pmax_at_q(mpc, g, fallback, MBASE, PG, QG)
pcap = fallback;
if ~isfield(mpc, 'gen_capability') || ~isstruct(mpc.gen_capability)
    return;
end
if isfield(mpc.gen_capability, 'enforce') && ...
        numel(mpc.gen_capability.enforce) >= g && ...
        ~mpc.gen_capability.enforce(g)
    return;
end
Smax = vector_value(mpc.gen_capability, {'Snom', 'Smax', 'smax'}, g, ...
    mpc.gen(g, MBASE));
if ~isfinite(Smax) || Smax <= 0
    return;
end
type = vector_value(mpc.gen_capability, {'type', 'gen_type'}, g, 2);
P0 = mpc.gen(g, PG);
Q0 = mpc.gen(g, QG);
try
    sat0 = gen_capability_curve(P0, Q0, Smax, type);
    if sat0
        pcap = P0;
        return;
    end
    hi = min(fallback, max(P0, Smax));
    if ~isfinite(hi) || hi <= P0
        hi = Smax;
    end
    if hi <= P0
        pcap = P0;
        return;
    end
    [sat_hi, ~, ~, ~] = gen_capability_curve(hi, Q0, Smax, type);
    if ~sat_hi
        pcap = hi;
        return;
    end
    lo = P0;
    for k = 1:60
        mid = 0.5 * (lo + hi);
        sat = gen_capability_curve(mid, Q0, Smax, type);
        if sat
            hi = mid;
        else
            lo = mid;
        end
    end
    pcap = lo;
catch
end

function val = vector_value(s, names, idx, default)
val = default;
for k = 1:length(names)
    name = names{k};
    if ~isfield(s, name) || isempty(s.(name))
        continue;
    end
    raw = s.(name);
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw)
            val = raw;
        elseif numel(raw) >= idx
            val = raw(idx);
        end
        return;
    elseif iscell(raw)
        if isscalar(raw)
            val = raw{1};
        elseif numel(raw) >= idx
            val = raw{idx};
        end
        return;
    elseif isstring(raw)
        if isscalar(raw)
            val = char(raw);
        elseif numel(raw) >= idx
            val = char(raw(idx));
        end
        return;
    elseif ischar(raw)
        val = raw;
        return;
    end
end

function frozen = frozen_p_rows(mpc, ng)
frozen = false(ng, 1);
if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'gen_capability') || ...
        ~isstruct(mpc.psse.gen_capability)
    return;
end
st = mpc.psse.gen_capability;
if isfield(st, 'frozen_p') && ~isempty(st.frozen_p)
    n = min(ng, numel(st.frozen_p));
    frozen(1:n) = st.frozen_p(1:n) ~= 0;
elseif isfield(st, 'frozen') && ~isempty(st.frozen)
    n = min(ng, numel(st.frozen));
    frozen(1:n) = st.frozen(1:n) ~= 0;
end

function target = update_target_pg(target, source, idx, PG)
if isempty(target) || ~isfield(target, 'gen') || isempty(target.gen) || ...
        size(target.gen, 1) < max(idx)
    return;
end
target.gen(idx, PG) = source.gen(idx, PG);

function mpc = attach_state(mpc, state)
if isempty(mpc)
    return;
end
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    mpc.psse = struct();
end
mpc.psse.gen_redispatch = state;

function report = empty_report(lam, dP_load, dP_sched, ng)
if nargin < 4
    ng = 0;
end
report = struct( ...
    'lambda',                   lam, ...
    'dP_load',                  dP_load, ...
    'rho',                      NaN, ...
    'min_change_mw',            0, ...
    'scheduled_mw',             dP_sched, ...
    'applied_mw',               0, ...
    'unallocated_mw',           dP_sched, ...
    'gen_idx',                  zeros(0, 1), ...
    'delta_pg',                 zeros(0, 1), ...
    'technology',               {cell(0, 1)}, ...
    'reserve',                  zeros(0, 1), ...
    'technology_names',         {cell(0, 1)}, ...
    'technology_applied_mw',    zeros(0, 1), ...
    'technology_available_mw',  zeros(0, 1), ...
    'technology_preference',    zeros(0, 1), ...
    'pg_before',                zeros(ng, 1), ...
    'pg_after',                 zeros(ng, 1));

function val = policy_value(policy, names, default)
val = default;
if isempty(policy) || ~isstruct(policy)
    return;
end
for k = 1:length(names)
    if isfield(policy, names{k}) && ~isempty(policy.(names{k}))
        val = policy.(names{k});
        return;
    end
end

function txt = policy_text(policy, names, default)
txt = policy_value(policy, names, default);
if isstring(txt)
    txt = char(txt);
end
if ~ischar(txt)
    error('cpf_gen_redispatch_policy_state:policy_text', ...
        'Redispatch policy text fields must be char or string.');
end

function val = policy_numeric(policy, names, default)
val = policy_value(policy, names, default);
if ~isscalar(val) || ~isnumeric(val) || ~isfinite(val)
    error('cpf_gen_redispatch_policy_state:policy_numeric', ...
        'Redispatch policy numeric fields must be finite scalars.');
end

function key = normalize_key(raw)
key = lower(strtrim(char(raw)));
key = strrep(key, '-', '_');
key = regexprep(key, '\s+', '_');
key = matlab.lang.makeValidName(key);
