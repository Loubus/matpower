function [dm_next, state] = psse_swshunt_control(task, ~, ~, dm, mpopt, mpx, state)
% psse_swshunt_control - Executes PSS/E switched shunt control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_SWSHUNT_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Applies PSS/E switched shunt voltage control for MODSW = 1 and MODSW = 2
% with ADJM = 0. The control uses the solved regulated-bus voltage from the
% current PF run, updates the PSS/E BINIT state, and returns a rebuilt data
% model when another PF run is required. If no further adjustment is needed,
% it returns an empty matrix.
%
% See also mp.task_pf_psse, mp.psse_swshunt_states, mp.psse_swshunt_update.

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

%% no PSS/E switched shunt data, no PSS/E control
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'swshunt') || ...
        isempty(dm.source.psse.swshunt.num)
    state = [];
    return;
end

%% initialize control state from the preserved RAW metadata
if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = mp.psse_swshunt_states(dm.source);
end

%% keep reporting/BINIT synchronization even when SWSHNT disables control
if ~state.enabled || ~any(state.controllable)
    state.last_vm_final(:) = NaN;
    state.last_margin(:) = NaN;
    dm.source = mp.psse_swshunt_update(dm.source, state);
    return;
end

%% stop after the PSS/E switched shunt iteration limit
state.iterations = state.iterations + 1;
if state.iterations > state.max_iter
    state.max_iter_reached = 1;
    state.changed_last = 0;
    dm.source = mp.psse_swshunt_update(dm.source, state);
    return;
end

%% classify the current solved state before selecting the next one
bus = dm.elements.bus;
vm = bus.tab.vm;
state = classify_state(state, vm);

%% detect global BINIT cycles and finish at the best state already seen
sig = state_signature(state.current_b);
if any(strcmp(state.visited_signatures, sig)) && ~state.cycle_resolved
    state.cycle_detected = 1;
    state.repeated_states = state.repeated_states + 1;
    if any(abs(state.best_b - state.current_b) > 1e-9)
        current_b0 = state.current_b;
        state.current_b = state.best_b;
        moved = abs(state.current_b - current_b0) > 1e-9;
        state.changed_last = nnz(moved);
        state.cycle_resolution_changes = state.cycle_resolution_changes + state.changed_last;
        state.cycle_resolved = 1;
        mpc = mp.psse_swshunt_update(dm.source, state);
        dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
    else
        state.changed_last = 0;
        state.cycle_resolved = 1;
        dm.source = mp.psse_swshunt_update(dm.source, state);
    end
    return;
end

if state.cycle_resolved
    state.changed_last = 0;
    dm.source = mp.psse_swshunt_update(dm.source, state);
    return;
end

state.visited_signatures{end+1} = sig;
if state.last_score < state.best_score
    state.best_score = state.last_score;
    state.best_b = state.current_b;
    state.best_violations = state.last_violations;
    state.best_violation_sum = state.last_violation_sum;
end

%% solve group decisions from the current PF voltages, then apply together
current_b0 = state.current_b;
[new_b, new_direction] = next_group_b(state, vm);
changed = state.needs_initial_update || any(abs(new_b - current_b0) > 1e-9);
state.needs_initial_update = 0;

%% save one voltage/B point per regulated bus for the next sensitivity step
for kk = 1:length(state.group.reg_bus_idx)
    reg = state.group.reg_bus_idx(kk);
    members = state.group.members{kk};
    state.last_vm(reg) = vm(reg);
    state.last_b(reg) = sum(current_b0(members));
end

%% rebuild the data model only when BINIT changed
if changed
    state.current_b = new_b;
    moved = abs(new_b - current_b0) > 1e-9;
    state.last_direction(moved) = new_direction(moved);
    state.changed_last = nnz(moved);
    state.num_adjustments = state.num_adjustments + state.changed_last;
    mpc = mp.psse_swshunt_update(dm.source, state);
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    state.changed_last = 0;
    dm.source = mp.psse_swshunt_update(dm.source, state);
end

function state = classify_state(state, vm)
% Classify the current regulated-bus voltages for reporting/scoring.
state.last_vm_final(:) = NaN;
state.last_margin(:) = NaN;
idx = find(state.controllable & state.reg_bus_idx > 0);
for kk = 1:length(idx)
    k = idx(kk);
    v = vm(state.reg_bus_idx(k));
    [lo, hi] = voltage_band(state, k);
    if isnan(lo) || isnan(hi)
        continue;
    end
    if state.modsw(k) == 1
        if v < lo - state.vtol
            state.last_margin(k) = v - lo;
        elseif v > hi + state.vtol
            state.last_margin(k) = v - hi;
        else
            state.last_margin(k) = 0;
        end
    elseif state.modsw(k) == 2
        target = (lo + hi) / 2;
        if abs(v - target) > state.vtol
            state.last_margin(k) = v - target;
        else
            state.last_margin(k) = 0;
        end
    end
    state.last_vm_final(k) = v;
