function [dm_next, state] = psse_genq_control(task, ~, ~, dm, mpopt, mpx, state)
% psse_genq_control - Executes PSS/E generator Q/voltage control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_GENQ_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Applies the outer-loop behavior for preserved PSS/E GENERATOR DATA
% metadata. Local PV generators use the solved QG and are converted to PQ
% when VAR limits bind. Remote regulating groups search for total group Q
% using bracket/secant state, distribute Q by RMPCT with individual limits,
% and rebuild the data model when QG or bus types change.
%
% See also mp.psse_genq_states, mp.psse_genq_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

dm_next = [];
if nargin < 7
    state = [];
end

%% no preserved PSS/E generator metadata, no PSS/E generator Q control
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'genq') || ...
        isempty(dm.source.psse.genq.num)
    state = [];
    return;
end

%% initialize control state from preserved RAW metadata
if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = mp.psse_genq_states(dm.source);
end

if ~any(state.active)
    dm.source = mp.psse_genq_update(dm.source, state);
    return;
end

%% stop after the PSS/E tap/shunt/generator adjustment iteration limit
state.iterations = state.iterations + 1;
if state.iterations > state.max_iter
    state.max_iter_reached = 1;
    state.changed_last = 0;
    dm.source = mp.psse_genq_update(dm.source, state);
    return;
end

bus = dm.elements.bus;
vm = bus.tab.vm;
solved_q = read_solved_q(dm);

q0 = state.current_q;
limited0 = state.limited;
state = sync_solved_state(state, solved_q, vm);
state = limit_local_gens(state);
sens = remote_group_sensitivities(dm, mpopt, state, vm);
state = control_remote_groups(state, vm, sens);
state = score_state(state);
state = refresh_codes(state);

controlled = state.remote | state.limited | limited0;
changed = any(abs(state.current_q(controlled) - q0(controlled)) > state.qtol) || ...
    any(state.limited ~= limited0);
if changed
    q_changed = false(size(state.current_q));
    q_changed(controlled) = abs(state.current_q(controlled) - ...
        q0(controlled)) > state.qtol;
    state.changed_last = nnz(q_changed | state.limited ~= limited0);
    state.num_adjustments = state.num_adjustments + state.changed_last;
    mpc = mp.psse_genq_update(dm.source, state);
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    state.changed_last = 0;
    dm.source = mp.psse_genq_update(dm.source, state);
end

function qg = read_solved_q(dm)
% Return solved generator Q values from the data model when available.
[~, ~, QG] = idx_gen;
qg = dm.source.gen(:, QG);
try
    gen = dm.elements.gen;
    if istable(gen.tab) && ismember('qg', gen.tab.Properties.VariableNames)
        qg = gen.tab.qg;
    end
catch
end

function state = sync_solved_state(state, solved_q, vm)
% Synchronize solved QG and voltage observations into the control state.
state.last_vm_final(:) = NaN;
state.last_margin(:) = NaN;
state.at_min(:) = false;
state.at_max(:) = false;
idx = find(state.active & state.gen_idx > 0);
for kk = idx(:)'
    gi = state.gen_idx(kk);
    if gi > 0 && gi <= length(solved_q) && ~isnan(solved_q(gi))
        state.current_q(kk) = solved_q(gi);
    end
    rb = state.reg_bus_idx(kk);
    if rb > 0 && rb <= length(vm)
        state.last_vm_final(kk) = vm(rb);
        state.last_margin(kk) = state.vs(kk) - vm(rb);
    end
    state.at_min(kk) = ~state.swing(kk) && ...
        state.current_q(kk) <= state.qmin(kk) + state.qtol;
    state.at_max(kk) = ~state.swing(kk) && ...
        state.current_q(kk) >= state.qmax(kk) - state.qtol;
end

function state = limit_local_gens(state)
% Convert local PV controllers to fixed-Q PQ controllers when limits bind.
if ~state.varlim_enabled
    return;
end
idx = find(state.controllable_local & ~state.swing);
for kk = idx(:)'
    if state.limited(kk)
        state.current_q(kk) = min(max(state.current_q(kk), ...
            state.qmin(kk)), state.qmax(kk));
        state.at_min(kk) = state.current_q(kk) <= state.qmin(kk) + state.qtol;
        state.at_max(kk) = state.current_q(kk) >= state.qmax(kk) - state.qtol;
    elseif state.current_q(kk) > state.qmax(kk) + state.qtol
        state.current_q(kk) = state.qmax(kk);
        state.at_max(kk) = true;
        state.at_min(kk) = false;
        state.limited(kk) = true;
    elseif state.current_q(kk) < state.qmin(kk) - state.qtol
        state.current_q(kk) = state.qmin(kk);
        state.at_min(kk) = true;
        state.at_max(kk) = false;
        state.limited(kk) = true;
    else
        state.at_min(kk) = state.current_q(kk) <= state.qmin(kk) + state.qtol;
        state.at_max(kk) = state.current_q(kk) >= state.qmax(kk) - state.qtol;
        state.limited(kk) = false;
    end
