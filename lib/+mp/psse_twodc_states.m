function state = psse_twodc_states(mpc)
% psse_twodc_states - Builds PSS/E two-terminal DC control state.
% ::
%
%   STATE = MP.PSSE_TWODC_STATES(MPC)
%
% Builds the internal state used by mp.task_pf_psse to update the LCC-backed
% dcline equivalent of preserved PSS/E two-terminal DC records.
%
% See also mp.psse_twodc_control, mp.psse_twodc_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

c = idx_dcline;

twodc = mpc.psse.twodc;
num = twodc.num;
col = twodc.col;
n = size(num, 1);

state = struct();
state.initialized = 1;
state.n = n;
state.col = col;
state.report = struct();

state.dctaps = psse_system_value(mpc, 'solver', 'DCTAPS', NaN);
state.enabled = 1;
state.dctaps_enabled = isnan(state.dctaps) || state.dctaps ~= 0;
state.max_iter = psse_system_value(mpc, 'adjust', 'MXTPSS', 20);
if isnan(state.max_iter) || state.max_iter <= 0
    state.max_iter = 20;
end
state.iterations = 0;
state.max_iter_reached = 0;
state.changed_last = 0;
state.num_adjustments = 0;

state.dcline_idx = (1:n)';
if isfield(twodc, 'dcline_idx')
    state.dcline_idx = twodc.dcline_idx(:);
end
if isfield(mpc, 'order') && isfield(mpc.order, 'dcline') && ...
        isfield(mpc.order.dcline, 'status') && ...
        isfield(mpc.order.dcline.status, 'on')
    %% ext2int keeps in-service dcline rows only; map preserved RAW rows
    %% from external row numbers to the current internal dcline row numbers.
    on = mpc.order.dcline.status.on(:);
    dcline_idx = zeros(n, 1);
    [tf, loc] = ismember(state.dcline_idx, on);
    dcline_idx(tf) = loc(tf);
    state.dcline_idx = dcline_idx;
end
state.valid_dcline = state.dcline_idx > 0 & state.dcline_idx <= size(mpc.dcline, 1);

state.mdc = col_default(num, col.mdc, 0);
state.rdc = col_default(num, col.rdc, 0);
state.setvl = col_default(num, col.setvl, 0);
state.vschd = col_default(num, col.vschd, 0);
state.vcmod = col_default(num, col.vcmod, 0);
state.rcomp = col_default(num, col.rcomp, 0);
state.rect_bus = col_default(num, col.ipr, 0);
state.inv_bus = col_default(num, col.ipi, 0);

state.nbr = col_default(num, col.nbr, 1);
state.anmxr = col_default(num, col.anmxr, 0);
state.anmnr = col_default(num, col.anmnr, 0);
state.rcr = col_default(num, col.rcr, 0);
state.xcr = col_default(num, col.xcr, 0);
state.ebasr = col_default(num, col.ebasr, 0);
state.trr = col_default(num, col.trr, 1);
state.tapr = col_default(num, col.tapr, 1);
state.tmxr = col_default(num, col.tmxr, state.tapr);
state.tmnr = col_default(num, col.tmnr, state.tapr);
state.stpr = col_default(num, col.stpr, 0);
state.xcapr = col_default(num, col.xcapr, 0);

state.nbi = col_default(num, col.nbi, 1);
state.anmxi = col_default(num, col.anmxi, 0);
state.anmni = col_default(num, col.anmni, 0);
state.rci = col_default(num, col.rci, 0);
state.xci = col_default(num, col.xci, 0);
state.ebasi = col_default(num, col.ebasi, 0);
state.tri = col_default(num, col.tri, 1);
state.tapi = col_default(num, col.tapi, 1);
state.tmxi = col_default(num, col.tmxi, state.tapi);
state.tmni = col_default(num, col.tmni, state.tapi);
state.stpi = col_default(num, col.stpi, 0);
state.xcapi = col_default(num, col.xcapi, 0);

state.rect_bus_idx = zeros(n, 1);
state.inv_bus_idx = zeros(n, 1);
if isfield(twodc, 'rect_bus_idx')
    state.rect_bus_idx = twodc.rect_bus_idx;
end
if isfield(twodc, 'inv_bus_idx')
    state.inv_bus_idx = twodc.inv_bus_idx;
end
rect_bus_idx = bus_index_from_external(mpc, state.rect_bus);
inv_bus_idx = bus_index_from_external(mpc, state.inv_bus);
state.rect_bus_idx(rect_bus_idx > 0) = rect_bus_idx(rect_bus_idx > 0);
state.inv_bus_idx(inv_bus_idx > 0) = inv_bus_idx(inv_bus_idx > 0);
dcline_internal = isfield(mpc, 'order') && isfield(mpc.order, 'dcline');
if any(state.valid_dcline) && dcline_internal
    idx = find(state.valid_dcline);
    dcidx = state.dcline_idx(idx);
    state.rect_bus_idx(idx) = mpc.dcline(dcidx, c.F_BUS);
    state.inv_bus_idx(idx) = mpc.dcline(dcidx, c.T_BUS);
