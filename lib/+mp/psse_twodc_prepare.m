function mpc = psse_twodc_prepare(mpc)
% psse_twodc_prepare - Prepares PSS/E two-terminal DC as PQ injections.
% ::
%
%   MPC = MP.PSSE_TWODC_PREPARE(MPC)
%
% For PSS/E two-terminal LCC records supported by runpf_psse, disables the
% generic MATPOWER dcline userfcn and applies the DC terminal active power
% as fixed bus injections. This avoids the voltage-controlling PV terminal
% behavior used by toggle_dcline, while preserving MPC.dcline for reporting.
%
% See also runpf_psse, mp.psse_twodc_control, mp.psse_twodc_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'twodc') || ...
        ~isfield(mpc, 'dcline') || isempty(mpc.dcline)
    return;
end

twodc = mpc.psse.twodc;
if ~isfield(twodc, 'num') || isempty(twodc.num) || ~isfield(twodc, 'col')
    return;
end

[~, ~, ~, ~, ~, ~, PD] = idx_bus;
c = idx_dcline;

num = twodc.num;
col = twodc.col;
n = size(num, 1);
dcline_idx = (1:n)';
if isfield(twodc, 'dcline_idx') && length(twodc.dcline_idx) == n
    dcline_idx = twodc.dcline_idx(:);
end
valid = dcline_idx > 0 & dcline_idx <= size(mpc.dcline, 1);

mdc = col_default(num, col, 'mdc', 0);
setvl = col_default(num, col, 'setvl', 0);
vschd = col_default(num, col, 'vschd', 0);
rect_bus = col_default(num, col, 'ipr', 0);
inv_bus = col_default(num, col, 'ipi', 0);
xcapr = col_default(num, col, 'xcapr', 0);
xcapi = col_default(num, col, 'xcapi', 0);

active = false(n, 1);
if any(valid)
    active(valid) = mpc.dcline(dcline_idx(valid), c.BR_STATUS) > 0 & ...
        mdc(valid) ~= 0;
end
supported = active & (mdc == 1 | mdc == 2) & abs(setvl) > 0 & ...
    vschd > 0 & rect_bus > 0 & inv_bus > 0 & xcapr == 0 & xcapi == 0;

twodc.pq_model = false(n, 1);
nb = size(mpc.bus, 1);
prev_p = previous_p_by_bus(mpc, twodc, nb);
if ~any(supported)
    mpc.bus(:, PD) = mpc.bus(:, PD) - prev_p;
    twodc = clear_pq_model(twodc, n);
    mpc.psse.twodc = twodc;
    return;
end

%% Mixed supported/unsupported active rows cannot be represented by the
%% all-or-nothing dcline userfcn switch, so keep legacy dcline behavior.
if any(active & ~supported)
    mpc.bus(:, PD) = mpc.bus(:, PD) - prev_p;
    twodc = clear_pq_model(twodc, n);
    mpc.psse.twodc = twodc;
    return;
end

if toggle_dcline(mpc, 'status')
    mpc = toggle_dcline(mpc, 'off');
end

[p_by_bus, p_rect, p_inv] = current_p_by_bus(mpc, supported, ...
    dcline_idx, rect_bus, inv_bus, nb);
mpc.bus(:, PD) = mpc.bus(:, PD) - prev_p + p_by_bus;

twodc.pq_model = supported;
twodc.p_rect_mw = p_rect;
twodc.p_inv_mw = p_inv;
[twodc.p_bus, twodc.p_bus_mw] = aggregate_by_bus_number( ...
    rect_bus, inv_bus, p_rect, p_inv, supported);
mpc.psse.twodc = twodc;

function v = col_default(num, col, name, default)
if isfield(col, name) && col.(name) && size(num, 2) >= col.(name)
    v = num(:, col.(name));
else
    v = default + zeros(size(num, 1), 1);
end
v(isnan(v)) = default;

function twodc = clear_pq_model(twodc, n)
twodc.pq_model = false(n, 1);
twodc.p_rect_mw = zeros(n, 1);
twodc.p_inv_mw = zeros(n, 1);
twodc.p_bus = zeros(0, 1);
twodc.p_bus_mw = zeros(0, 1);

function p = previous_p_by_bus(mpc, twodc, nb)
p = zeros(nb, 1);
if ~isfield(twodc, 'pq_model') || ~isfield(twodc, 'p_rect_mw') || ...
        ~isfield(twodc, 'p_inv_mw') || ...
        length(twodc.pq_model) ~= size(twodc.num, 1) || ...
        length(twodc.p_rect_mw) ~= size(twodc.num, 1) || ...
        length(twodc.p_inv_mw) ~= size(twodc.num, 1)
    return;
end
mask = logical(twodc.pq_model(:));
rect_idx = bus_rows(mpc, col_default(twodc.num, twodc.col, 'ipr', 0));
inv_idx = bus_rows(mpc, col_default(twodc.num, twodc.col, 'ipi', 0));
p = accum_p(rect_idx, twodc.p_rect_mw(:) .* mask, nb) + ...
    accum_p(inv_idx, twodc.p_inv_mw(:) .* mask, nb);

function [p, p_rect, p_inv] = current_p_by_bus(mpc, mask, dcline_idx, ...
        rect_bus, inv_bus, nb)
c = idx_dcline;
p_rect = zeros(size(mask));
p_inv = zeros(size(mask));
idx = find(mask);
if ~isempty(idx)
    dcidx = dcline_idx(idx);
    p_rect(idx) = mpc.dcline(dcidx, c.PF);
    p_inv(idx) = -mpc.dcline(dcidx, c.PT);
end
rect_idx = bus_rows(mpc, rect_bus);
inv_idx = bus_rows(mpc, inv_bus);
p = accum_p(rect_idx, p_rect, nb) + accum_p(inv_idx, p_inv, nb);

function idx = bus_rows(mpc, bus_ext)
[~, ~, ~, ~, BUS_I] = idx_bus;
idx = zeros(size(bus_ext));
[tf, loc] = ismember(bus_ext, mpc.bus(:, BUS_I));
idx(tf) = loc(tf);

function p = accum_p(bus_idx, pdc, nb)
idx = find(bus_idx > 0 & bus_idx <= nb & abs(pdc) > 0);
if isempty(idx)
    p = zeros(nb, 1);
else
    p = accumarray(bus_idx(idx), pdc(idx), [nb 1], @sum, 0);
end

function [bus, p] = aggregate_by_bus_number(rect_bus, inv_bus, ...
        p_rect, p_inv, mask)
bus_all = [rect_bus(:); inv_bus(:)];
p_all = [p_rect(:); p_inv(:)];
mask_all = [mask(:); mask(:)] & bus_all > 0 & abs(p_all) > 0;
if ~any(mask_all)
    bus = zeros(0, 1);
    p = zeros(0, 1);
else
    [bus, ~, grp] = unique(bus_all(mask_all));
    p = accumarray(grp, p_all(mask_all), [], @sum, 0);
end
