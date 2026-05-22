function mpc = psse_facts_update(mpc, state)
% psse_facts_update - Applies PSS/E FACTS state to an MPC.
% ::
%
%   MPC = MP.PSSE_FACTS_UPDATE(MPC, STATE)
%
% Incrementally updates ``mpc.bus(:, QD)`` with the controlled STATCON
% reactive injection and synchronizes ``mpc.psse.facts`` with a diagnostic
% control report.
%
% See also mp.psse_facts_control, mp.psse_facts_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, ~, ~, ~, QD] = idx_bus;

nb = size(mpc.bus, 1);
prev_q_by_bus = previous_q_by_bus(mpc, state, nb);
q_by_bus = current_q_by_bus(state, nb);

mpc.bus(:, QD) = mpc.bus(:, QD) + prev_q_by_bus - q_by_bus;
mpc.psse.facts.qinj = state.current_q;
mpc.psse.facts.control = mp.psse_facts_report(state);

function q = previous_q_by_bus(mpc, state, nb)
q = zeros(nb, 1);
if isfield(mpc.psse.facts, 'qinj') && ...
        length(mpc.psse.facts.qinj) == state.n
    q = accum_q(state, mpc.psse.facts.qinj(:), nb, false);
end

function q = current_q_by_bus(state, nb)
q = accum_q(state, state.current_q, nb, true);

function q = accum_q(state, qinj, nb, active_only)
idx = state.bus_idx > 0 & state.bus_idx <= nb & abs(qinj) > 0;
if active_only
    idx = idx & state.active;
end
idx = find(idx);
if isempty(idx)
    q = zeros(nb, 1);
else
    q = accumarray(state.bus_idx(idx), qinj(idx), [nb 1], @sum, 0);
end
