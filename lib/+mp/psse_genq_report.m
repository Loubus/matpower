function report = psse_genq_report(state)
% psse_genq_report - Builds a PSS/E generator Q-control report.
% ::
%
%   REPORT = MP.PSSE_GENQ_REPORT(STATE)
%
% Returns a compact struct summarizing the current PSS/E GENERATOR DATA
% reactive-control state and the last solved regulated-bus voltages.
%
% See also mp.psse_genq_control, mp.psse_genq_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

report = struct();
report.enabled = 1;
report.varlim = state.varlim;
report.varlim_enabled = state.varlim_enabled;
report.iterations = state.iterations;
report.max_iter = state.max_iter;
report.max_iter_reached = state.max_iter_reached;
report.changed_last = state.changed_last;
report.num_adjustments = state.num_adjustments;
report.last_violations = state.last_violations;
report.last_violation_sum = state.last_violation_sum;
report.n = state.n;
report.active = nnz(state.active);
report.inactive = state.n - nnz(state.active);
report.local = nnz(state.local);
report.remote = nnz(state.remote);
report.swing = nnz(state.swing);
report.limited_count = nnz(state.limited);
report.at_min_count = nnz(state.at_min);
report.at_max_count = nnz(state.at_max);
report.unmapped = nnz(state.unmapped);

report.gen_idx = state.gen_idx;
report.bus_idx = state.bus_idx;
report.bus_ext = state.bus_ext;
report.reg_bus_idx = state.reg_bus_idx;
report.reg_bus_ext = state.reg_bus_ext;
report.id = state.id;
report.status = state.status;
report.code = state.code_final;
report.code_label = state.code_label;
report.qgen = state.current_q;
report.qmax = state.qmax;
report.qmin = state.qmin;
report.vsched = state.vs;
report.vact = state.last_vm_final;
report.voltage_margin = state.last_margin;
report.rmpct = state.rmpct;
report.pct_q = state.pct_q;
report.at_min = state.at_min;
report.at_max = state.at_max;
report.limited = state.limited;
report.local_mask = state.local;
report.remote_mask = state.remote;
report.swing_mask = state.swing;

report.num_groups = length(state.group.reg_bus_idx);
report.group_reg_bus_idx = state.group.reg_bus_idx;
report.group_reg_bus_ext = state.group.reg_bus_ext;
report.group_count = state.group.count;
report.group_rmpct_sum = state.group.rmpct_sum;
report.group_target_vs = state.group.target_vs;
report.group_current_q = state.group.current_q;
report.group_qmin = state.group.qmin;
report.group_qmax = state.group.qmax;
report.group_vact = state.group.vact;
report.group_margin = state.group.margin;
report.group_all_limited = state.group.all_limited;
report.group_qlo = state.group.qlo;
report.group_qhi = state.group.qhi;
report.group_vlo = state.group.vlo;
report.group_vhi = state.group.vhi;
report.group_last_q = state.group.last_q;
report.group_last_v = state.group.last_v;
