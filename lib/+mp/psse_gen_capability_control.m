function [dm_next, state] = psse_gen_capability_control(task, mm, nm, dm, mpopt, mpx, state)
% psse_gen_capability_control - Executes generator capability control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_GEN_CAPABILITY_CONTROL(TASK, MM, NM, DM,
%       MPOPT, MPX, STATE)
%
% Applies the shared generator P-Q capability curve policy to a solved PSS/E
% PF/CPF source case. Saturated generators are frozen at the projected P/Q
% point and rebuilt for another solve. In CPF, the matching target source is
% also frozen so the accepted transfer removes that generator from further
% active/reactive participation.
%
% See also mp.task_pf_psse, mp.task_cpf_psse, gen_capability_curve.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

dm_next = [];
if nargin < 7 || isempty(state) || ~isstruct(state)
    state = empty_state();
    if isfield(dm.source, 'psse') && ...
            isfield(dm.source.psse, 'gen_capability') && ...
            isstruct(dm.source.psse.gen_capability)
        state = merge_source_state(state, dm.source.psse.gen_capability);
    end
end

if ~gen_capability_enabled(mpopt) || ~isfield(dm.source, 'gen') || ...
        isempty(dm.source.gen)
    return;
end

[PQ, ~, REF, ~, BUS_I, BUS_TYPE] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, ~, ~, GEN_STATUS] = idx_gen;

dm = sync_solved_data_model(mm, nm, dm, mpopt);
source0 = sync_source_gen_solution(dm.source, dm);
source1 = source0;
target1 = [];
if isprop(task, 'psse_target_source') && ~isempty(task.psse_target_source)
    target1 = task.psse_target_source;
end

ng = size(source1.gen, 1);
state = ensure_freeze_state(state, ng);
if ~isfield(state, 'frozen_values') || size(state.frozen_values, 1) < ng
    frozen_values = NaN(ng, 4);
    if isfield(state, 'frozen_values') && ~isempty(state.frozen_values)
        n = min(size(state.frozen_values, 1), ng);
        frozen_values(1:n, :) = state.frozen_values(1:n, :);
    end
    state.frozen_values = frozen_values;
end
source1 = apply_frozen_values(source1, state, ...
    PQ, GEN_BUS, BUS_I, BUS_TYPE);
target1 = apply_frozen_values(target1, state, ...
    PQ, GEN_BUS, BUS_I, BUS_TYPE);
changed = false(ng, 1);
report = empty_report();
eval_report = empty_eval_report();
tol = 1e-8;