end

function state = control_remote_groups(state, vm, sens)
% Select new remote-generator group Q targets from bracket/secant state.
for gg = 1:length(state.group.reg_bus_idx)
    members_all = state.group.members{gg};
    reg = state.group.reg_bus_idx(gg);
    if reg <= 0 || reg > length(vm) || isempty(members_all)
        continue;
    end
    v = vm(reg);
    target = state.group.target_vs(gg);
    cur_total = sum(state.current_q(members_all));
    state.group.vact(gg) = v;
    state.group.margin(gg) = target - v;
    state.group.current_q(gg) = cur_total;

    err = v - target;
    if err < -state.vtol
        state.group.qlo(gg) = cur_total;
        state.group.vlo(gg) = v;
    elseif err > state.vtol
        state.group.qhi(gg) = cur_total;
        state.group.vhi(gg) = v;
    else
        state.group.last_q(gg) = cur_total;
        state.group.last_v(gg) = v;
        continue;
    end

    movable = members_all(state.active(members_all) & ...
        ~state.swing(members_all) & ~state.limited(members_all));
    if isempty(movable)
        state.group.all_limited(gg) = 1;
        state.group.last_q(gg) = cur_total;
        state.group.last_v(gg) = v;
        continue;
    end

    [qmin_total, qmax_total] = group_bounds(state, members_all, movable);
    state.group.qmin(gg) = qmin_total;
    state.group.qmax(gg) = qmax_total;
    q_next = next_total_q(state, gg, v, target, cur_total, ...
        qmin_total, qmax_total, sens(gg));
    [state.current_q, at_min, at_max] = distribute_q(state, members_all, ...
        movable, q_next);
    if state.varlim_enabled
        newly_limited = movable(at_min(movable) | at_max(movable));
        state.limited(newly_limited) = true;
    end
    state.at_min(members_all) = at_min(members_all);
    state.at_max(members_all) = at_max(members_all);
    state.group.current_q(gg) = sum(state.current_q(members_all));
    state.group.all_limited(gg) = all(state.limited(movable) | state.swing(movable));
    state.group.last_q(gg) = cur_total;
    state.group.last_v(gg) = v;
end

function [qmin_total, qmax_total] = group_bounds(state, members_all, movable)
fixed = setdiff(members_all(:), movable(:));
fixed_q = sum(state.current_q(fixed));
if state.varlim_enabled
    qmin_total = fixed_q + sum(state.qmin(movable));
    qmax_total = fixed_q + sum(state.qmax(movable));
else
    span = max(sum(abs(state.qmax(members_all) - state.qmin(members_all))), 1);
    qmin_total = sum(state.current_q(members_all)) - span;
    qmax_total = sum(state.current_q(members_all)) + span;
end

function q_next = next_total_q(state, gg, v, target, cur_total, qmin_total, qmax_total, sens)
% Compute the next group Q total using bracketed secant when possible.
span = max(qmax_total - qmin_total, 0);
have_bracket = ~isnan(state.group.qlo(gg)) && ~isnan(state.group.qhi(gg)) && ...
    ~isnan(state.group.vlo(gg)) && ~isnan(state.group.vhi(gg)) && ...
    abs(state.group.vhi(gg) - state.group.vlo(gg)) > eps;
if have_bracket
    q_next = state.group.qlo(gg) + ...
        (target - state.group.vlo(gg)) * ...
        (state.group.qhi(gg) - state.group.qlo(gg)) / ...
        (state.group.vhi(gg) - state.group.vlo(gg));
elseif isfinite(sens) && abs(sens) > eps
    q_next = cur_total + (target - v) / sens;
else
    q_next = cur_total;
end
if span > 0
    q_next = min(max(q_next, qmin_total), qmax_total);
else
    q_next = cur_total;
end

