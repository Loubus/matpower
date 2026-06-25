function report = psse_xfmr_report(state)
% psse_xfmr_report - Builds a PSS/E transformer tap diagnostic report.
% ::
%
%   REPORT = MP.PSSE_XFMR_REPORT(STATE)
%
% Returns a compact struct summarizing the current transformer tap-control
% state and last solved voltage-band classification.
%
% See also mp.psse_xfmr_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

report = struct();
report.enabled = state.enabled;
report.actaps = state.actaps;
report.iterations = state.iterations;
report.max_iter = state.max_iter;
report.max_iter_reached = state.max_iter_reached;
if isfield(state, 'control_failed')
    report.control_failed = state.control_failed;
else
    report.control_failed = 0;
end
if isfield(state, 'failure_reason')
    report.failure_reason = state.failure_reason;
else
    report.failure_reason = '';
end
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
report.controllable = nnz(state.controllable);
report.cod_m1 = nnz(state.cod == -1);
report.cod0 = nnz(state.cod == 0);
report.cod1 = nnz(state.cod == 1);
report.unsupported_cod = nnz(state.unsupported_cod);
report.unsupported_cw = nnz(state.unsupported_cw);
report.unsupported_comp = nnz(state.unsupported_comp);
report.unsupported_tab = nnz(state.unsupported_tab);
report.tab_corrected = nnz(state.tab_corrected);
report.suppressed_auto = nnz(state.suppressed_auto);
report.cont_missing = nnz(state.cont_missing);
report.cycle_detected = state.cycle_detected;
report.cycle_resolved = state.cycle_resolved;
report.repeated_states = state.repeated_states;
report.cycle_resolution_changes = state.cycle_resolution_changes;
report.final_tap = state.current_tap;
report.final_windv = state.current_raw;
report.at_min = nnz(state.controllable & state.at_min);
report.at_max = nnz(state.controllable & state.at_max);
if isfield(state, 'locked_out')
    report.locked_out = nnz(state.locked_out);
    report.locked_rows = find(state.locked_out);
else
    report.locked_out = 0;
    report.locked_rows = [];
end
if isfield(state, 'rebuild_rejected')
    report.rebuild_rejected = state.rebuild_rejected;
else
    report.rebuild_rejected = 0;
end
if isfield(state, 'rebuild_rejected_rows')
    report.rebuild_rejected_rows = state.rebuild_rejected_rows;
else
    report.rebuild_rejected_rows = [];
end
if isfield(state, 'rebuild_replay_attempted')
    report.rebuild_replay_attempted = state.rebuild_replay_attempted;
else
    report.rebuild_replay_attempted = 0;
end
if isfield(state, 'rebuild_replay_attempts')
    report.rebuild_replay_attempts = state.rebuild_replay_attempts;
else
    report.rebuild_replay_attempts = 0;
end
if isfield(state, 'rebuild_replay_candidate_rows')
    report.rebuild_replay_candidate_rows = state.rebuild_replay_candidate_rows;
else
    report.rebuild_replay_candidate_rows = [];
end
if isfield(state, 'rebuild_replay_accepted_rows')
    report.rebuild_replay_accepted_rows = state.rebuild_replay_accepted_rows;
else
    report.rebuild_replay_accepted_rows = [];
end
if isfield(state, 'rebuild_replay_rejected_rows')
    report.rebuild_replay_rejected_rows = state.rebuild_replay_rejected_rows;
else
    report.rebuild_replay_rejected_rows = [];
end
if isfield(state, 'rebuild_replay_attempt_rows')
    report.rebuild_replay_attempt_rows = state.rebuild_replay_attempt_rows;
else
    report.rebuild_replay_attempt_rows = {};
end
if isfield(state, 'rebuild_replay_attempt_success')
    report.rebuild_replay_attempt_success = ...
        state.rebuild_replay_attempt_success;
else
    report.rebuild_replay_attempt_success = false(0, 1);
end
if isfield(state, 'rebuild_replay_from_tap')
    report.rebuild_replay_from_tap = state.rebuild_replay_from_tap;
else
    report.rebuild_replay_from_tap = [];
end
if isfield(state, 'rebuild_replay_to_tap')
    report.rebuild_replay_to_tap = state.rebuild_replay_to_tap;
else
    report.rebuild_replay_to_tap = [];
