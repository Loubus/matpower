function state = psse_swshunt_states(mpc)
% psse_swshunt_states - Builds PSS/E switched shunt control state.
% ::
%
%   STATE = MP.PSSE_SWSHUNT_STATES(MPC)
%
% Builds the internal state used by mp.task_pf_psse to control PSS/E
% switched shunts from metadata preserved in ``mpc.psse.swshunt``.
%
% See also mp.psse_swshunt_control, mp.psse_swshunt_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[PQ, PV, ~, ~, ~, BUS_TYPE, ~, ~, ~, BS] = idx_bus;

sw = mpc.psse.swshunt;
num = sw.num;
cols = sw.colnames;
nb = size(mpc.bus, 1);
ns = size(num, 1);

state = struct();
state.initialized = 1;
state.n = ns;
state.iterations = 0;
state.num_adjustments = 0;
state.changed_last = 0;
state.max_iter_reached = 0;
state.report = struct();

%% SYSTEM-WIDE options that affect switched shunt adjustment
state.swshnt = psse_system_value(mpc, 'solver', 'SWSHNT', NaN);
state.enabled = isnan(state.swshnt) || state.swshnt ~= 0;
state.max_iter = psse_system_value(mpc, 'adjust', 'MXTPSS', 99);
if isnan(state.max_iter) || state.max_iter <= 0
    state.max_iter = 99;
end
state.vtol = psse_system_value(mpc, 'newton', 'VCTOLV', 1e-5);
if isnan(state.vtol) || state.vtol <= 0
    state.vtol = 1e-5;
end

%% locate PSS/E switched shunt columns, including older naming variants
i_col = psse_col(cols, 'I');
modsw_col = psse_col(cols, 'MODSW');
adjm_col = psse_col(cols, 'ADJM');
stat_col = psse_col(cols, 'STAT');
if ~stat_col
    stat_col = psse_col(cols, 'ST');
end
vswhi_col = psse_col(cols, 'VSWHI');
vswlo_col = psse_col(cols, 'VSWLO');
swreg_col = psse_col(cols, 'SWREG');
if ~swreg_col
    swreg_col = psse_col(cols, 'SWREM');
end
rmpct_col = psse_col(cols, 'RMPCT');
binit_col = sw.binit_col;

state.i_col = i_col;
state.binit_col = binit_col;
state.bus_ext = col_default(num, i_col, 0);
state.modsw = col_default(num, modsw_col, 0);
state.adjm = col_default(num, adjm_col, 0);
state.stat = col_default(num, stat_col, 1);
state.vswhi = col_default(num, vswhi_col, 1);
state.vswlo = col_default(num, vswlo_col, 1);
state.swreg = col_default(num, swreg_col, 0);
state.rmpct = col_default(num, rmpct_col, 100);
state.rmpct(isnan(state.rmpct) | state.rmpct <= 0) = 100;
state.raw_binit = col_default(num, binit_col, 0);
state.raw_binit(isnan(state.raw_binit)) = 0;

%% map local/remote regulating buses from external RAW numbers to MPC rows
state.bus_idx = psse_bus_map(mpc, state.bus_ext);
reg_ext = state.swreg;
reg_ext(isnan(reg_ext) | reg_ext == 0) = state.bus_ext(isnan(reg_ext) | reg_ext == 0);
reg_idx = psse_bus_map(mpc, reg_ext);
self_idx = state.bus_idx;
remote_ok = false(size(reg_idx));
rr = find(reg_idx > 0);
remote_ok(rr) = mpc.bus(reg_idx(rr), BUS_TYPE) == PQ | ...
    mpc.bus(reg_idx(rr), BUS_TYPE) == PV;
reg_idx(~remote_ok) = self_idx(~remote_ok);
state.reg_bus_idx = reg_idx;

bus_ok = false(size(state.bus_idx));
bb = find(state.bus_idx > 0);
bus_ok(bb) = mpc.bus(state.bus_idx(bb), BUS_TYPE) == PQ | ...
    mpc.bus(state.bus_idx(bb), BUS_TYPE) == PV;
state.active = state.stat ~= 0 & state.bus_idx > 0;

%% recognize only the PSS/E switched shunt controls in scope for this task
state.automatic = state.active & (state.modsw == 1 | state.modsw == 2);
state.recognized = state.automatic & bus_ok;
state.controllable = state.enabled & state.recognized & state.adjm == 0 & ...
    (state.modsw == 1 | state.modsw == 2);
state.unsupported_modsw = state.active & state.modsw >= 3 & state.modsw <= 6;
state.unsupported_adjm = state.enabled & state.recognized & state.adjm ~= 0;

%% group controllable devices by effective regulated bus
group_reg = unique(state.reg_bus_idx(state.controllable & state.reg_bus_idx > 0));
ng = length(group_reg);
state.group = struct();
state.group.reg_bus_idx = group_reg;
state.group.members = cell(ng, 1);
state.group.count = zeros(ng, 1);
state.group.rmpct_sum = zeros(ng, 1);
for kk = 1:ng
    members = find(state.controllable & state.reg_bus_idx == group_reg(kk));
    state.group.members{kk} = members;
    state.group.count(kk) = length(members);
    state.group.rmpct_sum(kk) = sum(state.rmpct(members));
