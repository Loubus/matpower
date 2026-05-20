function [dm_next, state] = psse_xfmr_control(task, ~, ~, dm, mpopt, mpx, state)
% psse_xfmr_control - Executes PSS/E transformer tap control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_XFMR_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Applies PSS/E voltage-regulating transformer tap control for the RAW
% behavior in scope for this extension: active ``COD = 1`` windings with
% nonzero ``CONT`` and discrete ``NTP`` tap positions. The control uses the
% solved regulated-bus voltage from the current PF run, updates the PSS/E
% winding ``WINDV`` state and the corresponding MATPOWER ``branch(:, TAP)``,
% then returns a rebuilt data model when another PF run is required.
%
% See also mp.task_pf_psse, mp.psse_xfmr_states, mp.psse_xfmr_update.

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

%% no preserved PSS/E transformer metadata, no PSS/E tap control
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'xfmr')
    state = [];
    return;
end

%% initialize control state from preserved RAW metadata
if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = mp.psse_xfmr_states(dm.source);
end

%% keep report synchronized even when ACTAPS disables control
if ~state.enabled || ~any(state.controllable)
    state.last_vm_final(:) = NaN;
    state.last_margin(:) = NaN;
    dm.source = mp.psse_xfmr_update(dm.source, state);
    return;
end

%% stop after the PSS/E tap/shunt adjustment iteration limit
state.iterations = state.iterations + 1;
if state.iterations > state.max_iter
    state.max_iter_reached = 1;
    state.changed_last = 0;
    dm.source = mp.psse_xfmr_update(dm.source, state);
    return;
end

bus = dm.elements.bus;
vm = bus.tab.vm;
state = classify_state(state, vm);

%% detect global tap cycles and finish at the best state already seen
sig = state_signature(state.current_tap);
if any(strcmp(state.visited_signatures, sig)) && ~state.cycle_resolved
    state.cycle_detected = 1;
    state.repeated_states = state.repeated_states + 1;
    if any(abs(state.best_tap - state.current_tap) > 1e-9)
        tap0 = state.current_tap;
        state.current_tap = state.best_tap;
        state.current_raw = state.best_raw;
        moved = abs(state.current_tap - tap0) > 1e-9;
        state.changed_last = nnz(moved);
        state.cycle_resolution_changes = state.cycle_resolution_changes + state.changed_last;
        state.cycle_resolved = 1;
        mpc = mp.psse_xfmr_update(dm.source, state);
        dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
    else
        state.changed_last = 0;
        state.cycle_resolved = 1;
        dm.source = mp.psse_xfmr_update(dm.source, state);
    end
    return;
end

if state.cycle_resolved
    state.changed_last = 0;
    dm.source = mp.psse_xfmr_update(dm.source, state);
    return;
end

state.visited_signatures{end+1} = sig;
if state.last_score < state.best_score
    state.best_score = state.last_score;
    state.best_tap = state.current_tap;
    state.best_raw = state.current_raw;
    state.best_violations = state.last_violations;
    state.best_violation_sum = state.last_violation_sum;
end

[new_raw, new_tap] = next_tap_state(state, vm);
changed = state.needs_initial_update || any(abs(new_tap - state.current_tap) > 1e-9);
state.needs_initial_update = 0;

if changed
    tap0 = state.current_tap;
    state.current_raw = new_raw;
    state.current_tap = new_tap;
    moved = abs(new_tap - tap0) > 1e-9;
    state.changed_last = nnz(moved);
    state.num_adjustments = state.num_adjustments + state.changed_last;
    mpc = mp.psse_xfmr_update(dm.source, state);
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    state.changed_last = 0;
    dm.source = mp.psse_xfmr_update(dm.source, state);
end

function state = classify_state(state, vm)
% Classify the current regulated-bus voltages for reporting/scoring.
state.last_vm_final(:) = NaN;
state.last_margin(:) = NaN;
state.at_min(:) = false;
state.at_max(:) = false;
idx = find(state.controllable & state.reg_bus_idx > 0);
for kk = 1:length(idx)
    k = idx(kk);
    v = vm(state.reg_bus_idx(k));
    lo = min(state.vmi(k), state.vma(k));
    hi = max(state.vmi(k), state.vma(k));
    if v < lo - state.vtol
        state.last_margin(k) = v - lo;
    elseif v > hi + state.vtol
        state.last_margin(k) = v - hi;
    else
        state.last_margin(k) = 0;
    end
    states = state.states_tap{k};
    if ~isempty(states)
        state.at_min(k) = abs(state.current_tap(k) - states(1)) < 1e-9;
        state.at_max(k) = abs(state.current_tap(k) - states(end)) < 1e-9;
    end
    state.last_vm_final(k) = v;
end
margin = state.last_margin(idx);
margin = margin(~isnan(margin));
state.last_violations = nnz(margin ~= 0);
state.last_violation_sum = sum(abs(margin));
state.last_score = state.last_violations * 1e6 + state.last_violation_sum;

function [new_raw, new_tap] = next_tap_state(state, vm)
% Select the next discrete tap state for each violating controller.
new_raw = state.current_raw;
new_tap = state.current_tap;
idx = find(state.controllable & state.reg_bus_idx > 0);
for kk = 1:length(idx)
    k = idx(kk);
    v = vm(state.reg_bus_idx(k));
    lo = min(state.vmi(k), state.vma(k));
    hi = max(state.vmi(k), state.vma(k));
    if v < lo - state.vtol
        voltage_dir = 1;       %% raise controlled voltage
    elseif v > hi + state.vtol
        voltage_dir = -1;      %% lower controlled voltage
    else
        continue;
    end

    tap_dir = voltage_dir * state.side_sign(k);
    states = state.states_tap{k};
    raw_states = state.states_raw{k};
    if isempty(states)
        continue;
    end
    [~, cur] = min(abs(states - state.current_tap(k)));
    if tap_dir > 0
        cand = find(states > states(cur) + 1e-9, 1);
    else
        cand = find(states < states(cur) - 1e-9, 1, 'last');
    end
    if ~isempty(cand)
        new_tap(k) = states(cand);
        new_raw(k) = raw_states(cand);
    end
end

function sig = state_signature(tap)
% Build a compact key for cycle detection.
sig = sprintf('%.9g,', round(tap(:)' * 1e9) / 1e9);
