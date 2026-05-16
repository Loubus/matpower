function mpc = psse_swshunt_update(mpc, state)
% psse_swshunt_update - Applies PSS/E switched shunt state to an MPC.
% ::
%
%   MPC = MP.PSSE_SWSHUNT_UPDATE(MPC, STATE)
%
% Updates ``mpc.bus(:, BS)`` and ``mpc.psse.swshunt.num(:, BINIT)`` from the
% switched shunt control state.
%
% See also mp.psse_swshunt_control, mp.psse_swshunt_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, ~, ~, ~, ~, ~, BS] = idx_bus;

nb = size(mpc.bus, 1);

%% keep the preserved RAW table synchronized with the controlled BINIT
mpc.psse.swshunt.num(:, state.binit_col) = state.current_b;

%% rebuild bus BS as fixed shunt plus active switched shunt contribution
active_idx = find(state.active & state.bus_idx > 0);
if isempty(active_idx)
    switched_by_bus = zeros(nb, 1);
else
    switched_by_bus = accumarray(state.bus_idx(active_idx), ...
        state.current_b(active_idx), [nb 1], @sum, 0);
end
mpc.bus(:, BS) = state.base_bs + switched_by_bus;
mpc.psse.swshunt.control = mp.psse_swshunt_report(state);
