function state = psse_facts_states(mpc)
% psse_facts_states - Builds PSS/E FACTS device control state.
% ::
%
%   STATE = MP.PSSE_FACTS_STATES(MPC)
%
% Builds the internal state used by mp.task_pf_psse to control the PSS/E
% FACTS device behavior in scope for this extension: active STATCON records
% with ``MODE = 1`` and ``J = 0``. The controlled variable is reactive power
% injection at the sending-end bus, used to regulate the local or remote
% ``FCREG`` bus voltage.
%
% See also mp.psse_facts_control, mp.psse_facts_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[PQ, PV, ~, ~, ~, BUS_TYPE, ~, QD] = idx_bus;

fx = mpc.psse.facts;
num = fx.num;
cols = fx.colnames;
nf = size(num, 1);
nb = size(mpc.bus, 1);

state = struct();
state.initialized = 1;
state.n = nf;
state.iterations = 0;
state.num_adjustments = 0;
state.changed_last = 0;
state.max_iter_reached = 0;
state.report = struct();

%% SYSTEM-WIDE options and tolerances used by iterative PSS/E controls
state.facts = psse_system_value(mpc, 'solver', 'FACTS', NaN);
state.enabled = isnan(state.facts) || state.facts ~= 0;
state.max_iter = psse_system_value(mpc, 'adjust', 'MXTPSS', 99);
if isnan(state.max_iter) || state.max_iter <= 0
    state.max_iter = 99;
end
state.vtol = psse_system_value(mpc, 'newton', 'VCTOLV', 1e-5);
if isnan(state.vtol) || state.vtol <= 0
    state.vtol = 1e-5;
end

%% locate PSS/E FACTS columns
i_col = psse_col(cols, 'I');
j_col = psse_col(cols, 'J');
mode_col = psse_col(cols, 'MODE');
vset_col = psse_col(cols, 'VSET');
shmx_col = psse_col(cols, 'SHMX');
trmx_col = psse_col(cols, 'TRMX');
rmpct_col = psse_col(cols, 'RMPCT');
fcreg_col = psse_col(cols, 'FCREG');

state.i_col = i_col;
state.j_col = j_col;
state.mode_col = mode_col;
state.vset_col = vset_col;
state.shmx_col = shmx_col;
state.bus_ext = col_default(num, i_col, 0);
state.j_ext = col_default(num, j_col, 0);
state.mode = col_default(num, mode_col, 0);
state.vset = col_default(num, vset_col, 1);
state.shmx = col_default(num, shmx_col, 0);
state.trmx = col_default(num, trmx_col, NaN);
state.rmpct = col_default(num, rmpct_col, 100);
state.rmpct(isnan(state.rmpct) | state.rmpct <= 0) = 100;
state.fcreg = col_default(num, fcreg_col, 0);

%% map sending-end and regulated buses from external RAW numbers to MPC rows
state.bus_idx = psse_bus_map(mpc, state.bus_ext);
reg_ext = state.fcreg;
reg_ext(isnan(reg_ext) | reg_ext == 0) = ...
    state.bus_ext(isnan(reg_ext) | reg_ext == 0);
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
bus_ok(bb) = mpc.bus(state.bus_idx(bb), BUS_TYPE) == PQ;
state.bus_type_ok = bus_ok;

%% recognize only STATCON FACTS records present in the target RAW
state.active = state.mode ~= 0 & state.bus_idx > 0;
state.statcon = state.active & state.j_ext == 0 & state.mode == 1;
state.series_device = state.active & state.j_ext ~= 0;
state.unsupported_mode = state.active & ~(state.mode == 1 & state.j_ext == 0);
state.unsupported_i_bus = state.statcon & ~bus_ok;
state.recognized = state.statcon & bus_ok & state.reg_bus_idx > 0;
state.controllable = state.enabled & state.recognized;
state.remote_regulated = state.controllable & state.fcreg ~= 0 & ...
    state.fcreg ~= state.bus_ext;

state.current_q = zeros(nf, 1);
if isfield(fx, 'qinj') && ~isempty(fx.qinj)
    n = min(length(fx.qinj), nf);
    state.current_q(1:n) = fx.qinj(1:n);
end

%% group controllable STATCON devices by effective regulated bus
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

state.needs_initial_update = 0;
if nf
    active_idx = find(state.active & state.bus_idx > 0);
    if isempty(active_idx)
        q_by_bus = zeros(nb, 1);
    else
        q_by_bus = accumarray(state.bus_idx(active_idx), ...
            state.current_q(active_idx), [nb 1], @sum, 0);
    end
    state.base_qd = mpc.bus(:, QD) + q_by_bus;
else
    state.base_qd = mpc.bus(:, QD);
end
state.last_vm = NaN(nb, 1);
state.last_q = NaN(nb, 1);
state.last_direction = zeros(nf, 1);
state.last_vm_final = NaN(nf, 1);
state.last_vi_final = NaN(nf, 1);
state.last_margin = NaN(nf, 1);
state.last_qmin = NaN(nf, 1);
state.last_qmax = NaN(nf, 1);
state.at_min = false(nf, 1);
state.at_max = false(nf, 1);
state.limited = false(nf, 1);
state.last_score = Inf;
state.last_violations = 0;
state.last_violation_sum = 0;
state.best_score = Inf;
state.best_q = state.current_q;
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
    e2i = sparse(i2e, ones(size(i2e)), 1:length(i2e), max(i2e), 1);
    for kk = 1:length(bus)
        b = bus(kk);
        if ~isnan(b) && b > 0 && b <= size(e2i, 1)
            idx(kk) = full(e2i(b));
        end
    end
end

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end
