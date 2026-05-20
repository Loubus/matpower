function report = psse_twodc_report(state)
% psse_twodc_report - Builds a PSS/E two-terminal DC diagnostic report.
% ::
%
%   REPORT = MP.PSSE_TWODC_REPORT(STATE)
%
% Returns a compact struct summarizing the current two-terminal DC control
% state used by runpf_psse.
%
% See also mp.psse_twodc_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

report = struct();
report.enabled = state.enabled;
report.dctaps = state.dctaps;
report.dctaps_enabled = state.dctaps_enabled;
report.iterations = state.iterations;
report.max_iter = state.max_iter;
report.max_iter_reached = state.max_iter_reached;
report.changed_last = state.changed_last;
report.num_adjustments = state.num_adjustments;
report.n = state.n;
report.active = nnz(state.active);
report.supported = nnz(state.supported);
report.current_limited = nnz(state.current_limited);
report.current_limited_row = state.current_limited;
report.control_flag = control_flags(state);
report.mode = state.mode;
report.pf = state.current_pf;
report.pt = state.current_pt;
report.loss_mw = state.current_loss;
report.rect_bus = state.rect_bus;
report.inv_bus = state.inv_bus;
report.idc_ka = state.idc_ka;
report.vdcr_kv = state.vdcr_kv;
report.vdci_kv = state.vdci_kv;
report.vcomp_kv = state.vcomp_kv;
report.vcmod_kv = state.vcmod;
report.qacr_mvar = state.qacr_mvar;
report.qaci_mvar = state.qaci_mvar;
report.apply_q = state.apply_q;
report.apply_model = state.apply_model;
report.iacr_ka = state.iacr_ka;
report.iaci_ka = state.iaci_ka;
report.mu_r_deg = state.mu_r_deg;
report.mu_i_deg = state.mu_i_deg;
report.vmr_pu = state.vmr_pu;
report.vmi_pu = state.vmi_pu;
report.ac_pf_success = state.ac_pf_success;
if isfield(state, 'ac_pf_status')
    report.ac_pf_status = state.ac_pf_status;
end
if isfield(state, 'ac_pf_message')
    report.ac_pf_message = state.ac_pf_message;
end
report.tapr = state.tapr_final;
report.tapi = state.tapi_final;
if isfield(state, 'tapr_status')
    report.rectifier_tap_flag = state.tapr_status;
else
    report.rectifier_tap_flag = tap_flags(state, state.tapr_final, ...
        state.tmnr, state.tmxr, state.stpr);
end
if isfield(state, 'tapi_status')
    report.inverter_tap_flag = state.tapi_status;
else
    report.inverter_tap_flag = tap_flags(state, state.tapi_final, ...
        state.tmni, state.tmxi, state.stpi);
end
report.alpha_deg = state.alpha_deg;
report.gamma_deg = state.gamma_deg;
report.lcc_valid = nnz(state.lcc_valid);
report.lcc_valid_row = state.lcc_valid;
if isfield(state, 'q_bus')
    report.q_bus = state.q_bus;
    report.q_bus_mvar = state.q_bus_mvar;
else
    report.q_bus = zeros(0, 1);
    report.q_bus_mvar = zeros(0, 1);
end

function flags = control_flags(state)
flags = repmat({''}, state.n, 1);
for k = 1:state.n
    if ~state.active(k)
        flags{k} = 'BL';
    elseif ~state.supported(k)
        flags{k} = 'NA';
    elseif ~state.lcc_valid(k)
        flags{k} = 'ER';
    elseif state.current_limited(k)
        flags{k} = 'LO';
    else
        flags{k} = 'RG';
    end
end

function flags = tap_flags(state, tap, tmin, tmax, step)
flags = repmat({''}, state.n, 1);
tol = 1e-9;
for k = 1:state.n
    if ~state.active(k)
        flags{k} = 'BL';
    elseif ~state.supported(k)
        flags{k} = 'NA';
    elseif ~state.lcc_valid(k)
        flags{k} = 'ER';
    elseif ~state.dctaps_enabled || step(k) <= 0 || isnan(step(k)) || ...
            tmin(k) <= 0 || tmax(k) <= 0
        flags{k} = 'FX';
    else
        lo = min(tmin(k), tmax(k));
        hi = max(tmin(k), tmax(k));
        if tap(k) <= lo + tol
            flags{k} = 'LO';
        elseif tap(k) >= hi - tol
            flags{k} = 'HI';
        else
            flags{k} = 'RG';
        end
    end
end
