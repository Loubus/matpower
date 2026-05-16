function report = psse_swshunt_report(state)
% psse_swshunt_report - Builds a PSS/E switched shunt diagnostic report.
% ::
%
%   REPORT = MP.PSSE_SWSHUNT_REPORT(STATE)
%
% Returns a compact struct summarizing the current switched shunt control
% state and the last solved voltage-band classification.
%
% The returned REPORT includes:
%   * enabled, swshnt, iterations, max_iter, max_iter_reached
%   * n, active, inactive, automatic, recognized, controllable
%   * modsw0, modsw1, modsw2, unsupported_modsw, unsupported_adjm
%   * below_band, above_band, inside_band
%   * num_groups, multi_shunt_groups, max_group_rmpct_sum
%   * group_reg_bus_idx, group_count, group_rmpct_sum
%   * changed_last, num_adjustments, final_binit
%   * cycle_detected, cycle_resolved, repeated_states
%   * cycle_resolution_changes, best_violations, best_violation_sum
%
% See also mp.psse_swshunt_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

report = struct();
report.enabled = state.enabled;
report.swshnt = state.swshnt;
report.iterations = state.iterations;
report.max_iter = state.max_iter;
report.max_iter_reached = state.max_iter_reached;
report.changed_last = state.changed_last;
report.num_adjustments = state.num_adjustments;
report.last_violations = state.last_violations;
report.last_violation_sum = state.last_violation_sum;
report.best_violations = state.best_violations;
report.best_violation_sum = state.best_violation_sum;
report.n = state.n;
report.active = nnz(state.active);
report.inactive = state.n - nnz(state.active);
report.automatic = nnz(state.automatic);
report.recognized = nnz(state.recognized);
report.controllable = nnz(state.controllable);
report.modsw0 = nnz(state.modsw == 0);
report.modsw1 = nnz(state.modsw == 1);
report.modsw2 = nnz(state.modsw == 2);
report.unsupported_modsw = nnz(state.unsupported_modsw);
report.unsupported_adjm = nnz(state.unsupported_adjm);
report.num_groups = length(state.group.reg_bus_idx);
report.multi_shunt_groups = nnz(state.group.count > 1);
if isempty(state.group.rmpct_sum)
    report.max_group_rmpct_sum = 0;
else
    report.max_group_rmpct_sum = max(state.group.rmpct_sum);
end
report.group_reg_bus_idx = state.group.reg_bus_idx;
report.group_count = state.group.count;
report.group_rmpct_sum = state.group.rmpct_sum;
report.cycle_detected = state.cycle_detected;
report.cycle_resolved = state.cycle_resolved;
report.repeated_states = state.repeated_states;
report.cycle_resolution_changes = state.cycle_resolution_changes;
if isfield(state, 'cycle_blocked')
    report.cycle_blocked = nnz(state.cycle_blocked);
else
    report.cycle_blocked = 0;
end

idx = find(state.controllable);
if isempty(idx) || all(isnan(state.last_margin(idx)))
    report.below_band = 0;
    report.above_band = 0;
    report.inside_band = 0;
else
    margin = state.last_margin(idx);
    report.below_band = nnz(margin < 0);
    report.above_band = nnz(margin > 0);
    report.inside_band = nnz(margin == 0);
end

report.final_binit = state.current_b;
