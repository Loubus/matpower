function accepted = psse_twodc_guard_candidate(mpc, state0, target, mpopt)
% psse_twodc_guard_candidate - Guards PSS/E TWODC control candidates.
% ::
%
%   ACCEPTED = MP.PSSE_TWODC_GUARD_CANDIDATE(MPC, STATE0, TARGET, MPOPT)
%
% Probes a proposed two-terminal DC LCC control state with a plain AC power
% flow before committing it to the PSS/E control loop. If the full candidate
% does not solve, supported rows that changed are blocked one at a time, then
% as a set. If none of those guarded candidates solves, the previous state is
% restored and marked as rejected.
%
% See also mp.psse_twodc_control, mp.psse_twodc_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

accepted = target;
accepted.candidate_rejected = 0;
accepted.blocked_candidate_accepted = 0;
if probe_candidate(mpc, accepted, mpopt)
    return;
end

block_idx = candidate_block_rows(state0, target);
for kk = block_idx(:)'
    blocked = blocked_candidate(target, kk);
    if probe_candidate(mpc, blocked, mpopt)
        accepted = blocked;
        accepted.candidate_rejected = 1;
        accepted.blocked_candidate_accepted = 1;
        return;
    end
end
if length(block_idx) > 1
    blocked = blocked_candidate(target, block_idx);
    if probe_candidate(mpc, blocked, mpopt)
        accepted = blocked;
        accepted.candidate_rejected = 1;
        accepted.blocked_candidate_accepted = 1;
        return;
    end
end

accepted = state0;
accepted.next_pf = state0.current_pf;
accepted.next_pt = state0.current_pt;
accepted.next_loss = state0.current_loss;
accepted.next_qacr = state0.qacr_mvar;
accepted.next_qaci = state0.qaci_mvar;
accepted.candidate_rejected = 1;
accepted.blocked_candidate_accepted = 0;
accepted.ac_pf_status = 'candidate_rejected';

function idx = candidate_block_rows(state0, target)
ctrl_tol = 1e-8;
idx = find(target.supported(:) & ( ...
    abs(target.current_pf - state0.current_pf) > ctrl_tol | ...
    abs(target.current_pt - state0.current_pt) > ctrl_tol | ...
    abs(target.current_loss - state0.current_loss) > ctrl_tol | ...
    abs(target.qacr_mvar - state0.qacr_mvar) > ctrl_tol | ...
    abs(target.qaci_mvar - state0.qaci_mvar) > ctrl_tol));

function state = blocked_candidate(target, block_idx)
state = target;
idx = block_idx(:);
idx = idx(idx > 0 & idx <= state.n & state.supported(idx));
state.current_pf(idx) = 0;
state.current_pt(idx) = 0;
state.current_loss(idx) = 0;
state.qacr_mvar(idx) = 0;
state.qaci_mvar(idx) = 0;
state.next_pf = state.current_pf;
state.next_pt = state.current_pt;
state.next_loss = state.current_loss;
state.next_qacr = state.qacr_mvar;
state.next_qaci = state.qaci_mvar;
if ~isfield(state, 'blocked')
    state.blocked = false(state.n, 1);
end
state.blocked(idx) = true;
state.lcc_valid(idx) = true;
state.mode(idx) = repmat({'blocked'}, length(idx), 1);
state.vmr_pu(idx) = target.vmr_pu(idx);
state.vmi_pu(idx) = target.vmi_pu(idx);
state.alpha_deg(idx) = 90;
state.gamma_deg(idx) = 90;
state.ac_pf_status = 'blocked_candidate';

function ok = probe_candidate(mpc, state, mpopt)
try
    candidate = mp.psse_twodc_update(mpc, state);
    ok = mp.psse_twodc_probe_pq_model(candidate, mpopt);
catch
    ok = false;
end