for g = 1:ng
    meta_g = gen_capability_metadata_row(source1, g);
    if (state.frozen_p(g) && state.frozen_q(g)) || ...
            source1.gen(g, GEN_STATUS) <= 0 || ...
            isload(source1.gen(g, :)) || ...
            ~gen_capability_row_enabled(source1, meta_g)
        continue;
    end
    if is_slack_gen(source1, g, GEN_BUS, BUS_I, BUS_TYPE, REF)
        continue;
    end

    P0 = source1.gen(g, PG);
    Q0 = source1.gen(g, QG);
    Smax = gen_capability_metadata_or_option_value(source1, ...
        gen_capability_options(mpopt), {'Snom', 'Smax', 'smax'}, ...
        {'capability_gen_smax'}, meta_g, meta_g, ...
        gen_capability_default_smax(source1, g), 'psse_gen_capability');
    type = gen_capability_metadata_or_option_value(source1, ...
        gen_capability_options(mpopt), {'type', 'gen_type'}, ...
        {'capability_gen_type'}, meta_g, meta_g, 2, ...
        'psse_gen_capability');
    try
        [sat, Psat, Qsat, Ssat, info] = ...
            gen_capability_curve(P0, Q0, Smax, type);
    catch me
        error('psse_gen_capability: generator row %d capability evaluation failed: %s', ...
            g, me.message);
    end
    eval_report = append_eval_report(eval_report, source1, g, meta_g, ...
        P0, Q0, sat, Psat, Qsat, Ssat, info, GEN_BUS);
    if ~sat
        continue;
    end

    old_vals = source1.gen(g, [PG QG QMAX QMIN]);
    new_vals = old_vals;
    p_changed = abs(Psat - P0) > tol && ~state.frozen_p(g);
    q_changed = abs(Qsat - Q0) > tol;
    if p_changed
        new_vals(1) = Psat;
    end
    if q_changed
        new_vals(2:4) = Qsat;
    end
    if all(abs(old_vals - new_vals) <= tol) && ...
            (~q_changed || gen_bus_is_pq(source1, g, GEN_BUS, BUS_I, BUS_TYPE, PQ))
        continue;
    end

    source1.gen(g, [PG QG QMAX QMIN]) = new_vals;
    if q_changed
        source1 = set_gen_bus_type(source1, g, PQ, GEN_BUS, BUS_I, BUS_TYPE);
    end
    target1 = apply_target_freeze(target1, g, new_vals, ...
        p_changed, q_changed, PQ, GEN_BUS, BUS_I, BUS_TYPE);

    changed(g) = true;
    state.frozen_p(g) = state.frozen_p(g) || p_changed;
    state.frozen_q(g) = state.frozen_q(g) || q_changed;
    state.frozen(g) = state.frozen_p(g) || state.frozen_q(g);
    if p_changed
        state.frozen_values(g, 1) = new_vals(1);
    end
    if q_changed
        state.frozen_values(g, 2:4) = new_vals(2:4);
    end
    report = append_report(report, source0, g, meta_g, P0, Q0, ...
        Psat, Qsat, Ssat, info, GEN_BUS);
end

if any(changed)
    state.iterations = state.iterations + 1;
    state.changed_last = find(changed);
    state.report = report;
    state.event_history = append_event_history(state, report);
    state.last_eval = eval_report;
    source1.psse.gen_capability = state;
    if ~isempty(target1)
        if ~isfield(target1, 'psse') || isempty(target1.psse)
            target1.psse = struct();
        end
        target1.psse.gen_capability = state;
        task.psse_target_source = target1;
    end
    dm_next = task.data_model_build(source1, task.dmc, mpopt, mpx);
else
    state.changed_last = [];
    state.last_eval = eval_report;
    if ~isfield(dm.source, 'psse') || isempty(dm.source.psse)
        dm.source.psse = struct();
    end
    dm.source.psse.gen_capability = state;
end

function TorF = gen_capability_enabled(mpopt)
TorF = false;
if ~isfield(mpopt, 'vsc_mtdc') || ...
        ~isfield(mpopt.vsc_mtdc, 'capability_gen_enforce') || ...
        isempty(mpopt.vsc_mtdc.capability_gen_enforce)
    return;
end
raw = mpopt.vsc_mtdc.capability_gen_enforce;
if islogical(raw) || isnumeric(raw)
    TorF = any(raw(:) ~= 0);
elseif ischar(raw) || isstring(raw)
    TorF = any(strcmpi(char(raw), {'1', 'true', 'on', 'yes'}));
end

function opt = gen_capability_options(mpopt)
opt = struct();
if isfield(mpopt, 'vsc_mtdc') && isstruct(mpopt.vsc_mtdc)
    opt = mpopt.vsc_mtdc;
end

function dm = sync_solved_data_model(mm, nm, dm, mpopt)
if isempty(mm) || isempty(nm) || isempty(dm) || ...
        ~isobject(mm) || ~ismethod(mm, 'data_model_update')
    return;
end
try
    if ismethod(dm, 'copy')
        dm1 = dm.copy();
    else
        dm1 = dm;
    end
    dm = mm.data_model_update(nm, dm1, mpopt);
catch
end

function TorF = gen_capability_row_enabled(mpc, g)
TorF = true;
if ~isfield(mpc, 'gen_capability') || ...
        ~isstruct(mpc.gen_capability) || ...
        ~isfield(mpc.gen_capability, 'enforce') || ...
        isempty(mpc.gen_capability.enforce)
    return;