end

[state.n_cols, state.b_cols] = psse_block_cols(cols);
state.states = cell(ns, 1);
state.bmin = zeros(ns, 1);
state.bmax = zeros(ns, 1);
state.current_b = state.raw_binit;

%% expand Rev34 N/B block data into admissible discrete/continuous B ranges
for k = 1:ns
    [b_states, bmin, bmax] = psse_row_states(num(k, :), state.n_cols, state.b_cols);
    state.states{k} = b_states;
    state.bmin(k) = bmin;
    state.bmax(k) = bmax;
    if state.enabled && state.active(k)
        if state.modsw(k) == 1
            [~, jj] = min(abs(b_states - state.raw_binit(k)));
            state.current_b(k) = b_states(jj);
        elseif state.modsw(k) == 2
            state.current_b(k) = min(max(state.raw_binit(k), bmin), bmax);
        end
    end
end

state.needs_initial_update = state.enabled && any(abs(state.current_b(state.active) - ...
    state.raw_binit(state.active)) > 1e-9);

%% separate fixed bus BS from the switched shunt BINIT controlled state
active_idx = find(state.active & state.bus_idx > 0);
if isempty(active_idx)
    switched_by_bus = zeros(nb, 1);
else
    switched_by_bus = accumarray(state.bus_idx(active_idx), ...
        state.raw_binit(active_idx), [nb 1], @sum, 0);
end
state.base_bs = mpc.bus(:, BS) - switched_by_bus;

state.last_vm = NaN(nb, 1);
state.last_b = NaN(nb, 1);
state.last_direction = zeros(ns, 1);
state.cycle_blocked = false(ns, 1);
state.last_vm_final = NaN(ns, 1);
state.last_margin = NaN(ns, 1);
state.last_score = Inf;
state.last_violations = 0;
state.last_violation_sum = 0;
state.best_score = Inf;
state.best_b = state.current_b;
state.best_violations = 0;
state.best_violation_sum = 0;
state.visited_signatures = {};
state.cycle_detected = 0;
state.cycle_resolved = 0;
state.repeated_states = 0;
state.cycle_resolution_changes = 0;

function v = col_default(num, col, default)
if col && size(num, 2) >= col
    v = num(:, col);
else
    v = default * ones(size(num, 1), 1);
end

function col = psse_col(cols, name)
col = find(strcmpi(cols, name), 1);
if isempty(col)
    col = 0;
end

function idx = psse_bus_map(mpc, bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
nbus = size(mpc.bus, 1);
idx = zeros(size(bus));
if isfield(mpc, 'order') && isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'e2i') && ~isempty(mpc.order.bus.e2i)
    e2i = mpc.order.bus.e2i;
    for kk = 1:length(bus)
        b = bus(kk);
        if ~isnan(b) && b > 0 && b <= size(e2i, 1)
            idx(kk) = full(e2i(b));
        end
    end
else
    i2e = mpc.bus(:, BUS_I);
    e2i = sparse(i2e, ones(nbus, 1), 1:nbus, max(i2e), 1);
    for kk = 1:length(bus)
        b = bus(kk);
        if ~isnan(b) && b > 0 && b <= size(e2i, 1)
            idx(kk) = full(e2i(b));
        end
    end
end

function [n_cols, b_cols] = psse_block_cols(cols)
n_cols = zeros(1, 8);
b_cols = zeros(1, 8);
nb = 0;
for kk = 1:8
    n_col = find(strcmpi(cols, sprintf('N%d', kk)), 1);
    b_col = find(strcmpi(cols, sprintf('B%d', kk)), 1);
    if ~isempty(n_col) && ~isempty(b_col)
        nb = nb + 1;
        n_cols(nb) = n_col;
        b_cols(nb) = b_col;
    end
end
n_cols = n_cols(1:nb);
b_cols = b_cols(1:nb);

function [states, bmin, bmax] = psse_row_states(row, n_cols, b_cols)
nvals = zeros(length(n_cols), 1);
bvals = zeros(length(n_cols), 1);
nb = 0;
for kk = 1:length(n_cols)
    n = row(n_cols(kk));
    b = row(b_cols(kk));
    if isnan(n) || isnan(b) || n == 0 || b == 0
        break;
    end
    nb = nb + 1;
    nvals(nb) = abs(round(n));
    bvals(nb) = b;
end

nvals = nvals(1:nb);
bvals = bvals(1:nb);
neg_states = zeros(sum(nvals(bvals < 0)), 1);
pos_states = zeros(sum(nvals(bvals > 0)), 1);
neg = 0;
pos = 0;
nn = 0;
np = 0;

for kk = 1:nb
    n = nvals(kk);
    b = bvals(kk);
    if b < 0
        for jj = 1:n
            neg = neg + b;
            nn = nn + 1;
            neg_states(nn) = neg;
        end
    else
        for jj = 1:n
            pos = pos + b;
            np = np + 1;
            pos_states(np) = pos;
        end
    end
end
neg_states = neg_states(1:nn);
pos_states = pos_states(1:np);
states = unique([flipud(neg_states(:)); 0; pos_states(:)], 'stable');
states = sort(states);
if isempty(states)
    states = 0;
end
bmin = min(states);
bmax = max(states);

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end
