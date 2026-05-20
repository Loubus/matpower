function mpc = psse_xfmr_update(mpc, state)
% psse_xfmr_update - Applies PSS/E transformer tap state to an MPC.
% ::
%
%   MPC = MP.PSSE_XFMR_UPDATE(MPC, STATE)
%
% Updates ``mpc.branch(:, TAP)`` and the preserved transformer winding
% ``WINDV`` fields from the PSS/E transformer tap-control state.
%
% See also mp.psse_xfmr_control, mp.psse_xfmr_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, BR_R, BR_X, ~, ~, ~, ~, TAP] = idx_brch;
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, BASE_KV] = idx_bus;

idx = find(state.branch_idx > 0);
if ~isempty(idx)
    mpc.branch(state.branch_idx(idx), TAP) = state.current_tap(idx);
end

idx = find(state.branch_idx > 0 & state.tab_applied & ...
    ~isnan(state.nominal_r) & ~isnan(state.nominal_x));
if ~isempty(idx) && isfield(mpc, 'psse') && isfield(mpc.psse, 'impcor')
    ratio = state.current_raw(idx);
    k = state.cw(idx) == 2 & state.bus_idx(idx) > 0;
    if any(k)
        ratio(k) = ratio(k) ./ mpc.bus(state.bus_idx(idx(k)), BASE_KV);
    end
    [factor, applied] = mp.psse_xfmr_tab_factor( ...
        mpc.psse.impcor, state.tab(idx), ratio, state.ang(idx));
    idx = idx(applied);
    if ~isempty(idx)
        z = (state.nominal_r(idx) + 1j * state.nominal_x(idx)) .* factor(applied);
        mpc.branch(state.branch_idx(idx), BR_R) = real(z);
        mpc.branch(state.branch_idx(idx), BR_X) = imag(z);
    end
end

for kk = 1:state.n
    row = state.raw_row(kk);
    col = state.windv_col(kk);
    if state.kind(kk) == 2
        mpc.psse.xfmr.two.num(row, col) = state.current_raw(kk);
    else
        mpc.psse.xfmr.three.num(row, col) = state.current_raw(kk);
    end
end
mpc.psse.xfmr.control = mp.psse_xfmr_report(state);