end

state.active = false(n, 1);
idx = find(state.valid_dcline);
if ~isempty(idx)
    dcidx = state.dcline_idx(idx);
    state.active(idx) = mpc.dcline(dcidx, c.BR_STATUS) > 0 & state.mdc(idx) ~= 0;
end
state.power_mode = state.mdc == 1 & abs(state.setvl) > 0;
state.current_mode = state.mdc == 2 & abs(state.setvl) > 0;
state.supported = state.active & (state.power_mode | state.current_mode) & ...
    state.vschd > 0 & state.rect_bus_idx > 0 & ...
    state.inv_bus_idx > 0 & state.xcapr == 0 & state.xcapi == 0;
state.apply_q = state.supported;
state.apply_model = state.supported;
state.pq_model = false(n, 1);
if isfield(twodc, 'apply_q')
    if isscalar(twodc.apply_q)
        state.apply_q(:) = logical(twodc.apply_q) & state.supported;
    elseif length(twodc.apply_q) == n
        state.apply_q = logical(twodc.apply_q(:)) & state.supported;
    end
end
if isfield(twodc, 'apply_model')
    if isscalar(twodc.apply_model)
        state.apply_model(:) = logical(twodc.apply_model) & state.supported;
    elseif length(twodc.apply_model) == n
        state.apply_model = logical(twodc.apply_model(:)) & state.supported;
    end
end
if isfield(twodc, 'pq_model')
    if isscalar(twodc.pq_model)
        state.pq_model(:) = logical(twodc.pq_model) & state.supported;
    elseif length(twodc.pq_model) == n
        state.pq_model = logical(twodc.pq_model(:)) & state.supported;
    end
end

state.current_pf = zeros(n, 1);
state.current_pt = zeros(n, 1);
state.current_loss = zeros(n, 1);
idx = find(state.valid_dcline);
if ~isempty(idx)
    dcidx = state.dcline_idx(idx);
    state.current_pf(idx) = mpc.dcline(dcidx, c.PF);
    state.current_pt(idx) = mpc.dcline(dcidx, c.PT);
    state.current_loss(idx) = mpc.dcline(dcidx, c.LOSS0) + ...
        mpc.dcline(dcidx, c.LOSS1) .* mpc.dcline(dcidx, c.PF);
end

state.mode = repmat({'blocked'}, n, 1);
state.mode(state.active) = {'power'};
state.mode(state.active & state.mdc == 2) = {'current'};
state.idc_ka = zeros(n, 1);
state.vdcr_kv = zeros(n, 1);
state.vdci_kv = zeros(n, 1);
state.vcomp_kv = zeros(n, 1);
state.qacr_mvar = zeros(n, 1);
state.qaci_mvar = zeros(n, 1);
state.iacr_ka = zeros(n, 1);
state.iaci_ka = zeros(n, 1);
state.mu_r_deg = zeros(n, 1);
state.mu_i_deg = zeros(n, 1);
state.vmr_pu = zeros(n, 1);
state.vmi_pu = zeros(n, 1);
state.tapr_final = state.tapr;
state.tapi_final = state.tapi;
state.tapr_status = repmat({'--'}, n, 1);
state.tapi_status = repmat({'--'}, n, 1);
state.alpha_deg = state.anmnr;
state.gamma_deg = state.anmni;
state.alpha_deg(state.mdc == 0) = 90;
state.gamma_deg(state.mdc == 0) = 90;
state.current_limited = false(n, 1);
state.lcc_valid = false(n, 1);
state.ac_pf_success = 0;
state.ac_pf_status = 'not_run';
state.ac_pf_message = '';

function v = col_default(num, c, default)
if c && size(num, 2) >= c
    v = num(:, c);
else
    if isscalar(default)
        v = default + zeros(size(num, 1), 1);
    else
        v = default;
    end
end
if isscalar(default)
    v(isnan(v)) = default;
else
    idx = isnan(v);
    v(idx) = default(idx);
end

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end

function idx = bus_index_from_external(mpc, bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
idx = zeros(size(bus));
if isfield(mpc, 'order') && isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'e2i') && ~isempty(mpc.order.bus.e2i)
    ok = bus > 0 & bus <= length(mpc.order.bus.e2i);
    if any(ok)
        idx(ok) = full(mpc.order.bus.e2i(bus(ok)));
    end
else
    [tf, loc] = ismember(bus, mpc.bus(:, BUS_I));
    idx(tf) = loc(tf);
end
