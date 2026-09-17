function [new_raw, new_tap] = psse_xfmr_tap_decision(state, vm, eligible)
% psse_xfmr_tap_decision - Select one adjacent ULTC tap from solved voltages.
% ::
%
%   [NEW_RAW, NEW_TAP] = MP.PSSE_XFMR_TAP_DECISION(STATE, VM, ELIGIBLE)
%
% Pure simultaneous pass: each eligible controller uses the same voltage
% sample and original tap vector. STATE owns sorted paired RAW/tap grids,
% mapped bus indices, supported-device eligibility and terminal direction.
% ELIGIBLE is the caller's explicit policy mask (including its lock policy).
% No electrical solve, history, acceptance, rollback or lock changes occur.
% See the project docs/ULTC_DECISION_CONTRACT.md for caller differences.
%
% See also mp.psse_xfmr_states, mp.psse_xfmr_control,
% mp.psse_unified_control_update, mp.psse_xfmr_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

new_raw = state.current_raw;
new_tap = state.current_tap;
idx = find(eligible & state.controllable & state.reg_bus_idx > 0);
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

    tap_dir = voltage_dir * state.side_sign(k);
    states = state.states_tap{k};
    raw_states = state.states_raw{k};
    if isempty(states)
        continue;
    end
    if tap_dir > 0
        cand = find(states > state.current_tap(k) + 1e-9, 1);
    else
        cand = find(states < state.current_tap(k) - 1e-9, 1, 'last');
    end
    if ~isempty(cand)
        new_tap(k) = states(cand);
        new_raw(k) = raw_states(cand);
    end
end
