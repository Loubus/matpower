function mpc = psse_facts_update(mpc, state)
% psse_facts_update - Applies PSS/E FACTS state to an MPC.
% ::
%
%   MPC = MP.PSSE_FACTS_UPDATE(MPC, STATE)
%
% Updates ``mpc.bus(:, QD)`` with the controlled STATCON reactive injection
% and synchronizes ``mpc.psse.facts`` with a diagnostic control report.
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
active_idx = find(state.active & state.bus_idx > 0);
if isempty(active_idx)
    q_by_bus = zeros(nb, 1);
else
    q_by_bus = accumarray(state.bus_idx(active_idx), ...
        state.current_q(active_idx), [nb 1], @sum, 0);
end

mpc.bus(:, QD) = state.base_qd - q_by_bus;
mpc.psse.facts.qinj = state.current_q;
mpc.psse.facts.control = mp.psse_facts_report(state);
