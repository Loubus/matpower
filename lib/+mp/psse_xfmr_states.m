function state = psse_xfmr_states(mpc)
% psse_xfmr_states - Builds PSS/E transformer tap-control state.
% ::
%
%   STATE = MP.PSSE_XFMR_STATES(MPC)
%
% Builds the internal state used by mp.task_pf_psse to control PSS/E
% voltage-regulating transformer taps from metadata preserved in
% ``mpc.psse.xfmr``.
%
% See also mp.psse_xfmr_control, mp.psse_xfmr_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, NONE, ~, BUS_TYPE] = idx_bus;
[~, ~, ~, ~, ~, ~, ~, ~, TAP, ~, BR_STATUS] = idx_brch;

xf = mpc.psse.xfmr;

state = struct();
state.initialized = 1;
state.iterations = 0;
state.num_adjustments = 0;
state.changed_last = 0;
state.max_iter_reached = 0;
state.report = struct();

state.actaps = psse_system_value(mpc, 'solver', 'ACTAPS', NaN);
state.enabled = ~isnan(state.actaps) && state.actaps ~= 0;
state.max_iter = psse_system_value(mpc, 'adjust', 'MXTPSS', 99);
if isnan(state.max_iter) || state.max_iter <= 0
    state.max_iter = 99;
end
state.vtol = psse_system_value(mpc, 'newton', 'VCTOLV', 1e-5);
if isnan(state.vtol) || state.vtol <= 0
    state.vtol = 1e-5;
end

state.kind = [];
state.raw_row = [];
state.winding = [];
state.branch_ext = [];
state.winding_bus_ext = [];
state.other_bus_ext = [];
state.cw = [];
state.stat = [];
state.cod = [];
state.cont = [];
state.rma = [];
state.rmi = [];
state.vma = [];
state.vmi = [];
state.ntp = [];
state.tab = [];
state.tab_applied = [];
state.cr = [];
state.cx = [];
state.windv = [];
state.windv2 = [];
state.ang = [];
state.nomv = [];
state.nomv2 = [];
state.windv_col = [];
state.nominal_r = [];
state.nominal_x = [];

state = add_two_winding(state, xf.two);
state = add_three_winding(state, xf.three);
state.n = length(state.cod);

state.branch_idx = psse_branch_map(mpc, state.branch_ext);
state.bus_idx = psse_bus_map(mpc, state.winding_bus_ext);
reg_ext = abs(state.cont);
state.reg_bus_idx = psse_bus_map(mpc, reg_ext);

reg_ok = false(size(state.reg_bus_idx));
rr = find(state.reg_bus_idx > 0);
reg_ok(rr) = mpc.bus(state.reg_bus_idx(rr), BUS_TYPE) ~= NONE;
br_ok = state.branch_idx > 0;
state.branch_status = zeros(state.n, 1);
state.branch_status(br_ok) = mpc.branch(state.branch_idx(br_ok), BR_STATUS);

state.active = state.stat ~= 0;
k3 = find(state.kind == 3);
state.active(k3) = ~(state.stat(k3) == 0 | ...
    (state.stat(k3) == 4 & state.winding(k3) == 1) | ...
    (state.stat(k3) == 2 & state.winding(k3) == 2) | ...
    (state.stat(k3) == 3 & state.winding(k3) == 3));
state.active = state.active & state.branch_status ~= 0 & br_ok;

state.automatic = state.active & abs(state.cod) == 1;
state.suppressed_auto = state.active & state.cod == -1;
state.cont_missing = state.active & state.cod == 1 & state.cont == 0;
state.unsupported_cod = state.active & state.cod ~= 0 & abs(state.cod) ~= 1;
state.unsupported_cw = state.active & state.cod == 1 & ...
    ~(state.cw == 1 | state.cw == 2);
state.unsupported_comp = state.active & state.cod == 1 & ...
    (abs(state.cr) > 1e-12 | abs(state.cx) > 1e-12);
