function ok = psse_twodc_probe_pq_model(mpc, mpopt)
% psse_twodc_probe_pq_model - Tests a TWODC PQ-equivalent AC solve.
% ::
%
%   OK = MP.PSSE_TWODC_PROBE_PQ_MODEL(MPC, MPOPT)
%
% Runs a quiet plain MATPOWER power flow with PSS/E extension callbacks
% disabled. The helper is used by two-terminal DC preparation and guarded
% control candidate rollback to avoid committing an LCC state that makes the
% next AC solve collapse.
%
% See also mp.psse_twodc_prepare, mp.psse_twodc_guard_candidate.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

ok = false;
try
    if isfield(mpc, 'order')
        mpc = rmfield(mpc, 'order');
    end
    auxopt = mpoption(mpopt, 'verbose', 0, 'out.all', 0, ...
        'pf.enforce_q_lims', 0);
    auxopt.exp.mpx = {};
    warn_state = warning;
    cleanup = onCleanup(@() warning(warn_state));
    warning('off', 'all');
    r = runpf(mpc, auxopt);
    if isstruct(r) && isfield(r, 'success') && r.success && ...
            isfield(r, 'bus') && ~isempty(r.bus)
        [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
        vm = r.bus(:, VM);
        ok = all(isfinite(vm)) && min(vm) > 0.05 && max(vm) < 5;
    end
catch
    ok = false;
end
