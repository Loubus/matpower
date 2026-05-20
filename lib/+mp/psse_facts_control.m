function [dm_next, state] = psse_facts_control(task, ~, ~, dm, mpopt, mpx, state)
% psse_facts_control - Executes PSS/E FACTS device control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_FACTS_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Applies PSS/E STATCON voltage control for active FACTS records with
% ``MODE = 1`` and ``J = 0``. The control uses the solved regulated-bus
% voltage from the current PF run, updates a tagged reactive injection, and
% returns a rebuilt data model when another PF run is required.
%
% See also mp.task_pf_psse, mp.psse_facts_states, mp.psse_facts_update.

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

%% no preserved PSS/E FACTS metadata, no PSS/E FACTS control
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'facts') || ...
        isempty(dm.source.psse.facts.num)
    state = [];
    return;
end

%% initialize control state from preserved RAW metadata
if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = mp.psse_facts_states(dm.source);
end

%% keep reporting synchronized even when FACTS control is disabled
if ~state.enabled || ~any(state.controllable)
    state.last_vm_final(:) = NaN;
    state.last_margin(:) = NaN;
    dm.source = mp.psse_facts_update(dm.source, state);
    return;
end

%% stop after the PSS/E tap/shunt adjustment iteration limit
state.iterations = state.iterations + 1;
if state.iterations > state.max_iter
    state.max_iter_reached = 1;
    state.changed_last = 0;
    dm.source = mp.psse_facts_update(dm.source, state);
    return;
end

bus = dm.elements.bus;
vm = bus.tab.vm;
state = classify_state(state, vm);

%% detect global Q-injection cycles and finish at the best state seen
sig = state_signature(state.current_q);
if any(strcmp(state.visited_signatures, sig)) && ~state.cycle_resolved
    state.cycle_detected = 1;
    state.repeated_states = state.repeated_states + 1;
    if any(abs(state.best_q - state.current_q) > 1e-7)
        q0 = state.current_q;
        state.current_q = state.best_q;
        moved = abs(state.current_q - q0) > 1e-7;
        state.changed_last = nnz(moved);
        state.cycle_resolution_changes = state.cycle_resolution_changes + state.changed_last;
        state.cycle_resolved = 1;
        mpc = mp.psse_facts_update(dm.source, state);
        dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
    else
        state.changed_last = 0;
        state.cycle_resolved = 1;
        dm.source = mp.psse_facts_update(dm.source, state);
    end
    return;
end

if state.cycle_resolved
    state.changed_last = 0;
    dm.source = mp.psse_facts_update(dm.source, state);
    return;
end

state.visited_signatures{end+1} = sig;
if state.last_score < state.best_score
    state.best_score = state.last_score;
    state.best_q = state.current_q;
    state.best_violations = state.last_violations;
    state.best_violation_sum = state.last_violation_sum;
end

[new_q, new_direction] = next_group_q(state, vm);
changed = state.needs_initial_update || any(abs(new_q - state.current_q) > 1e-7);
state.needs_initial_update = 0;

%% save one voltage/Q point per regulated bus for the next sensitivity step
for kk = 1:length(state.group.reg_bus_idx)
    reg = state.group.reg_bus_idx(kk);
    members = state.group.members{kk};
    state.last_vm(reg) = vm(reg);
    state.last_q(reg) = sum(state.current_q(members));
end

if changed
    q0 = state.current_q;
    state.current_q = new_q;
    moved = abs(new_q - q0) > 1e-7;
    state.last_direction(moved) = new_direction(moved);
    state.changed_last = nnz(moved);
    state.num_adjustments = state.num_adjustments + state.changed_last;
    mpc = mp.psse_facts_update(dm.source, state);
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    state.changed_last = 0;
    dm.source = mp.psse_facts_update(dm.source, state);
end

