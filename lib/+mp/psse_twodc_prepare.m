function mpc = psse_twodc_prepare(mpc, mpopt)
% psse_twodc_prepare - Prepares PSS/E two-terminal DC as PQ injections.
% ::
%
%   MPC = MP.PSSE_TWODC_PREPARE(MPC)
%   MPC = MP.PSSE_TWODC_PREPARE(MPC, MPOPT)
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

if nargin < 2 || isempty(mpopt)
    mpopt = mpoption;
end

if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'twodc') || ...
        ~isfield(mpc, 'dcline') || isempty(mpc.dcline)
    return;
end

twodc = mpc.psse.twodc;
mpc0 = mpc;
if ~isfield(twodc, 'num') || isempty(twodc.num) || ~isfield(twodc, 'col')
    return;
end

[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
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
prev_q = previous_q_by_bus(mpc, twodc, nb);
if ~any(supported)
    mpc.bus(:, PD) = mpc.bus(:, PD) - prev_p;
    mpc.bus(:, QD) = mpc.bus(:, QD) - prev_q;
    twodc = clear_pq_model(twodc, n);
    mpc.psse.twodc = twodc;
    return;
end

%% Mixed supported/unsupported active rows cannot be represented by the
%% all-or-nothing dcline userfcn switch, so keep legacy dcline behavior.
if any(active & ~supported)
    mpc.bus(:, PD) = mpc.bus(:, PD) - prev_p;
    mpc.bus(:, QD) = mpc.bus(:, QD) - prev_q;
    twodc = clear_pq_model(twodc, n);
    mpc.psse.twodc = twodc;
    return;
end

if toggle_dcline(mpc, 'status')
    mpc = toggle_dcline(mpc, 'off');
end

[p_by_bus, p_rect, p_inv] = current_p_by_bus(mpc, supported, ...
    dcline_idx, rect_bus, inv_bus, nb);
[q_by_bus, q_rect, q_inv, q_valid] = initial_q_by_bus(mpc, ...
    supported, num, col, rect_bus, inv_bus, nb);
mpc.bus(:, PD) = mpc.bus(:, PD) - prev_p + p_by_bus;
mpc.bus(:, QD) = mpc.bus(:, QD) - prev_q + q_by_bus;

twodc.pq_model = supported;
twodc.p_rect_mw = p_rect;
twodc.p_inv_mw = p_inv;
twodc.apply_q = q_valid;
twodc.qacr_mvar = q_rect;
twodc.qaci_mvar = q_inv;
twodc.prepare_mode = 'pq';
twodc.prepare_deferred = 0;
twodc.initial_blocked = false(n, 1);
[twodc.p_bus, twodc.p_bus_mw] = aggregate_by_bus_number( ...
    rect_bus, inv_bus, p_rect, p_inv, supported);
[twodc.q_bus, twodc.q_bus_mvar] = aggregate_by_bus_number( ...
    rect_bus, inv_bus, q_rect, q_inv, q_valid);
mpc.psse.twodc = twodc;
if ~mp.psse_twodc_probe_pq_model(mpc, mpopt)
    twodc = clear_pq_model(twodc, n);
    twodc.pq_model = supported;
    twodc.apply_model = supported;
    twodc.apply_q = supported;
    twodc.p_rect_mw = zeros(n, 1);
    twodc.p_inv_mw = zeros(n, 1);
    twodc.qacr_mvar = zeros(n, 1);
    twodc.qaci_mvar = zeros(n, 1);
    twodc.prepare_mode = 'deferred_pq';
    twodc.prepare_deferred = 1;
    twodc.initial_blocked = false(n, 1);
    twodc.pq_model_deferred = 1;
    twodc.pq_model_defer_reason = 'initial_pq_power_flow_failed';
    mpc = mpc0;
    if toggle_dcline(mpc, 'status')
        mpc = toggle_dcline(mpc, 'off');
    end
    dcidx = dcline_idx(supported & valid);
    if ~isempty(dcidx)
        mpc.dcline(dcidx, [c.PF c.PT c.LOSS0 c.LOSS1]) = 0;
    end
    mpc.psse.twodc = twodc;
end

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
twodc.apply_q = false(n, 1);
twodc.qacr_mvar = zeros(n, 1);
twodc.qaci_mvar = zeros(n, 1);
twodc.q_bus = zeros(0, 1);
twodc.q_bus_mvar = zeros(0, 1);
twodc.initial_blocked = false(n, 1);

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

function q = previous_q_by_bus(mpc, twodc, nb)
q = zeros(nb, 1);
if ~isfield(twodc, 'qacr_mvar') || ~isfield(twodc, 'qaci_mvar') || ...
        length(twodc.qacr_mvar) ~= size(twodc.num, 1) || ...
        length(twodc.qaci_mvar) ~= size(twodc.num, 1)
    return;
end
mask = true(size(twodc.num, 1), 1);
if isfield(twodc, 'apply_q') && length(twodc.apply_q) == size(twodc.num, 1)
    mask = logical(twodc.apply_q(:));
end
rect_idx = bus_rows(mpc, col_default(twodc.num, twodc.col, 'ipr', 0));
inv_idx = bus_rows(mpc, col_default(twodc.num, twodc.col, 'ipi', 0));
q = accum_p(rect_idx, twodc.qacr_mvar(:) .* mask, nb) + ...
    accum_p(inv_idx, twodc.qaci_mvar(:) .* mask, nb);

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

function [q, q_rect, q_inv, q_valid] = initial_q_by_bus(mpc, mask, ...
        num, col, rect_bus, inv_bus, nb)
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
q_rect = zeros(size(mask));
q_inv = zeros(size(mask));
q_valid = false(size(mask));
rect_idx = bus_rows(mpc, rect_bus);
inv_idx = bus_rows(mpc, inv_bus);
idx = find(mask);
for kk = 1:length(idx)
    k = idx(kk);
    rb = rect_idx(k);
    ib = inv_idx(k);
    if rb <= 0 || rb > size(mpc.bus, 1) || ib <= 0 || ib > size(mpc.bus, 1)
        continue;
    end
    op = initial_lcc_op(num(k, :), col, mpc.bus(rb, VM), mpc.bus(ib, VM));
    if ~op.valid
        continue;
    end
    q_rect(k) = op.qacr;
    q_inv(k) = op.qaci;
    q_valid(k) = true;
end
q = accum_p(rect_idx, q_rect .* q_valid, nb) + ...
    accum_p(inv_idx, q_inv .* q_valid, nb);

function op = initial_lcc_op(row, col, vmr, vmi)
mdc = field_value(row, col, 'mdc', 0);
if mdc == 2
    op = solve_current_mode(row, col, vmr, vmi, 0);
elseif mdc == 1
    op = solve_power_mode(row, col, vmr, vmi);
    vcmod = field_value(row, col, 'vcmod', 0);
    if ~op.valid || (vcmod > 0 && op.vdci < vcmod)
        op = solve_current_mode(row, col, vmr, vmi, 1);
    end
else
    op = default_op();
end

function op = solve_power_mode(row, col, vmr, vmi)
op = default_op();
p_set = abs(field_value(row, col, 'setvl', 0));
target_inverter = field_value(row, col, 'setvl', 0) < 0;
if p_set <= 0
    return;
end
gamma = field_value(row, col, 'anmni', 0);
tapi_grid = tap_grid(field_value(row, col, 'tmni', 0), ...
    field_value(row, col, 'tmxi', 0), field_value(row, col, 'stpi', 0), ...
    field_value(row, col, 'tapi', 1), true);

best_score = [];
for ii = 1:length(tapi_grid)
    tapi = tapi_grid(ii);
    eaci = converter_eac(field_value(row, col, 'ebasi', 0), vmi, ...
        field_value(row, col, 'tri', 1), tapi);
    if eaci <= 0
        continue;
    end
    roots_idc = power_mode_currents(row, col, p_set, eaci, gamma, ...
        target_inverter);
    for rr = 1:length(roots_idc)
        idc = roots_idc(rr);
        vdci = inverter_voltage(row, col, eaci, gamma, idc);
        vdcr = vdci + field_value(row, col, 'rdc', 0) * idc;
        if vdci <= 0 || vdcr <= 0
            continue;
        end
        [tapr, alpha, ok] = select_rectifier_tap(row, col, vmr, vdcr, idc);
        if ~ok
            continue;
        end
        eacr = converter_eac(field_value(row, col, 'ebasr', 0), vmr, ...
            field_value(row, col, 'trr', 1), tapr);
        lcc = lcc_quantities(row, col, eacr, eaci, alpha, gamma, ...
            tapr, tapi, idc, vdcr, vdci, 0);
        vschd = field_value(row, col, 'vschd', 0);
        score = [abs(lcc.vcomp - vschd) ...
            abs(alpha - max(field_value(row, col, 'anmnr', 0), ...
                field_value(row, col, 'anmxr', 0))) ...
            abs(tapi - field_value(row, col, 'tapi', 1))];
        if isempty(best_score) || lex_lt(score, best_score)
            best_score = score;
            op = lcc;
            if target_inverter
                op.pt = p_set;
                op.pf = vdcr * idc;
            else
                op.pf = p_set;
                op.pt = vdci * idc;
            end
            op.loss = op.pf - op.pt;
            op.valid = true;
        end
    end
end

function op = solve_current_mode(row, col, vmr, vmi, current_limited)
if nargin < 5
    current_limited = 1;
end
op = default_op();
setvl = abs(field_value(row, col, 'setvl', 0));
if field_value(row, col, 'mdc', 0) == 2
    idc = setvl / 1000;
else
    vschd = field_value(row, col, 'vschd', 0);
    if vschd <= 0
        return;
    end
    idc = setvl / vschd;
end
if idc <= 0
    return;
end

gamma = field_value(row, col, 'anmni', 0);
tapi = field_value(row, col, 'tapi', 1);
if field_value(row, col, 'tmni', 0) > 0
    tapi = field_value(row, col, 'tmni', tapi);
end
eaci = converter_eac(field_value(row, col, 'ebasi', 0), vmi, ...
    field_value(row, col, 'tri', 1), tapi);
vdci = inverter_voltage(row, col, eaci, gamma, idc);
vdcr = vdci + field_value(row, col, 'rdc', 0) * idc;
[tapr, alpha, ok] = select_rectifier_tap(row, col, vmr, vdcr, idc);
if ~ok
    alpha = min(max(field_value(row, col, 'anmnr', 0), 0), ...
        max(field_value(row, col, 'anmxr', 0), field_value(row, col, 'anmnr', 0)));
end
eacr = converter_eac(field_value(row, col, 'ebasr', 0), vmr, ...
    field_value(row, col, 'trr', 1), tapr);
op = lcc_quantities(row, col, eacr, eaci, alpha, gamma, tapr, tapi, ...
    idc, vdcr, vdci, current_limited);
op.pf = vdcr * idc;
op.pt = vdci * idc;
op.loss = field_value(row, col, 'rdc', 0) * idc ^ 2;
op.valid = vdci >= 0 && vdcr >= 0;

function idc = power_mode_currents(row, col, p_set, eaci, gamma, target_inverter)
nbi = field_value(row, col, 'nbi', 1);
xci = field_value(row, col, 'xci', 0);
rci = field_value(row, col, 'rci', 0);
rdc = field_value(row, col, 'rdc', 0);
a = nbi * (3 * sqrt(2) / pi) * eaci * cosd(gamma);
b = nbi * ((3 * xci) / pi + 2 * rci);
if target_inverter
    if abs(b) < 1e-12
        roots_idc = p_set / a;
    else
        roots_idc = roots([-b a -p_set]);
    end
else
    c = rdc - b;
    if abs(c) < 1e-12
        roots_idc = p_set / a;
    else
        roots_idc = roots([c a -p_set]);
    end
end
idc = sort(real(roots_idc(abs(imag(roots_idc)) < 1e-9 & ...
    real(roots_idc) > 0)));
if ~isempty(idc)
    vdci = a - b .* idc;
    vdcr = vdci + rdc .* idc;
    idc = idc(vdci > 0 & vdcr > 0);
end

function vdci = inverter_voltage(row, col, eac, gamma, idc)
vdci = field_value(row, col, 'nbi', 1) * ((3 * sqrt(2) / pi) * ...
    eac * cosd(gamma) - (3 * field_value(row, col, 'xci', 0) * idc) / pi - ...
    2 * field_value(row, col, 'rci', 0) * idc);

function [tapr, alpha, ok] = select_rectifier_tap(row, col, vmr, vdcr, idc)
tapr_grid = tap_grid(field_value(row, col, 'tmnr', 0), ...
    field_value(row, col, 'tmxr', 0), field_value(row, col, 'stpr', 0), ...
    field_value(row, col, 'tapr', 1), true);
angle_fn = @(t) rectifier_alpha(row, col, ...
    converter_eac(field_value(row, col, 'ebasr', 0), vmr, ...
    field_value(row, col, 'trr', 1), t), vdcr, idc);
[tapr, alpha, ok] = select_tap_by_angle(tapr_grid, ...
    field_value(row, col, 'tapr', 1), field_value(row, col, 'anmnr', 0), ...
    field_value(row, col, 'anmxr', 0), angle_fn);

function alpha = rectifier_alpha(row, col, eac, vdcr, idc)
alpha = NaN;
nbr = field_value(row, col, 'nbr', 1);
if eac <= 0 || nbr <= 0
    return;
end
ca = (vdcr / nbr + (3 * field_value(row, col, 'xcr', 0) * idc) / pi + ...
    2 * field_value(row, col, 'rcr', 0) * idc) / ((3 * sqrt(2) / pi) * eac);
if ca >= -1 && ca <= 1
    alpha = acosd(ca);
end

function op = lcc_quantities(row, col, eacr, eaci, alpha, gamma, tapr, ...
        tapi, idc, vdcr, vdci, current_limited)
op = default_op();
op.valid = true;
op.current_limited = current_limited;
op.idc = idc;
op.vdcr = vdcr;
op.vdci = vdci;
op.vcomp = vdci + field_value(row, col, 'rcomp', 0) * idc;
op.tapr = tapr;
op.tapi = tapi;
op.alpha = alpha;
op.gamma = gamma;
mu_r = overlap_angle(alpha, idc, field_value(row, col, 'xcr', 0), eacr);
mu_i = overlap_angle(gamma, idc, field_value(row, col, 'xci', 0), eaci);
op.qacr = converter_q(vdcr * idc, alpha, mu_r);
op.qaci = converter_q(vdci * idc, gamma, mu_i);

function mu = overlap_angle(angle, idc, xc, eac)
mu = 0;
if eac <= 0
    return;
end
arg = cosd(angle) - sqrt(2) * idc * xc / eac;
mu = acosd(clamp(arg, -1, 1)) - angle;
mu = max(mu, 0);

function q = converter_q(p, angle, mu)
a = deg2rad(angle);
m = deg2rad(mu);
den = cos(2 * a) - cos(2 * (a + m));
if abs(den) < 1e-12
    cosphi = 0.5 * (cosd(angle) + cosd(angle + mu));
    q = abs(p) * tand(acosd(clamp(cosphi, -1, 1)));
else
    tanphi = (2 * m + sin(2 * a) - sin(2 * (a + m))) / den;
    q = abs(p) * abs(tanphi);
end

function eac = converter_eac(ebase, vm, tr, tap)
if tap <= 0 || isnan(tap)
    tap = 1;
end
if tr <= 0 || isnan(tr)
    tr = 1;
end
eac = ebase * vm * tr / tap;

function taps = tap_grid(tmin, tmax, step, nominal, enabled)
if ~enabled || step <= 0 || isnan(step) || tmin <= 0 || tmax <= 0
    taps = nominal;
    if taps <= 0 || isnan(taps)
        taps = 1;
    end
    return;
end
lo = min(tmin, tmax);
hi = max(tmin, tmax);
n = max(round((hi - lo) / step), 0);
taps = lo + (0:n)' * step;
taps = taps(taps >= lo - 1e-9 & taps <= hi + 1e-9);
taps = unique([taps; lo; hi; nominal]);
taps = taps(taps > 0 & taps >= lo - 1e-9 & taps <= hi + 1e-9);
if isempty(taps)
    taps = 1;
end

function [tap, angle, ok] = select_tap_by_angle(taps, nominal, amin, amax, angle_fn)
tol = 1e-9;
amin = min(amin, amax);
amax = max(amin, amax);
taps = sort(unique(taps(:)));
if nominal <= 0 || isnan(nominal)
    nominal = taps(1);
end
cur = nearest_value(taps, nominal);
cur_angle = angle_fn(cur);
if isfinite(cur_angle) && cur_angle >= amin - tol && cur_angle <= amax + tol
    tap = cur;
    angle = cur_angle;
    ok = true;
    return;
end
angles = nan(size(taps));
for ii = 1:length(taps)
    angles(ii) = angle_fn(taps(ii));
end
inside = find(isfinite(angles) & angles >= amin - tol & angles <= amax + tol);
if ~isempty(inside)
    [~, jj] = min(abs(taps(inside) - nominal));
    tap = taps(inside(jj));
    angle = angles(inside(jj));
    ok = true;
    return;
end
[~, jj] = min(abs(angles - amax));
tap = taps(jj);
angle = angles(jj);
ok = isfinite(angle);

function val = nearest_value(values, target)
[~, idx] = min(abs(values - target));
val = values(idx);

function TorF = lex_lt(a, b)
TorF = false;
for ii = 1:numel(a)
    if a(ii) < b(ii) - 1e-12
        TorF = true;
        return;
    elseif a(ii) > b(ii) + 1e-12
        return;
    end
end

function x = clamp(x, xmin, xmax)
x = min(max(x, xmin), xmax);

function v = field_value(row, col, name, default)
if isfield(col, name) && col.(name) && numel(row) >= col.(name)
    v = row(col.(name));
    if isnan(v)
        v = default;
    end
else
    v = default;
end

function op = default_op()
op = struct('valid', false, 'current_limited', false, 'pf', 0, 'pt', 0, ...
    'loss', 0, 'qacr', 0, 'qaci', 0, 'idc', 0, 'vdcr', 0, ...
    'vdci', 0, 'vcomp', 0, 'tapr', 1, 'tapi', 1, ...
    'alpha', 0, 'gamma', 0);

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