function sens = remote_group_sensitivities(dm, mpopt, state, vm)
% Linearized d|Vreg|/dQgroup sensitivities at the solved AC state.
[~, PV, REF, ~, ~, BUS_TYPE, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
sens = NaN(length(state.group.reg_bus_idx), 1);
if isempty(sens)
    return;
end
mpc = dm.source;
bus = mpc.bus;
gen = mpc.gen;
branch = mpc.branch;
bus(:, VM) = vm;
try
    btab = dm.elements.bus.tab;
    if istable(btab) && ismember('va', btab.Properties.VariableNames)
        bus(:, VA) = btab.va;
    end
catch
end
try
    [~, pv, pq] = bustypes(bus, gen);
    if isempty(pq)
        return;
    end
    [Ybus, ~, ~] = makeYbus(mpc.baseMVA, bus, branch);
    V = bus(:, VM) .* exp(1j * pi/180 * bus(:, VA));
    [dSbus_dVa, dSbus_dVm] = dSbus_dV(Ybus, V);
    [~, neg_dSd_dVm] = makeSbus(mpc.baseMVA, bus, gen, mpopt, abs(V));
    dSbus_dVm = dSbus_dVm - neg_dSd_dVm;
    pvpq = [pv; pq];
    npvpq = length(pvpq);
    npq = length(pq);
    J = [ real(dSbus_dVa(pvpq, pvpq)) real(dSbus_dVm(pvpq, pq));
          imag(dSbus_dVa(pq, pvpq))   imag(dSbus_dVm(pq, pq)) ];
    ng = length(sens);
    pq_pos = zeros(size(bus, 1), 1);
    pq_pos(pq) = 1:npq;
    max_rhs = 0;
    for gg = 1:ng
        max_rhs = max_rhs + length(state.group.members{gg});
    end
    rhs_i = zeros(max_rhs, 1);
    rhs_j = zeros(max_rhs, 1);
    rhs_v = zeros(max_rhs, 1);
    nrhs = 0;
    for gg = 1:ng
        members_all = state.group.members{gg};
        movable = members_all(state.active(members_all) & ...
            ~state.swing(members_all) & ~state.limited(members_all));
        if isempty(movable)
            continue;
        end
        weights = state.rmpct(movable);
        weights(isnan(weights) | weights <= 0) = 100;
        share = weights / sum(weights);
        for kk = 1:length(movable)
            b = state.bus_idx(movable(kk));
            if b > 0 && b <= size(bus, 1) && bus(b, BUS_TYPE) ~= REF
                pos = pq_pos(b);
                if pos > 0
                    nrhs = nrhs + 1;
                    rhs_i(nrhs) = npvpq + pos;
                    rhs_j(nrhs) = gg;
                    rhs_v(nrhs) = share(kk) / mpc.baseMVA;
                end
            end
        end
    end
    if nrhs == 0
        return;
    end
    rhs = sparse(rhs_i(1:nrhs), rhs_j(1:nrhs), rhs_v(1:nrhs), ...
        npvpq + npq, ng);
    dx = J \ rhs;
    for gg = 1:ng
        reg = state.group.reg_bus_idx(gg);
        if reg > 0 && reg <= size(bus, 1) && bus(reg, BUS_TYPE) ~= PV
            pos = pq_pos(reg);
            if pos > 0
                sens(gg) = dx(npvpq + pos, gg);
            end
        end
    end
catch
end

function [q, at_min, at_max] = distribute_q(state, members_all, movable, q_total)
% Distribute a requested total Q by RMPCT, clamping individual limits.
q = state.current_q;
at_min = state.at_min;
at_max = state.at_max;
fixed = setdiff(members_all(:), movable(:));
target_movable = q_total - sum(q(fixed));
current_movable = sum(q(movable));
delta = target_movable - current_movable;
remaining = movable(:);

while ~isempty(remaining) && abs(delta) > state.qtol
    weights = state.rmpct(remaining);
    weights(isnan(weights) | weights <= 0) = 100;
    share = weights / sum(weights);
    q_try = q(remaining) + delta * share;
    if state.varlim_enabled
        q_clamped = min(max(q_try, state.qmin(remaining)), state.qmax(remaining));
    else
        q_clamped = q_try;
    end
    q(remaining) = q_clamped;
    hit = state.varlim_enabled & ...
        (q_clamped <= state.qmin(remaining) + state.qtol | ...
         q_clamped >= state.qmax(remaining) - state.qtol);
    delta = target_movable - sum(q(movable));
    if ~any(hit)
        break;
    end
    remaining = remaining(~hit);
end

if state.varlim_enabled
    at_min(members_all) = q(members_all) <= state.qmin(members_all) + state.qtol;
    at_max(members_all) = q(members_all) >= state.qmax(members_all) - state.qtol;
else
    at_min(members_all) = false;
    at_max(members_all) = false;
end

function state = score_state(state)
% Update report margins for controllers that still regulate voltage.
idx = find(state.active & state.reg_bus_idx > 0 & ~state.limited & ...
    ~state.swing);
margin = state.last_margin(idx);
margin = margin(~isnan(margin));
margin(abs(margin) <= state.vtol) = 0;
state.last_violations = nnz(margin ~= 0);
state.last_violation_sum = sum(abs(margin));
state.last_score = state.last_violations * 1e6 + state.last_violation_sum;

function state = refresh_codes(state)
% Refresh numeric and text final status codes.
for kk = 1:state.n
    if state.unmapped(kk)
        state.code_final(kk) = -9;
        state.code_label{kk} = 'UNMAPPED';
    elseif ~state.active(kk)
        state.code_final(kk) = 0;
        state.code_label{kk} = 'OFF';
    elseif state.swing(kk)
        state.code_final(kk) = 3;
        state.code_label{kk} = 'SWING';
    elseif state.limited(kk)
        state.code_final(kk) = -2;
        if state.at_min(kk)
            state.code_label{kk} = 'QMIN';
        elseif state.at_max(kk)
            state.code_label{kk} = 'QMAX';
        else
            state.code_label{kk} = 'LIMITED';
        end
    elseif state.remote(kk)
        state.code_final(kk) = 2;
        state.code_label{kk} = 'REMOTE';
    else
        state.code_final(kk) = 2;
        state.code_label{kk} = 'LOCAL';
    end
end