end
if isfield(state, 'rebuild_replay_from_windv')
    report.rebuild_replay_from_windv = state.rebuild_replay_from_windv;
else
    report.rebuild_replay_from_windv = [];
end
if isfield(state, 'rebuild_replay_to_windv')
    report.rebuild_replay_to_windv = state.rebuild_replay_to_windv;
else
    report.rebuild_replay_to_windv = [];
end
if isfield(state, 'rebuild_replay_kind')
    report.rebuild_replay_kind = state.rebuild_replay_kind;
else
    report.rebuild_replay_kind = [];
end
if isfield(state, 'rebuild_replay_raw_row')
    report.rebuild_replay_raw_row = state.rebuild_replay_raw_row;
else
    report.rebuild_replay_raw_row = [];
end
if isfield(state, 'rebuild_replay_winding')
    report.rebuild_replay_winding = state.rebuild_replay_winding;
else
    report.rebuild_replay_winding = [];
end
if isfield(state, 'rebuild_replay_branch_idx')
    report.rebuild_replay_branch_idx = state.rebuild_replay_branch_idx;
else
    report.rebuild_replay_branch_idx = [];
end
if isfield(state, 'rebuild_replay_branch_ext')
    report.rebuild_replay_branch_ext = state.rebuild_replay_branch_ext;
else
    report.rebuild_replay_branch_ext = [];
end
if isfield(state, 'rebuild_replay_reg_bus_idx')
    report.rebuild_replay_reg_bus_idx = state.rebuild_replay_reg_bus_idx;
else
    report.rebuild_replay_reg_bus_idx = [];
end
if isfield(state, 'rebuild_replay_cod')
    report.rebuild_replay_cod = state.rebuild_replay_cod;
else
    report.rebuild_replay_cod = [];
end
if isfield(state, 'rebuild_replay_cont')
    report.rebuild_replay_cont = state.rebuild_replay_cont;
else
    report.rebuild_replay_cont = [];
end
if isfield(state, 'rebuild_replay_cw')
    report.rebuild_replay_cw = state.rebuild_replay_cw;
else
    report.rebuild_replay_cw = [];
end
if isfield(state, 'rebuild_replay_windv')
    report.rebuild_replay_windv = state.rebuild_replay_windv;
else
    report.rebuild_replay_windv = [];
end
if isfield(state, 'rebuild_replay_rma')
    report.rebuild_replay_rma = state.rebuild_replay_rma;
else
    report.rebuild_replay_rma = [];
end
if isfield(state, 'rebuild_replay_rmi')
    report.rebuild_replay_rmi = state.rebuild_replay_rmi;
else
    report.rebuild_replay_rmi = [];
end
if isfield(state, 'rebuild_replay_vma')
    report.rebuild_replay_vma = state.rebuild_replay_vma;
else
    report.rebuild_replay_vma = [];
end
if isfield(state, 'rebuild_replay_vmi')
    report.rebuild_replay_vmi = state.rebuild_replay_vmi;
else
    report.rebuild_replay_vmi = [];
end
if isfield(state, 'rebuild_replay_ntp')
    report.rebuild_replay_ntp = state.rebuild_replay_ntp;
else
    report.rebuild_replay_ntp = [];
end
if isfield(state, 'rebuild_replay_tab')
    report.rebuild_replay_tab = state.rebuild_replay_tab;
else
    report.rebuild_replay_tab = [];
end
if isfield(state, 'blocked_low')
    report.blocked_low = nnz(state.blocked_low);
    report.blocked_low_rows = find(state.blocked_low);
else
    report.blocked_low = 0;
    report.blocked_low_rows = [];
end
if isfield(state, 'blocked_high')
    report.blocked_high = nnz(state.blocked_high);
    report.blocked_high_rows = find(state.blocked_high);
else
    report.blocked_high = 0;
    report.blocked_high_rows = [];
end
if isfield(state, 'blocked_violations')
    report.blocked_violations = state.blocked_violations;
else
    report.blocked_violations = 0;
end
if isfield(state, 'locked_violations')
    report.locked_violations = state.locked_violations;
else
    report.locked_violations = 0;
end
if isfield(state, 'locked_violation_sum')
    report.locked_violation_sum = state.locked_violation_sum;
else
    report.locked_violation_sum = 0;
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
