function [mpc, prep, mpopt, source] = psse_prepare_case(mpc, mpopt, mode)
% psse_prepare_case - Applies common PSS/E case preparation.
% ::
%
%   [MPC, PREP, MPOPT] = MP.PSSE_PREPARE_CASE(MPC, MPOPT, MODE)
%   [MPC, PREP, MPOPT, SOURCE] = MP.PSSE_PREPARE_CASE(...)
%
% Applies the same PSS/E SYSTEM-WIDE option policy and metadata preparation
% used by ``runpf_psse`` before building an MP-Core task. ``MODE`` is used
% only for traceability in the returned ``PREP`` struct. ``SOURCE`` is the
% case after SYSTEM-WIDE option policy handling but before topology/control
% preparation, for callers that need to retry from the original PSS/E data.
%
% See also runpf_psse, runcpf_psse, mp.psse_solver_options.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 3
    mode = 'pf';
end

prep = struct('mode', mode, 'solver_policy', [], ...
    'swdev_collapse', [], 'branch_collapse', [], ...
    'source_prepared', false);

[mpopt, prep.solver_policy, mpc] = mp.psse_solver_options(mpopt, mpc);
if isfield(mpc, 'psse')
    mpc.psse.solver_options = prep.solver_policy;
end
source = mpc;

if psse_solved_snapshot_mode(mpc)
    mpc = psse_record_solved_snapshot_detection(mpc);
end
if ~isempty(which('mp.psse_swdev_collapse'))
    [mpc, prep.swdev_collapse] = mp.psse_swdev_collapse(mpc);
end
if ~isempty(which('mp.psse_branch_collapse'))
    [mpc, prep.branch_collapse] = mp.psse_branch_collapse(mpc);
end
if ~isempty(which('mp.psse_pqbrak_prepare'))
    mpc = mp.psse_pqbrak_prepare(mpc);
end
if ~isempty(which('mp.psse_genq_prepare'))
    mpc = mp.psse_genq_prepare(mpc);
end
if ~isempty(which('mp.psse_twodc_prepare'))
    mpc = mp.psse_twodc_prepare(mpc, mpopt);
end
if psse_genq_needs_deferred_prepare(mpc, mpopt)
    mpc = mp.psse_genq_prepare(mpc, 'deferred');
    mpc.psse.genq.prepare_fallback_reason = ...
        'fixed_q_initial_power_flow_failed';
end
prep.source_prepared = true;

function TorF = psse_solved_snapshot_mode(mpc)
TorF = 0;
if ~isfield(mpc, 'psse') || isempty(mpc.bus) || size(mpc.bus, 1) <= 1000
    return;
end
varlim = mp.psse_system_value(mpc, 'solver', 'VARLIM', NaN, 0);
if isnan(varlim) || varlim ~= 0
    return;
end
TorF = isfield(mpc.psse, 'twodc') && isfield(mpc.psse.twodc, 'num') && ...
    size(mpc.psse.twodc.num, 1) > 1;

function mpc = psse_record_solved_snapshot_detection(mpc)
% Record solved snapshot diagnostics without changing RAW solver controls.
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    mpc.psse = struct();
end
mpc.psse.solved_snapshot_detection = struct( ...
    'active', 1, ...
    'reason', 'large_raw_varlim0_saved_solution');

function TorF = psse_genq_needs_deferred_prepare(mpc, mpopt)
TorF = 0;
if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'genq') || ...
        ~isfield(mpc.psse.genq, 'prepare_mode') || ...
        ~strcmp(mpc.psse.genq.prepare_mode, 'fixed_q')
    return;
end
try
    auxopt = mpoption(mpopt, 'verbose', 0, 'out.all', 0, ...
        'pf.enforce_q_lims', 0);
    auxopt.exp.mpx = {};
    warn_state = warning;
    cleanup = onCleanup(@() warning(warn_state));
    warning('off', 'all');
    r = runpf(mpc, auxopt);
    TorF = ~(isstruct(r) && isfield(r, 'success') && r.success);
catch
    TorF = 1;
end
