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

[F_BUS, ~, BR_R, BR_X, ~, ~, ~, ~, TAP] = idx_brch;
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, BASE_KV] = idx_bus;

idx = find(state.branch_idx > 0);
if ~isempty(idx)
    mpc.branch(state.branch_idx(idx), TAP) = state.current_tap(idx);
end

idx = find(state.branch_idx > 0 & state.tab_applied & ...
    ~isnan(state.nominal_r) & ~isnan(state.nominal_x));
if ~isempty(idx) && isfield(mpc, 'psse') && isfield(mpc.psse, 'impcor')
    ratio = state.current_raw(idx);
    k = state.cw(idx) == 2;
    if any(k)
        rows = xfmr_base_kv_rows(mpc, state, idx(k), F_BUS);
        ok = rows > 0;
        ratio_k = ratio(k);
        ratio_k(ok) = ratio_k(ok) ./ mpc.bus(rows(ok), BASE_KV);
        ratio(k) = ratio_k;
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
if isfield(state, 'control_bus_i2e') && ~isempty(state.control_bus_i2e)
    mpc.psse.xfmr.control_bus_i2e = state.control_bus_i2e;
end
if isfield(state, 'control_branch_on') && ~isempty(state.control_branch_on)
    mpc.psse.xfmr.control_branch_on = state.control_branch_on;
end
if isfield(state, 'locked_out') && ~isempty(state.locked_out)
    mpc.psse.xfmr.control_locked_out = state.locked_out;
end
mpc.psse.xfmr.control_current_tap = state.current_tap;
mpc.psse.xfmr.control_current_raw = state.current_raw;
mpc.psse.xfmr.control = mp.psse_xfmr_report(state);

function rows = xfmr_base_kv_rows(mpc, state, idx, branch_bus_col)
[~, ~, ~, ~, BUS_I] = idx_bus;
rows = state.bus_idx(idx);
missing = rows <= 0;
for kk = find(missing(:))'
    br = state.branch_idx(idx(kk));
    if br <= 0 || br > size(mpc.branch, 1)
        continue;
    end
    b = mpc.branch(br, branch_bus_col);
    rows(kk) = branch_bus_row(mpc, b, BUS_I);
end

function row = branch_bus_row(mpc, bus, bus_i_col)
row = 0;
if isnan(bus) || bus <= 0
    return;
end
nb = size(mpc.bus, 1);
if bus <= nb && abs(bus - round(bus)) < 1e-9 && ...
        mpc.bus(bus, bus_i_col) == bus
    row = bus;
    return;
end
idx = psse_bus_map(mpc, bus);
if idx > 0
    row = idx;
elseif bus <= nb && abs(bus - round(bus)) < 1e-9
    row = bus;
end

function idx = psse_bus_map(mpc, bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
idx = 0;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'xfmr') && ...
        isfield(mpc.psse.xfmr, 'control_bus_i2e') && ...
        ~isempty(mpc.psse.xfmr.control_bus_i2e) && ...
        isequal(mpc.bus(:, BUS_I), (1:size(mpc.bus, 1))')
    i2e = mpc.psse.xfmr.control_bus_i2e(:);
    idx = bus_lookup(i2e, bus);
elseif isfield(mpc, 'order') && isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'i2e') && ~isempty(mpc.order.bus.i2e) && ...
        isequal(mpc.bus(:, BUS_I), (1:size(mpc.bus, 1))')
    idx = bus_lookup(mpc.order.bus.i2e(:), bus);
elseif isfield(mpc, 'order') && isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'e2i') && ~isempty(mpc.order.bus.e2i)
    e2i = mpc.order.bus.e2i;
    if bus <= size(e2i, 1)
        idx = full(e2i(bus));
    end
else
    idx = bus_lookup(mpc.bus(:, BUS_I), bus);
end

function idx = bus_lookup(i2e, bus)
idx = 0;
if bus > max(i2e)
    return;
end
e2i = sparse(i2e, ones(length(i2e), 1), (1:length(i2e))', max(i2e), 1);
idx = full(e2i(bus));