end
raw = mpc.gen_capability.enforce;
if islogical(raw) || isnumeric(raw)
    if isscalar(raw)
        TorF = raw ~= 0;
    elseif numel(raw) >= g
        TorF = raw(g) ~= 0;
    else
        TorF = false;
    end
end

function row = gen_capability_metadata_row(mpc, g)
row = g;
if isfield(mpc, 'order') && isfield(mpc.order, 'gen') && ...
        isfield(mpc.order.gen, 'status') && ...
        isfield(mpc.order.gen.status, 'on') && ...
        numel(mpc.order.gen.status.on) >= g
    row = mpc.order.gen.status.on(g);
end

function TorF = is_slack_gen(mpc, g, GEN_BUS, BUS_I, BUS_TYPE, REF)
row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
TorF = ~isempty(row) && mpc.bus(row, BUS_TYPE) == REF;

function TorF = gen_bus_is_pq(mpc, g, GEN_BUS, BUS_I, BUS_TYPE, PQ)
row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
TorF = ~isempty(row) && mpc.bus(row, BUS_TYPE) == PQ;

function mpc = set_gen_bus_type(mpc, g, type, GEN_BUS, BUS_I, BUS_TYPE)
row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
if ~isempty(row)
    mpc.bus(row, BUS_TYPE) = type;
end

function target = apply_target_freeze(target, g, new_vals, ...
        p_changed, q_changed, PQ, GEN_BUS, BUS_I, BUS_TYPE)
if isempty(target) || ~isfield(target, 'gen') || size(target.gen, 1) < g
    return;
end
[~, PG, QG, QMAX, QMIN] = idx_gen;
if p_changed
    target.gen(g, PG) = new_vals(1);
end
if q_changed
    target.gen(g, [QG QMAX QMIN]) = new_vals(2:4);
    target = set_gen_bus_type(target, g, PQ, GEN_BUS, BUS_I, BUS_TYPE);
end

function source = sync_source_gen_solution(source, dm)
% Copy solved generator P/Q from the data model table into the source MPC.
[~, PG, QG] = idx_gen;
if ~isfield(source, 'gen') || isempty(source.gen) || ...
        ~isprop(dm, 'elements') || ~isfield(dm.elements, 'gen') || ...
        isempty(dm.elements.gen) || ~isprop(dm.elements.gen, 'tab')
    return;
end
tab = dm.elements.gen.tab;
if ~all(ismember({'pg', 'qg'}, tab.Properties.VariableNames))
    return;
end
n = min(size(source.gen, 1), height(tab));
pg = tab.pg(1:n);
qg = tab.qg(1:n);
if isfield(source, 'baseMVA') && source.baseMVA > 0 && ...
        max(abs(pg)) < 10 && max(abs(source.gen(1:n, PG))) > 10
    pg = pg * source.baseMVA;
    qg = qg * source.baseMVA;
end
source.gen(1:n, PG) = pg;
source.gen(1:n, QG) = qg;

function state = empty_state()
state = struct( ...
    'initialized', 1, ...
    'iterations', 0, ...
    'frozen', [], ...
    'frozen_p', [], ...
    'frozen_q', [], ...
    'frozen_values', [], ...
    'changed_last', [], ...
    'event_history', {{}}, ...
    'report', empty_report());

function state = merge_source_state(state, source_state)
names = {'iterations', 'frozen', 'frozen_p', 'frozen_q', ...
    'frozen_values', 'changed_last', 'event_history', 'report'};
for kk = 1:length(names)
    name = names{kk};
    if isfield(source_state, name)
        state.(name) = source_state.(name);
    end
end

function history = append_event_history(state, report)
if isfield(state, 'event_history') && iscell(state.event_history)
    history = state.event_history;
else
    history = {};
end
history{end+1, 1} = report;

