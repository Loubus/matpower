function report = psse_facts_report(state)
% psse_facts_report - Builds a PSS/E FACTS diagnostic report.
% ::
%
%   REPORT = MP.PSSE_FACTS_REPORT(STATE)
%
% Returns a compact struct summarizing the current FACTS control state and
% the last solved voltage-target classification.
%
% See also mp.psse_facts_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

report = struct();
report.enabled = state.enabled;
report.facts = state.facts;
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
report.statcon = nnz(state.statcon);
report.recognized = nnz(state.recognized);
report.controllable = nnz(state.controllable);
report.remote_regulated = nnz(state.remote_regulated);
report.series_device = nnz(state.series_device);
report.unsupported_mode = nnz(state.unsupported_mode);
report.unsupported_i_bus = nnz(state.unsupported_i_bus);
report.num_groups = length(state.group.reg_bus_idx);
report.multi_facts_groups = nnz(state.group.count > 1);
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

idx = find(state.controllable);
if isempty(idx) || all(isnan(state.last_margin(idx)))
    report.below_target = 0;
    report.above_target = 0;
    report.inside_target = 0;
else
    margin = state.last_margin(idx);
    report.below_target = nnz(margin > 0);
    report.above_target = nnz(margin < 0);
    report.inside_target = nnz(margin == 0);
end

report.qinj = state.current_q;
report.qmin = state.last_qmin;
report.qmax = state.last_qmax;
report.at_min = state.at_min;
report.at_max = state.at_max;
report.limited = state.limited;
report.regulated_vm = state.last_vm_final;
report.i_bus_vm = state.last_vi_final;
report.voltage_margin = state.last_margin;
