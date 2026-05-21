function state = psse_genq_states(mpc)
% psse_genq_states - Builds PSS/E generator Q-control state.
% ::
%
%   STATE = MP.PSSE_GENQ_STATES(MPC)
%
% Builds the internal state used by the PSS/E generator reactive-power
% controller from metadata preserved in ``mpc.psse.genq`` and the current
% ``mpc.gen``/``mpc.bus`` matrices. The state supports both external and
% internal MATPOWER indexing.
%
% See also mp.psse_genq_prepare, mp.psse_genq_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, REF, ~, ~, BUS_TYPE] = idx_bus;
[GEN_BUS, ~, QG, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;

gq = mpc.psse.genq;
num = gq.num;
n = size(num, 1);
nb = size(mpc.bus, 1);

state = struct();
state.initialized = 1;
state.n = n;
state.iterations = 0;
state.num_adjustments = 0;
state.changed_last = 0;
state.max_iter_reached = 0;
state.report = struct();

state.varlim = psse_system_value(mpc, 'solver', 'VARLIM', 1);
state.varlim_enabled = isnan(state.varlim) || state.varlim >= 0;
state.max_iter = psse_system_value(mpc, 'adjust', 'MXTPSS', 99);
if isnan(state.max_iter) || state.max_iter <= 0
    state.max_iter = 99;
end
state.vtol = psse_system_value(mpc, 'newton', 'VCTOLV', 1e-5);
if isnan(state.vtol) || state.vtol <= 0
    state.vtol = 1e-5;
end
state.qtol = psse_system_value(mpc, 'newton', 'VCTOLQ', 0.1);
if isnan(state.qtol) || state.qtol <= 0
    state.qtol = 0.1;
end

state.gen_idx = psse_gen_map(mpc, n);
state.bus_ext = field_or_col(gq, num, 'bus_ext', 'I', NaN);
state.reg_bus_ext = field_or_col(gq, num, 'reg_bus_ext', 'IREG', 0);
local_reg = isnan(state.reg_bus_ext) | state.reg_bus_ext == 0;
state.reg_bus_ext(local_reg) = state.bus_ext(local_reg);
state.id = gen_ids(gq, n);
state.status = field_or_col(gq, num, 'status', 'STAT', 1);
state.vs = field_or_col(gq, num, 'vs', 'VS', NaN);
state.rmpct = field_or_col(gq, num, 'rmpct', 'RMPCT', 100);
state.rmpct(isnan(state.rmpct) | state.rmpct <= 0) = 100;

state.bus_idx = psse_bus_map(mpc, state.bus_ext);
state.base_bus_type = zeros(n, 1);
state.current_q = field_or_col(gq, num, 'qg', 'QG', NaN);
state.qmax = field_or_col(gq, num, 'qmax', 'QT', NaN);
state.qmin = field_or_col(gq, num, 'qmin', 'QB', NaN);
if isfield(gq, 'original_qmax') && length(gq.original_qmax) == n
    state.qmax = gq.original_qmax(:);
end
if isfield(gq, 'original_qmin') && length(gq.original_qmin) == n
    state.qmin = gq.original_qmin(:);
end

mapped = find(state.gen_idx > 0);
if ~isempty(mapped)
    gi = state.gen_idx(mapped);
    gen_bus_idx = gen_bus_map(mpc, mpc.gen(gi, GEN_BUS));
    missing_bus = state.bus_idx(mapped) <= 0;
    state.bus_idx(mapped(missing_bus)) = gen_bus_idx(missing_bus);
    state.current_q(mapped) = mpc.gen(gi, QG);
    if ~isfield(gq, 'original_qmax') || length(gq.original_qmax) ~= n
        state.qmax(mapped) = mpc.gen(gi, QMAX);
    end
    if ~isfield(gq, 'original_qmin') || length(gq.original_qmin) ~= n
        state.qmin(mapped) = mpc.gen(gi, QMIN);
    end
    vmissing = isnan(state.vs(mapped));
    if any(vmissing)
        mm = mapped(vmissing);
        state.vs(mm) = mpc.gen(state.gen_idx(mm), VG);
    end
    state.status(mapped) = mpc.gen(gi, GEN_STATUS);
end

state.reg_bus_idx = psse_bus_map(mpc, state.reg_bus_ext);
missing_reg = state.reg_bus_idx <= 0;
state.reg_bus_idx(missing_reg) = state.bus_idx(missing_reg);
state.reg_bus_ext(missing_reg) = state.bus_ext(missing_reg);

if isfield(gq, 'original_bus_type') && length(gq.original_bus_type) == n
    state.base_bus_type = gq.original_bus_type(:);
end
for kk = 1:n
    b = state.bus_idx(kk);
    if b > 0 && b <= nb && state.base_bus_type(kk) == 0
        state.base_bus_type(kk) = mpc.bus(b, BUS_TYPE);
    end
end

state.vs(isnan(state.vs)) = 1;
state.qmax(isnan(state.qmax)) = Inf;
state.qmin(isnan(state.qmin)) = -Inf;
state.current_q(isnan(state.current_q)) = 0;
state.status(isnan(state.status)) = 1;

state.active = state.status ~= 0 & state.gen_idx > 0 & state.bus_idx > 0;
state.local = state.active & (state.reg_bus_idx == state.bus_idx | ...
    state.reg_bus_ext == state.bus_ext);
state.remote = state.active & ~state.local & state.reg_bus_idx > 0;
state.swing = false(n, 1);
for kk = find(state.active)'
    b = state.bus_idx(kk);
    state.swing(kk) = b > 0 && b <= nb && ...
        (mpc.bus(b, BUS_TYPE) == REF || state.base_bus_type(kk) == REF);
end
state.at_min = state.active & state.current_q <= state.qmin + state.qtol;
state.at_max = state.active & state.current_q >= state.qmax - state.qtol;
state.limited = state.active & ~state.swing & state.varlim_enabled & ...
    state.qmax <= state.qmin + state.qtol;
state.controllable_local = state.active & state.local & ~state.swing;
state.controllable_remote = state.active & state.remote & ~state.swing;
state.unmapped = state.status ~= 0 & state.gen_idx <= 0;

group_reg = unique(state.reg_bus_idx(state.controllable_remote & ...
    state.reg_bus_idx > 0));
ng = length(group_reg);
state.group = struct();
state.group.reg_bus_idx = group_reg;
state.group.reg_bus_ext = zeros(ng, 1);
state.group.members = cell(ng, 1);
state.group.count = zeros(ng, 1);
state.group.rmpct_sum = zeros(ng, 1);
state.group.target_vs = zeros(ng, 1);
state.group.current_q = zeros(ng, 1);
state.group.qmin = zeros(ng, 1);
state.group.qmax = zeros(ng, 1);
state.group.vact = NaN(ng, 1);
state.group.margin = NaN(ng, 1);
state.group.all_limited = zeros(ng, 1);
state.group.qlo = NaN(ng, 1);
state.group.qhi = NaN(ng, 1);
state.group.vlo = NaN(ng, 1);
state.group.vhi = NaN(ng, 1);
state.group.last_q = NaN(ng, 1);
state.group.last_v = NaN(ng, 1);
for gg = 1:ng
    members = find(state.controllable_remote & state.reg_bus_idx == group_reg(gg));
    weights = state.rmpct(members);
    state.group.members{gg} = members;
    state.group.count(gg) = length(members);
    state.group.rmpct_sum(gg) = sum(weights);
    state.group.reg_bus_ext(gg) = state.reg_bus_ext(members(1));
    state.group.target_vs(gg) = weighted_mean(state.vs(members), weights);
    state.group.current_q(gg) = sum(state.current_q(members));
    state.group.qmin(gg) = sum(state.qmin(members));
    state.group.qmax(gg) = sum(state.qmax(members));
end

state.last_vm_final = NaN(n, 1);
state.last_margin = NaN(n, 1);
state.pct_q = state.rmpct;
state.pct_q(~state.active) = 0;
state.last_score = Inf;
state.last_violations = 0;
state.last_violation_sum = 0;
state.code_final = zeros(n, 1);
state.code_label = cell(n, 1);
state = refresh_codes(state);

function v = field_or_col(gq, num, field, colname, default)
if isfield(gq, field) && length(gq.(field)) == size(num, 1)
    v = gq.(field)(:);
else
    col = psse_col(gq.colnames, colname);
    v = default * ones(size(num, 1), 1);
    if col && col <= size(num, 2)
        v = num(:, col);
    end
end

function ids = gen_ids(gq, n)
ids = cell(n, 1);
for kk = 1:n
    ids{kk} = '';
end
if isfield(gq, 'id') && length(gq.id) == n
    ids = gq.id(:);
    return;
end
col = psse_col(gq.colnames, 'ID');
if col && col <= size(gq.txt, 2)
    for kk = 1:n
        str = gq.txt{kk, col};
        if numel(str) >= 2 && ((str(1) == '''' && str(end) == '''') || ...
                (str(1) == '"' && str(end) == '"'))
            str = str(2:end-1);
        end
        ids{kk} = strtrim(str);
    end
end

function col = psse_col(cols, name)
col = find(strcmpi(cols, name), 1);
if isempty(col)
    col = 0;
end

function gen_idx = psse_gen_map(mpc, n)
ng = size(mpc.gen, 1);
gen_idx = zeros(n, 1);
if isfield(mpc, 'order') && isfield(mpc.order, 'state') && ...
        mpc.order.state == 'i' && isfield(mpc.order, 'gen') && ...
        isfield(mpc.order.gen, 'status') && ...
        isfield(mpc.order.gen.status, 'on')
    on = mpc.order.gen.status.on(:);
    if isfield(mpc.order.gen, 'i2e') && ~isempty(mpc.order.gen.i2e)
        i2e = mpc.order.gen.i2e(:);
    else
        i2e = (1:length(on))';
    end
    for ii = 1:length(i2e)
        pos = i2e(ii);
        if pos > 0 && pos <= length(on)
            raw = on(pos);
            if raw > 0 && raw <= n
                gen_idx(raw) = ii;
            end
        end
    end
else
    k = min(n, ng);
    gen_idx(1:k) = (1:k)';
end

function idx = psse_bus_map(mpc, bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
idx = zeros(size(bus));
if isempty(bus)
    return;
end
if isfield(mpc, 'order') && isfield(mpc.order, 'state') && ...
        strcmp(mpc.order.state, 'i') && ...
        isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'e2i') && ~isempty(mpc.order.bus.e2i)
    e2i = mpc.order.bus.e2i;
else
    i2e = mpc.bus(:, BUS_I);
    if isempty(i2e)
        return;
    end
    e2i = sparse(i2e, ones(size(i2e)), 1:length(i2e), max(i2e), 1);
end
for kk = 1:length(bus)
    b = bus(kk);
    if ~isnan(b) && b > 0 && b <= size(e2i, 1)
        idx(kk) = full(e2i(b));
    end
end

function idx = gen_bus_map(mpc, bus)
% Return row indices for GEN_BUS values in external or internal cases.
idx = zeros(size(bus));
if isempty(bus)
    return;
end
if isfield(mpc, 'order') && isfield(mpc.order, 'state') && ...
        strcmp(mpc.order.state, 'i')
    nb = size(mpc.bus, 1);
    ok = ~isnan(bus) & bus > 0 & bus <= nb;
    idx(ok) = bus(ok);
else
    idx = psse_bus_map(mpc, bus);
end

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end

function v = weighted_mean(x, w)
w(isnan(w) | w <= 0) = 100;
if isempty(x)
    v = NaN;
elseif sum(w) == 0
    v = mean(x);
else
    v = sum(x .* w) / sum(w);
end

function state = refresh_codes(state)
for kk = 1:state.n
    if state.unmapped(kk)
        state.code_final(kk) = -9;
        state.code_label{kk} = 'UNMAPPED';
    elseif ~state.active(kk)
        state.code_final(kk) = 0;
        state.code_label{kk} = 'OFF';
    elseif state.swing(kk)
        state.code_final(kk) = 3;
        state.code_label{kk} = 'SWING';
    elseif state.limited(kk)
        state.code_final(kk) = -2;
        if state.at_min(kk)
            state.code_label{kk} = 'QMIN';
        elseif state.at_max(kk)
            state.code_label{kk} = 'QMAX';
        else
            state.code_label{kk} = 'LIMITED';
        end
    elseif state.remote(kk)
        state.code_final(kk) = 2;
        state.code_label{kk} = 'REMOTE';
    else
        state.code_final(kk) = 2;
        state.code_label{kk} = 'LOCAL';
    end
end