end
margin = state.last_margin(idx);
margin = margin(~isnan(margin));
state.last_violations = nnz(margin ~= 0);
state.last_violation_sum = sum(abs(margin));
state.last_score = state.last_violations * 1e6 + state.last_violation_sum;

function [new_b, new_direction] = next_group_b(state, vm)
% Select the next BINIT vector by regulated-bus group.
new_b = state.current_b;
new_direction = zeros(size(state.current_b));
for gg = 1:length(state.group.reg_bus_idx)
    reg = state.group.reg_bus_idx(gg);
    members = state.group.members{gg};
    v = vm(reg);
    [direction, target, active_members] = group_action(state, members, v);
    if direction == 0
        continue;
    end

    cur_reg_b = sum(state.current_b(members));
    sens = voltage_sensitivity(state, reg, v, cur_reg_b);
    for jj = 1:length(active_members)
        k = active_members(jj);
        if state.modsw(k) == 1
            b = discrete_next_b(state, k, direction);
        else
            b = continuous_next_b(state, k, v, target, direction, sens);
        end
        if abs(b - state.current_b(k)) > 1e-9
            new_b(k) = b;
            new_direction(k) = sign(b - state.current_b(k));
        end
    end
end

function [direction, target, active_members] = group_action(state, members, v)
% Determine one voltage-control direction for all shunts in a group.
err = zeros(length(members), 1);
target_k = NaN(length(members), 1);
for jj = 1:length(members)
    k = members(jj);
    [lo, hi] = voltage_band(state, k);
    if isnan(lo) || isnan(hi)
        continue;
    end
    if state.modsw(k) == 1
        if v < lo - state.vtol
            target_k(jj) = lo;
            err(jj) = lo - v;
        elseif v > hi + state.vtol
            target_k(jj) = hi;
            err(jj) = hi - v;
        end
    elseif state.modsw(k) == 2
        target_k(jj) = (lo + hi) / 2;
        if abs(target_k(jj) - v) > state.vtol
            err(jj) = target_k(jj) - v;
        end
    end
end

up = find(err > 0);
dn = find(err < 0);
up_score = sum(abs(err(up)) .* state.rmpct(members(up)) / 100);
dn_score = sum(abs(err(dn)) .* state.rmpct(members(dn)) / 100);
if up_score == 0 && dn_score == 0
    direction = 0;
    target = NaN;
    active_members = [];
    return;
elseif up_score >= dn_score
    direction = 1;
    active = up;
else
    direction = -1;
    active = dn;
end

active_members = members(active);
weights = state.rmpct(active_members);
if isempty(weights) || sum(weights) == 0
    target = mean(target_k(active));
else
    target = sum(target_k(active) .* weights) / sum(weights);
end

function [lo, hi] = voltage_band(state, k)
% Return a normalized voltage band for one switched shunt.
lo = state.vswlo(k);
hi = state.vswhi(k);
if isnan(lo) || isnan(hi)
    return;
end
if hi < lo
    tmp = hi;
    hi = lo;
    lo = tmp;
end

function b = discrete_next_b(state, k, direction)
% Advance one admissible discrete block state for ADJM = 0.
states = state.states{k};
[~, cur] = min(abs(states - state.current_b(k)));
if direction > 0
    cand = find(states > states(cur) + 1e-9);
else
    cand = find(states < states(cur) - 1e-9);
end
if isempty(cand)
    b = state.current_b(k);
    return;
end

step_idx = cand(1);
if direction < 0
    step_idx = cand(end);
end
b = states(step_idx);

function b = continuous_next_b(state, k, v, target, direction, sens)
% Compute the continuous BINIT move, bounded by the RAW block range.
span = max(state.bmax(k) - state.bmin(k), 0);
if span == 0
    b = state.current_b(k);
    return;
end
db = requested_db(state, k, v, target, direction, sens);
if sign(db) ~= direction
    db = direction * min(abs(db), span);
end
b = min(max(state.current_b(k) + db, state.bmin(k)), state.bmax(k));

function db = requested_db(state, k, v, target, direction, sens)
% Estimate a BINIT movement using group sensitivity and literal RMPCT.
span = max(state.bmax(k) - state.bmin(k), 0);
if ~isnan(sens) && abs(sens) > 1e-8
    db = (target - v) / sens * state.rmpct(k) / 100;
else
    db = direction * span * 0.25 * state.rmpct(k) / 100;
end

function sens = voltage_sensitivity(state, reg, v, cur_reg_b)
% Estimate dV/dB at the regulated bus from consecutive PF solutions.
sens = NaN;
if reg <= length(state.last_vm) && ~isnan(state.last_vm(reg)) && ...
        ~isnan(state.last_b(reg))
    db = cur_reg_b - state.last_b(reg);
    if abs(db) > 1e-9
        sens = (v - state.last_vm(reg)) / db;
    end
end

function sig = state_signature(b)
% Build a compact key for cycle detection.
sig = sprintf('%.9g,', round(b(:)' * 1e9) / 1e9);