function state = ensure_freeze_state(state, ng)
names = {'frozen_p', 'frozen_q', 'frozen'};
for kk = 1:numel(names)
    name = names{kk};
    vals = false(ng, 1);
    if isfield(state, name) && ~isempty(state.(name))
        n = min(numel(state.(name)), ng);
        vals(1:n) = state.(name)(1:n);
    end
    state.(name) = vals;
end
if ~any(state.frozen_p) && ~any(state.frozen_q) && any(state.frozen)
    state.frozen_p = state.frozen;
    state.frozen_q = state.frozen;
end
state.frozen = state.frozen_p | state.frozen_q;

function mpc = apply_frozen_values(mpc, state, ...
        PQ, GEN_BUS, BUS_I, BUS_TYPE)
if isempty(mpc) || ~isfield(mpc, 'gen') || isempty(mpc.gen) || ...
        ~isfield(state, 'frozen_values') || isempty(state.frozen_values)
    return;
end
[~, PG, QG, QMAX, QMIN] = idx_gen;
ng = min([size(mpc.gen, 1), numel(state.frozen), ...
    size(state.frozen_values, 1)]);
for g = find(state.frozen(1:ng)).'
    vals = state.frozen_values(g, :);
    if state.frozen_p(g) && isfinite(vals(1))
        mpc.gen(g, PG) = vals(1);
    end
    if state.frozen_q(g) && all(isfinite(vals(2:4)))
        mpc.gen(g, [QG QMAX QMIN]) = vals(2:4);
        mpc = set_gen_bus_type(mpc, g, PQ, GEN_BUS, BUS_I, BUS_TYPE);
    end
end

function report = empty_report()
report = struct( ...
    'changed_idx', [], ...
    'bus', [], ...
    'active_limit', {{}}, ...
    'P', [], ...
    'Q', [], ...
    'P_saturated', [], ...
    'Q_saturated', [], ...
    'S_saturated', [], ...
    'Smax', [], ...
    'gen_type_code', [], ...
    'gen_type', {{}});

function report = empty_eval_report()
report = struct( ...
    'idx', [], ...
    'external_idx', [], ...
    'bus', [], ...
    'P', [], ...
    'Q', [], ...
    'sat', [], ...
    'P_saturated', [], ...
    'Q_saturated', [], ...
    'S_saturated', [], ...
    'Smax', [], ...
    'margin', [], ...
    'active_limit', {{}}, ...
    'gen_type', {{}});

function report = append_report(report, mpc, g, meta_g, P0, Q0, Psat, ...
        Qsat, Ssat, info, GEN_BUS)
report.changed_idx(end+1, 1) = meta_g;
report.bus(end+1, 1) = mpc.gen(g, GEN_BUS);
report.active_limit{end+1, 1} = info.active_limit;
report.P(end+1, 1) = P0;
report.Q(end+1, 1) = Q0;
report.P_saturated(end+1, 1) = Psat;
report.Q_saturated(end+1, 1) = Qsat;
report.S_saturated(end+1, 1) = Ssat;
report.Smax(end+1, 1) = info.Smax;
report.gen_type_code(end+1, 1) = info.gen_type_code;
report.gen_type{end+1, 1} = info.gen_type;

function report = append_eval_report(report, mpc, g, meta_g, P0, Q0, sat, ...
        Psat, Qsat, Ssat, info, GEN_BUS)
report.idx(end+1, 1) = g;
report.external_idx(end+1, 1) = meta_g;
report.bus(end+1, 1) = mpc.gen(g, GEN_BUS);
report.P(end+1, 1) = P0;
report.Q(end+1, 1) = Q0;
report.sat(end+1, 1) = sat;
report.P_saturated(end+1, 1) = Psat;
report.Q_saturated(end+1, 1) = Qsat;
report.S_saturated(end+1, 1) = Ssat;
report.Smax(end+1, 1) = info.Smax;
report.margin(end+1, 1) = info.margin;
report.active_limit{end+1, 1} = info.active_limit;
report.gen_type{end+1, 1} = info.gen_type;
