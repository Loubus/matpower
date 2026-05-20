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
