function [mpc, report] = psse_unified_control_update(mpc, unified_bus)
% psse_unified_control_update - Apply PSS/E controls from unified voltages.
% ::
%
%   [MPC, REPORT] = MP.PSSE_UNIFIED_CONTROL_UPDATE(MPC, UNIFIED_BUS)
%
% Applies one direct PSS/E discrete-control pass for control families whose
% measured voltage is available from a unified AC/DC/VSC solution. This keeps
% local tap and switched-shunt decisions tied to the monolithic voltage
% solution instead of a projected AC-only auxiliary power flow.
%
% Currently handles transformer tap voltage control and switched shunts.
%
% See also mp.psse_xfmr_states, mp.psse_swshunt_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, BUS_I, ~, ~, ~, GS, BS, ~, VM] = idx_bus;
[~, ~, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, TAP, SHIFT, BR_STATUS] = idx_brch;
[~, ~, ~, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;

report = struct('supported', 0, 'changed', 0, ...
    'changed_buses', 0, 'changed_gens', 0, 'changed_branches', 0);

bus0 = mpc.bus;
gen0 = mpc.gen;
branch0 = mpc.branch;
vm = unified_vm(mpc, unified_bus, BUS_I, VM);

if has_family(mpc, 'xfmr')
    report.supported = 1;
    mpc = direct_xfmr_control(mpc, vm);
end
if has_family(mpc, 'swshunt')
    report.supported = 1;
    mpc = direct_swshunt_control(mpc, vm);
end

bus_cols = existing_cols([GS BS], bus0, mpc.bus);
gen_cols = existing_cols([QMAX QMIN VG GEN_STATUS], gen0, mpc.gen);
branch_cols = existing_cols([BR_R BR_X BR_B RATE_A RATE_B RATE_C ...
    TAP SHIFT BR_STATUS], branch0, mpc.branch);

report.changed_buses = changed_rows(bus0(:, bus_cols), mpc.bus(:, bus_cols));
report.changed_gens = changed_rows(gen0(:, gen_cols), mpc.gen(:, gen_cols));
report.changed_branches = changed_rows(branch0(:, branch_cols), ...
    mpc.branch(:, branch_cols));
report.changed = report.changed_buses || report.changed_gens || ...
    report.changed_branches;

function TorF = has_family(mpc, name)
TorF = isfield(mpc, 'psse') && isfield(mpc.psse, name) && ...
    ~isempty(mpc.psse.(name));
if TorF && isstruct(mpc.psse.(name)) && isfield(mpc.psse.(name), 'num') && ...
        isempty(mpc.psse.(name).num)
    TorF = 0;
end

function vm = unified_vm(mpc, unified_bus, BUS_I, VM)
vm = mpc.bus(:, VM);
if isempty(unified_bus)
    return;
end
for k = 1:size(mpc.bus, 1)
    row = find(unified_bus(:, BUS_I) == mpc.bus(k, BUS_I), 1);
    if ~isempty(row)
        vm(k) = unified_bus(row, VM);
    end
end

function mpc = direct_xfmr_control(mpc, vm)
state = mp.psse_xfmr_states(mpc);
state.iterations = state.iterations + 1;
state = classify_xfmr_state(state, vm);
[new_raw, new_tap] = next_xfmr_tap_state(state, vm);
moved = abs(new_tap - state.current_tap) > 1e-9;
if any(moved)
    state.current_raw(moved) = new_raw(moved);
    state.current_tap(moved) = new_tap(moved);
    state.changed_last = nnz(moved);
    state.num_adjustments = state.num_adjustments + state.changed_last;
else
    state.changed_last = 0;
end
state = update_xfmr_limit_flags(state);
mpc = mp.psse_xfmr_update(mpc, state);

function state = classify_xfmr_state(state, vm)
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
state.best_violations = state.last_violations;
state.best_violation_sum = state.last_violation_sum;

function state = update_xfmr_limit_flags(state)
state.at_min(:) = false;
state.at_max(:) = false;
idx = find(state.controllable);
for kk = 1:length(idx)
    k = idx(kk);
    states = state.states_tap{k};
    if ~isempty(states)
        state.at_min(k) = abs(state.current_tap(k) - states(1)) < 1e-9;
        state.at_max(k) = abs(state.current_tap(k) - states(end)) < 1e-9;
    end
end

function [new_raw, new_tap] = next_xfmr_tap_state(state, vm)
new_raw = state.current_raw;
new_tap = state.current_tap;
idx = find(state.controllable & state.reg_bus_idx > 0);
for kk = 1:length(idx)
    k = idx(kk);
    v = vm(state.reg_bus_idx(k));
    lo = min(state.vmi(k), state.vma(k));
    hi = max(state.vmi(k), state.vma(k));
    if v < lo - state.vtol
        voltage_dir = 1;
    elseif v > hi + state.vtol
        voltage_dir = -1;
    else
        continue;
    end

    states = state.states_tap{k};
    raw_states = state.states_raw{k};
    if isempty(states)
        continue;
    end
    tap_dir = voltage_dir * state.side_sign(k);
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

function mpc = direct_swshunt_control(mpc, vm)
state = mp.psse_swshunt_states(mpc);
state.iterations = state.iterations + 1;
state = classify_swshunt_state(state, vm);
new_b = next_swshunt_b_state(state, vm);
moved = abs(new_b - state.current_b) > 1e-9;
if any(moved)
    state.current_b(moved) = new_b(moved);
    state.changed_last = nnz(moved);
    state.num_adjustments = state.num_adjustments + state.changed_last;
else
    state.changed_last = 0;
end
mpc = mp.psse_swshunt_update(mpc, state);

function state = classify_swshunt_state(state, vm)
state.last_vm_final(:) = NaN;
state.last_margin(:) = NaN;
idx = find(state.controllable & state.reg_bus_idx > 0);
for kk = 1:length(idx)
    k = idx(kk);
    v = vm(state.reg_bus_idx(k));
    [lo, hi] = swshunt_voltage_band(state, k);
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
state.best_violations = state.last_violations;
state.best_violation_sum = state.last_violation_sum;

function new_b = next_swshunt_b_state(state, vm)
new_b = state.current_b;
for gg = 1:length(state.group.reg_bus_idx)
    reg = state.group.reg_bus_idx(gg);
    members = state.group.members{gg};
    [direction, active_members] = swshunt_group_action(state, members, vm(reg));
    if direction == 0
        continue;
    end
    for jj = 1:length(active_members)
        k = active_members(jj);
        if state.modsw(k) == 1
            new_b(k) = discrete_next_b(state, k, direction);
        elseif state.modsw(k) == 2
            new_b(k) = continuous_next_b(state, k, direction);
        end
    end
end

function [direction, active_members] = swshunt_group_action(state, members, v)
err = zeros(length(members), 1);
for jj = 1:length(members)
    k = members(jj);
    [lo, hi] = swshunt_voltage_band(state, k);
    if isnan(lo) || isnan(hi)
        continue;
    end
    if state.modsw(k) == 1
        if v < lo - state.vtol
            err(jj) = lo - v;
        elseif v > hi + state.vtol
            err(jj) = hi - v;
        end
    elseif state.modsw(k) == 2
        target = (lo + hi) / 2;
        if abs(target - v) > state.vtol
            err(jj) = target - v;
        end
    end
end

up = find(err > 0);
dn = find(err < 0);
up_score = sum(abs(err(up)) .* state.rmpct(members(up)) / 100);
dn_score = sum(abs(err(dn)) .* state.rmpct(members(dn)) / 100);
if up_score == 0 && dn_score == 0
    direction = 0;
    active_members = [];
elseif up_score >= dn_score
    direction = 1;
    active_members = members(up);
else
    direction = -1;
    active_members = members(dn);
end

function [lo, hi] = swshunt_voltage_band(state, k)
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
states = state.states{k};
if isempty(states)
    b = state.current_b(k);
    return;
end
[~, cur] = min(abs(states - state.current_b(k)));
if direction > 0
    cand = find(states > states(cur) + 1e-9, 1);
else
    cand = find(states < states(cur) - 1e-9, 1, 'last');
end
if isempty(cand)
    b = state.current_b(k);
else
    b = states(cand);
end

function b = continuous_next_b(state, k, direction)
span = max(state.bmax(k) - state.bmin(k), 0);
if span == 0
    b = state.current_b(k);
else
    db = direction * span * 0.25 * state.rmpct(k) / 100;
    b = min(max(state.current_b(k) + db, state.bmin(k)), state.bmax(k));
end

function cols = existing_cols(cols, a, b)
cols = cols(cols <= size(a, 2) & cols <= size(b, 2));

function n = changed_rows(a, b)
if isempty(a) || isempty(b)
    n = 0;
else
    n = nnz(any(abs(a - b) > 1e-8, 2));
end