state.unsupported_tab = state.active & state.cod == 1 & state.tab ~= 0;
state.unsupported_tab = state.unsupported_tab & ~state.tab_applied;
state.tab_corrected = state.active & state.tab ~= 0 & state.tab_applied;
state.controllable = state.enabled & state.active & state.cod == 1 & ...
    state.cont ~= 0 & state.ntp >= 2 & reg_ok & ...
    (state.cw == 1 | state.cw == 2) & ...
    abs(state.cr) <= 1e-12 & abs(state.cx) <= 1e-12 & ...
    (state.tab == 0 | state.tab_applied);

state.side_sign = tap_side_sign(state);

state.base_tap = zeros(state.n, 1);
state.current_tap = zeros(state.n, 1);
state.current_raw = state.windv;
state.states_raw = cell(state.n, 1);
state.states_tap = cell(state.n, 1);
state.at_min = false(state.n, 1);
state.at_max = false(state.n, 1);

for k = 1:state.n
    if state.branch_idx(k) > 0
        tap = mpc.branch(state.branch_idx(k), TAP);
        if tap == 0
            tap = 1;
        end
        state.base_tap(k) = tap;
        state.current_tap(k) = tap;
    end
    raw_states = [];
    tap_states = [];
    if state.controllable(k)
        [raw_states, tap_states] = tap_states_for_control(state, mpc, k);
    end
    state.states_raw{k} = raw_states;
    state.states_tap{k} = tap_states;
    if state.controllable(k) && ~isempty(tap_states)
        [~, jj] = min(abs(tap_states - state.current_tap(k)));
        state.current_tap(k) = tap_states(jj);
        state.current_raw(k) = raw_states(jj);
    end
end

state.needs_initial_update = state.enabled && any(state.controllable & ...
    abs(state.current_tap - state.base_tap) > 1e-9);

state.last_vm_final = NaN(state.n, 1);
state.last_margin = NaN(state.n, 1);
state.last_score = Inf;
state.last_violations = 0;
state.last_violation_sum = 0;
state.best_score = Inf;
state.best_tap = state.current_tap;
state.best_raw = state.current_raw;
state.best_violations = 0;
state.best_violation_sum = 0;
state.visited_signatures = {};
state.cycle_detected = 0;
state.cycle_resolved = 0;
state.repeated_states = 0;
state.cycle_resolution_changes = 0;

function state = add_two_winding(state, two)
num = two.num;
if isempty(num)
    return;
end
c = two.col;
n = size(num, 1);
tab_applied = false(n, 1);
if isfield(two, 'tab_applied') && ~isempty(two.tab_applied)
    tab_applied = logical(two.tab_applied(:));
end
nominal_rx = NaN(n, 2);
if isfield(two, 'nominal_rx') && ~isempty(two.nominal_rx)
    nominal_rx = two.nominal_rx;