function state = classify_state(state, vm)
% Classify the current regulated-bus voltages for reporting/scoring.
state.last_vm_final(:) = NaN;
state.last_vi_final(:) = NaN;
state.last_margin(:) = NaN;
state.last_qmin(:) = NaN;
state.last_qmax(:) = NaN;
state.at_min(:) = false;
state.at_max(:) = false;
state.limited(:) = false;
idx = find(state.controllable & state.reg_bus_idx > 0);
for kk = 1:length(idx)
    k = idx(kk);
    reg = state.reg_bus_idx(k);
    ib = state.bus_idx(k);
    v = vm(reg);
    vi = vm(ib);
    qlim = facts_q_limit(state, k, vi);
    state.last_qmin(k) = -qlim;
    state.last_qmax(k) = qlim;
    if abs(v - state.vset(k)) > state.vtol
        state.last_margin(k) = state.vset(k) - v;
    else
        state.last_margin(k) = 0;
    end
    state.at_min(k) = state.current_q(k) <= state.last_qmin(k) + 1e-7;
    state.at_max(k) = state.current_q(k) >= state.last_qmax(k) - 1e-7;
    state.limited(k) = (state.last_margin(k) > 0 && state.at_max(k)) || ...
        (state.last_margin(k) < 0 && state.at_min(k));
    state.last_vm_final(k) = v;
    state.last_vi_final(k) = vi;
end
margin = state.last_margin(idx);
margin = margin(~isnan(margin));
state.last_violations = nnz(margin ~= 0);
state.last_violation_sum = sum(abs(margin));
state.last_score = state.last_violations * 1e6 + state.last_violation_sum;

function [new_q, new_direction] = next_group_q(state, vm)
% Select the next STATCON Q injection vector by regulated-bus group.
new_q = state.current_q;
new_direction = zeros(size(state.current_q));
for gg = 1:length(state.group.reg_bus_idx)
    reg = state.group.reg_bus_idx(gg);
    members = state.group.members{gg};
    v = vm(reg);
    weights = state.rmpct(members);
    weights(isnan(weights) | weights <= 0) = 100;
    target = sum(state.vset(members) .* weights) / sum(weights);
    err = target - v;
    if abs(err) <= state.vtol
        continue;
    end

    cur_q = sum(state.current_q(members));
    qmin = sum(state.last_qmin(members));
    qmax = sum(state.last_qmax(members));
    if qmax <= qmin
        continue;
    end

    sens = voltage_sensitivity(state, reg, v, cur_q);
    span = qmax - qmin;
    if isnan(sens) || sens <= 0
        dq = sign(err) * min(max(1, 0.10 * span), 0.25 * span);
    else
        dq = err / sens;
        dq = min(max(dq, -0.50 * span), 0.50 * span);
    end
    new_total = min(max(cur_q + dq, qmin), qmax);
    dq = new_total - cur_q;
    if abs(dq) <= 1e-7
        continue;
    end

    share = weights / sum(weights);
    for jj = 1:length(members)
        k = members(jj);
        q = state.current_q(k) + dq * share(jj);
        q = min(max(q, state.last_qmin(k)), state.last_qmax(k));
        if abs(q - state.current_q(k)) > 1e-7
            new_q(k) = q;
            new_direction(k) = sign(q - state.current_q(k));
        end
    end
end

function sens = voltage_sensitivity(state, reg, v, cur_q)
% Estimate dV/dQ from consecutive solved points for the same regulated bus.
sens = NaN;
if reg <= 0 || reg > length(state.last_vm) || isnan(state.last_vm(reg)) || ...
        isnan(state.last_q(reg))
    return;
end
dq = cur_q - state.last_q(reg);
dv = v - state.last_vm(reg);
if abs(dq) <= 1e-7 || abs(dv) <= eps
    return;
end
sens = dv / dq;

function qlim = facts_q_limit(state, k, vi)
% Convert PSS/E SHMX current limit to a reactive Mvar limit at |V_i|.
if isnan(vi) || vi <= 0
    vi = 1;
end
qlim = state.shmx(k) * vi;
if isnan(qlim) || qlim < 0
    qlim = 0;
end

function sig = state_signature(q)
% Build a compact key for cycle detection.
sig = sprintf('%.7g,', round(q(:)' * 1e7) / 1e7);