end
state.kind = [state.kind; 2 * ones(n, 1)];
state.raw_row = [state.raw_row; (1:n)'];
state.winding = [state.winding; ones(n, 1)];
state.branch_ext = [state.branch_ext; two.branch_idx(:)];
state.winding_bus_ext = [state.winding_bus_ext; num(:, c.i)];
state.other_bus_ext = [state.other_bus_ext; abs(num(:, c.j))];
state.cw = [state.cw; col(num, c.cw, 1)];
state.stat = [state.stat; col(num, c.stat, 1)];
state.cod = [state.cod; col(num, c.cod1, 0)];
state.cont = [state.cont; col(num, c.cont1, 0)];
state.rma = [state.rma; col(num, c.rma1, NaN)];
state.rmi = [state.rmi; col(num, c.rmi1, NaN)];
state.vma = [state.vma; col(num, c.vma1, 1.1)];
state.vmi = [state.vmi; col(num, c.vmi1, 0.9)];
state.ntp = [state.ntp; round(col(num, c.ntp1, 33))];
state.tab = [state.tab; col(num, c.tab1, 0)];
state.tab_applied = [state.tab_applied; tab_applied];
state.cr = [state.cr; col(num, c.cr1, 0)];
state.cx = [state.cx; col(num, c.cx1, 0)];
state.windv = [state.windv; col(num, c.windv1, 1)];
state.windv2 = [state.windv2; col(num, c.windv2, 1)];
state.ang = [state.ang; col(num, c.ang1, 0)];
state.nomv = [state.nomv; col(num, c.nomv1, 0)];
state.nomv2 = [state.nomv2; col(num, c.nomv2, 0)];
state.windv_col = [state.windv_col; c.windv1 * ones(n, 1)];
state.nominal_r = [state.nominal_r; nominal_rx(:, 1)];
state.nominal_x = [state.nominal_x; nominal_rx(:, 2)];

function state = add_three_winding(state, three)
num = three.num;
if isempty(num)
    return;
end
c = three.col;
tab_applied = false(size(num, 1), 3);
if isfield(three, 'tab_applied') && ~isempty(three.tab_applied)
    tab_applied = logical(three.tab_applied);
end
nominal_rx = NaN(size(num, 1), 3, 2);
if isfield(three, 'nominal_rx') && ~isempty(three.nominal_rx)
    nominal_rx = three.nominal_rx;
end
for w = 1:3
    n = size(num, 1);
    state.kind = [state.kind; 3 * ones(n, 1)];
    state.raw_row = [state.raw_row; (1:n)'];
    state.winding = [state.winding; w * ones(n, 1)];
    state.branch_ext = [state.branch_ext; three.branch_idx(:, w)];
    switch w
        case 1
            bus_col = c.i; windv_col = c.windv1; nomv_col = c.nomv1;
            cod_col = c.cod1; cont_col = c.cont1; rma_col = c.rma1;
            rmi_col = c.rmi1; vma_col = c.vma1; vmi_col = c.vmi1;
            ntp_col = c.ntp1; tab_col = c.tab1; cr_col = c.cr1; cx_col = c.cx1;
        case 2
            bus_col = c.j; windv_col = c.windv2; nomv_col = c.nomv2;
            cod_col = c.cod2; cont_col = c.cont2; rma_col = c.rma2;
            rmi_col = c.rmi2; vma_col = c.vma2; vmi_col = c.vmi2;
            ntp_col = c.ntp2; tab_col = c.tab2; cr_col = c.cr2; cx_col = c.cx2;
        case 3
            bus_col = c.k; windv_col = c.windv3; nomv_col = c.nomv3;
            cod_col = c.cod3; cont_col = c.cont3; rma_col = c.rma3;
            rmi_col = c.rmi3; vma_col = c.vma3; vmi_col = c.vmi3;
            ntp_col = c.ntp3; tab_col = c.tab3; cr_col = c.cr3; cx_col = c.cx3;
    end
    state.winding_bus_ext = [state.winding_bus_ext; abs(num(:, bus_col))];
    state.other_bus_ext = [state.other_bus_ext; zeros(n, 1)];
    state.cw = [state.cw; col(num, c.cw, 1)];
    state.stat = [state.stat; col(num, c.stat, 1)];
    state.cod = [state.cod; col(num, cod_col, 0)];
    state.cont = [state.cont; col(num, cont_col, 0)];
    state.rma = [state.rma; col(num, rma_col, NaN)];
    state.rmi = [state.rmi; col(num, rmi_col, NaN)];
    state.vma = [state.vma; col(num, vma_col, 1.1)];
    state.vmi = [state.vmi; col(num, vmi_col, 0.9)];
    state.ntp = [state.ntp; round(col(num, ntp_col, 33))];
    state.tab = [state.tab; col(num, tab_col, 0)];
    state.tab_applied = [state.tab_applied; tab_applied(:, w)];
    state.cr = [state.cr; col(num, cr_col, 0)];
    state.cx = [state.cx; col(num, cx_col, 0)];
    state.windv = [state.windv; col(num, windv_col, 1)];
    state.windv2 = [state.windv2; ones(n, 1)];
    state.ang = [state.ang; col(num, angle_col(w, c), 0)];
    state.nomv = [state.nomv; col(num, nomv_col, 0)];
    state.nomv2 = [state.nomv2; zeros(n, 1)];
    state.windv_col = [state.windv_col; windv_col * ones(n, 1)];
    state.nominal_r = [state.nominal_r; nominal_rx(:, w, 1)];
    state.nominal_x = [state.nominal_x; nominal_rx(:, w, 2)];
end

function v = col(num, c, default)
if c && size(num, 2) >= c
    v = num(:, c);
else
    v = default * ones(size(num, 1), 1);
end
v(isnan(v)) = default;

function cang = angle_col(w, c)
switch w
    case 1
        cang = c.ang1;
    case 2
        cang = c.ang2;
    otherwise
        cang = c.ang3;
end

function side = tap_side_sign(state)
% Determine MATPOWER tap movement direction for PSS/E voltage control.
side = ones(state.n, 1);
side(state.cont < 0) = -1;
k = state.kind == 2 & state.cont ~= 0;
terminal = k & abs(state.cont) == state.other_bus_ext;
remote = k & ~terminal;
side(terminal) = -1;
side(remote) = -sign(state.cont(remote));

function [raw_states, tap_states] = tap_states_for_control(state, mpc, k)
raw_states = [];
tap_states = [];
if state.ntp(k) < 2 || isnan(state.rma(k)) || isnan(state.rmi(k))
    return;
end
lo = min(state.rmi(k), state.rma(k));
hi = max(state.rmi(k), state.rma(k));
raw_states = linspace(lo, hi, state.ntp(k))';
tap_states = raw_to_tap(state, mpc, k, raw_states);
[tap_states, ord] = sort(tap_states);
raw_states = raw_states(ord);

function tap = raw_to_tap(state, mpc, k, raw)
[~, T_BUS] = idx_brch;
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, BASE_KV] = idx_bus;
if state.kind(k) == 2
    w2 = state.windv2(k);
    if isnan(w2) || w2 == 0
        w2 = 1;
    end
    tap = raw ./ w2;
    if state.cw(k) == 2
        f = state.bus_idx(k);
        br = state.branch_idx(k);
        if isfield(mpc, 'order') && isfield(mpc.order, 'bus')
            t = mpc.branch(br, T_BUS);
        else
            t = psse_bus_map(mpc, mpc.branch(br, T_BUS));
        end
        if f > 0 && t > 0
            tap = tap .* mpc.bus(t, BASE_KV) ./ mpc.bus(f, BASE_KV);
        end
    elseif state.cw(k) == 3
        n1 = state.nomv(k);
        n2 = state.nomv2(k);
        if n1 ~= 0 && n2 ~= 0
            tap = tap .* n1 ./ n2;
        end
    end
else
    tap = raw;
    f = state.bus_idx(k);
    if state.cw(k) == 2 && f > 0
        tap = tap ./ mpc.bus(f, BASE_KV);
    elseif state.cw(k) == 3
        n1 = state.nomv(k);
        if n1 ~= 0
            tap = tap .* n1;
        end
    end
end

function idx = psse_bus_map(mpc, bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
idx = zeros(size(bus));
if isempty(bus)
    return;
end
if isfield(mpc, 'order') && isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'e2i') && ~isempty(mpc.order.bus.e2i)
    e2i = mpc.order.bus.e2i;
    for kk = 1:length(bus)
        b = abs(bus(kk));
        if ~isnan(b) && b > 0 && b <= size(e2i, 1)
            idx(kk) = full(e2i(b));
        end
    end
else
    nbus = size(mpc.bus, 1);
    i2e = mpc.bus(:, BUS_I);
    e2i = sparse(i2e, ones(nbus, 1), 1:nbus, max(i2e), 1);
    for kk = 1:length(bus)
        b = abs(bus(kk));
        if ~isnan(b) && b > 0 && b <= size(e2i, 1)
            idx(kk) = full(e2i(b));
        end
    end
end

function idx = psse_branch_map(mpc, branch)
idx = zeros(size(branch));
if isempty(branch)
    return;
end
if isfield(mpc, 'order') && isfield(mpc.order, 'branch') && ...
        isfield(mpc.order.branch, 'status') && ...
        isfield(mpc.order.branch.status, 'on')
    on = mpc.order.branch.status.on;
    if isempty(on)
        return;
    end
    e2i = zeros(max(on), 1);
    e2i(on) = (1:length(on))';
    for kk = 1:length(branch)
        b = branch(kk);
        if ~isnan(b) && b > 0 && b <= length(e2i)
            idx(kk) = e2i(b);
        end
    end
else
    idx = branch;
    idx(isnan(idx)) = 0;
end

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end
