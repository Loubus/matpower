function [dm_next, state] = psse_twodc_control(task, ~, nm, dm, mpopt, mpx, state)
% psse_twodc_control - Executes PSS/E two-terminal DC control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_TWODC_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Applies the opt-in PSS/E two-terminal LCC model for preserved
% ``MDC = 1`` and ``MDC = 2`` records. The control uses solved AC bus voltages to compute
% non-capacitor-commutated converter voltages, current, losses, and reactive
% demand, then updates the MATPOWER ``dcline`` equivalent.
%
% See also mp.task_pf_psse, mp.psse_twodc_states, mp.psse_twodc_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

dm_next = [];
if nargin < 7
    state = [];
end

%% no preserved PSS/E two-terminal DC metadata, no PSS/E DC control
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'twodc') || ...
        isempty(dm.source.psse.twodc.num) || ~isfield(dm.source, 'dcline')
    state = [];
    return;
end

%% initialize control state from preserved RAW metadata
if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = mp.psse_twodc_states(dm.source);
end

%% keep reporting synchronized even when DC control is disabled
if ~state.enabled || ~any(state.supported)
    dm.source = mp.psse_twodc_update(dm.source, state);
    return;
end

%% stop after the PSS/E tap/shunt adjustment iteration limit
state.iterations = state.iterations + 1;
if state.iterations > state.max_iter
    state.max_iter_reached = 1;
    state.changed_last = 0;
    dm.source = mp.psse_twodc_update(dm.source, state);
    return;
end

bus = dm.elements.bus;
vm = bus.tab.vm;
if ~isempty(nm) && isobject(nm) && isprop(nm, 'soln') && ...
        isfield(nm.soln, 'v') && ...
        length(nm.soln.v) == length(vm)
    vm = abs(nm.soln.v);
end
[vm, state] = estimate_ac_vm(dm.source, state, vm, mpopt);
state = solve_lcc(state, vm);

ctrl_tol = 1e-8;
q_changed = state.apply_q & (abs(state.next_qacr - state.qacr_mvar) > ctrl_tol | ...
    abs(state.next_qaci - state.qaci_mvar) > ctrl_tol);
changed = any(abs(state.next_pf - state.current_pf) > ctrl_tol | ...
    abs(state.next_pt - state.current_pt) > ctrl_tol | ...
    q_changed);
if changed
    prev_pf = state.current_pf;
    prev_pt = state.current_pt;
    prev_qacr = state.qacr_mvar;
    prev_qaci = state.qaci_mvar;
    state.current_pf = state.next_pf;
    state.current_pt = state.next_pt;
    state.current_loss = state.next_loss;
    state.qacr_mvar = state.next_qacr;
    state.qaci_mvar = state.next_qaci;
    state.changed_last = nnz(abs(state.current_pf - prev_pf) > ctrl_tol | ...
        abs(state.current_pt - prev_pt) > ctrl_tol | ...
        (state.apply_q & (abs(state.qacr_mvar - prev_qacr) > ctrl_tol | ...
        abs(state.qaci_mvar - prev_qaci) > ctrl_tol)));
    state.num_adjustments = state.num_adjustments + state.changed_last;
    mpc = mp.psse_twodc_update(dm.source, state);
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    state.qacr_mvar = state.next_qacr;
    state.qaci_mvar = state.next_qaci;
    state.changed_last = 0;
    dm.source = mp.psse_twodc_update(dm.source, state);
end

function [vm, state] = estimate_ac_vm(mpc, state, vm, mpopt)
% Compute converter-bus AC voltages with DC terminals as PQ injections.
[PQ, ~, REF, ~, ~, BUS_TYPE, PD, ~] = idx_bus;
c = idx_dcline;

state.ac_pf_success = 0;
state.ac_pf_status = 'not_run';
state.ac_pf_message = '';
idx = find(state.valid_dcline & state.active);
if isempty(idx)
    return;
end

state.ac_pf_status = 'fallback';
try
    mpc_aux = mpc;
    original_ng = [];
    if isfield(mpc_aux, 'order')
        if isfield(mpc_aux.order, 'ext') && isfield(mpc_aux.order.ext, 'gen')
            original_ng = size(mpc_aux.order.ext.gen, 1);
        end
        mpc_aux = rmfield(mpc_aux, 'order');
    end

    dcidx = state.dcline_idx(idx);
    if isfield(mpc_aux, 'gen') && ~isempty(mpc_aux.gen)
        if ~isempty(original_ng) && size(mpc_aux.gen, 1) > original_ng
            keep = true(size(mpc_aux.gen, 1), 1);
            keep(original_ng+1:end) = false;
        else
            [GEN_BUS, PG, ~, ~, ~, ~, ~, ~, PMAX, PMIN] = idx_gen;
            term_bus = unique([state.rect_bus_idx(idx); state.inv_bus_idx(idx)]);
            keep = ~(ismember(mpc_aux.gen(:, GEN_BUS), term_bus) & ...
                mpc_aux.gen(:, PG) ~= 0 & mpc_aux.gen(:, PMIN) <= 0 & ...
                mpc_aux.gen(:, PMAX) <= 0);
        end
        if any(~keep)
            mpc_aux.gen = mpc_aux.gen(keep, :);
            if isfield(mpc_aux, 'gencost') && ...
                    size(mpc_aux.gencost, 1) == length(keep)
                mpc_aux.gencost = mpc_aux.gencost(keep, :);
            end
        end
    end
    mpc_aux.dcline(dcidx, c.BR_STATUS) = 0;
    for kk = 1:length(idx)
        k = idx(kk);
        rb = state.rect_bus_idx(k);
        ib = state.inv_bus_idx(k);
        if rb <= 0 || rb > size(mpc_aux.bus, 1) || ...
                ib <= 0 || ib > size(mpc_aux.bus, 1)
            continue;
        end
        if ~isfield(state, 'pq_model') || ~state.pq_model(k)
            mpc_aux.bus(rb, PD) = mpc_aux.bus(rb, PD) + state.current_pf(k);
            mpc_aux.bus(ib, PD) = mpc_aux.bus(ib, PD) - state.current_pt(k);
        end
        if mpc_aux.bus(rb, BUS_TYPE) ~= REF
            mpc_aux.bus(rb, BUS_TYPE) = PQ;
        end
        if mpc_aux.bus(ib, BUS_TYPE) ~= REF
            mpc_aux.bus(ib, BUS_TYPE) = PQ;
        end
    end

    auxopt = mpoption(mpopt, 'verbose', 0, 'out.all', 0);
    r = runpf(mpc_aux, auxopt);
    if isstruct(r) && isfield(r, 'success') && r.success && ...
            size(r.bus, 1) == length(vm)
        [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
        vm = r.bus(:, VM);
        state.ac_pf_success = 1;
        state.ac_pf_status = 'success';
    end
catch err
    %% Keep the solved MATPOWER voltages when the auxiliary PQ solve is not
    %% available, e.g. for islands that require the active dcline model.
    state.ac_pf_status = 'error';
    state.ac_pf_message = err.message;
end

function state = solve_lcc(state, vm)
% Compute LCC operating points from solved AC voltages.
state.next_pf = state.current_pf;
state.next_pt = state.current_pt;
state.next_loss = state.current_loss;
state.next_qacr = state.qacr_mvar;
state.next_qaci = state.qaci_mvar;
state.current_limited(:) = false;
state.lcc_valid(:) = false;
state.mode(state.active) = {'power'};
state.tapr_status(:) = {'--'};
state.tapi_status(:) = {'--'};

idx = find(state.supported);
for kk = 1:length(idx)
    k = idx(kk);
    rb = state.rect_bus_idx(k);
    ib = state.inv_bus_idx(k);
    if rb <= 0 || rb > length(vm) || ib <= 0 || ib > length(vm)
        continue;
    end

    vmr = vm(rb);
    vmi = vm(ib);
    if state.mdc(k) == 2
        op = solve_current_mode(state, k, vmr, vmi, 0);
    else
        op = solve_power_mode(state, k, vmr, vmi);
        if ~op.valid || (state.vcmod(k) > 0 && op.vdci < state.vcmod(k))
            op = solve_current_mode(state, k, vmr, vmi, 1);
            op.current_limited = op.valid;
        end
    end
    if ~op.valid
        continue;
    end

    if state.apply_model(k)
        state.next_pf(k) = op.pf;
        state.next_pt(k) = op.pt;
        state.next_loss(k) = op.loss;
    end
    state.next_qacr(k) = op.qacr;
    state.next_qaci(k) = op.qaci;
    state.idc_ka(k) = op.idc;
    state.vdcr_kv(k) = op.vdcr;
    state.vdci_kv(k) = op.vdci;
    state.vcomp_kv(k) = op.vcomp;
    state.iacr_ka(k) = op.iacr;
    state.iaci_ka(k) = op.iaci;
    state.mu_r_deg(k) = op.mu_r;
    state.mu_i_deg(k) = op.mu_i;
    state.vmr_pu(k) = vmr;
    state.vmi_pu(k) = vmi;
    state.tapr_final(k) = op.tapr;
    state.tapi_final(k) = op.tapi;
    state.tapr_status{k} = op.tapr_status;
    state.tapi_status{k} = op.tapi_status;
    state.alpha_deg(k) = op.alpha;
    state.gamma_deg(k) = op.gamma;
    state.current_limited(k) = op.current_limited;
    state.lcc_valid(k) = true;
    if op.current_limited || state.mdc(k) == 2
        state.mode{k} = 'current';
    else
        state.mode{k} = 'power';
    end
end

function op = solve_power_mode(state, k, vmr, vmi)
% Solve a power-control LCC point using tap candidates and firing limits.
op = default_op();
p_set = abs(state.setvl(k));
target_inverter = state.setvl(k) < 0;
if p_set <= 0
    return;
end

gamma = state.anmni(k);
tapi_grid = tap_grid(state.tmni(k), state.tmxi(k), state.stpi(k), ...
    state.tapi(k), state.dctaps_enabled);

best_score = [];
for ii = 1:length(tapi_grid)
    tapi = tapi_grid(ii);
    eaci = converter_eac(state.ebasi(k), vmi, state.tri(k), tapi);
    if eaci <= 0
        continue;
    end
    roots_idc = power_mode_currents(state, k, p_set, eaci, gamma, ...
        target_inverter);
    for rr = 1:length(roots_idc)
        idc = roots_idc(rr);
        vdci = inverter_voltage(state, k, eaci, gamma, idc);
        vdcr = vdci + state.rdc(k) * idc;
        if vdci <= 0 || vdcr <= 0
            continue;
        end
        [tapr, alpha, tapr_status, ok] = select_rectifier_tap( ...
            state, k, vmr, vdcr, idc);
        if ~ok
            continue;
        end
        eacr = converter_eac(state.ebasr(k), vmr, state.trr(k), tapr);
        lcc = lcc_quantities(state, k, eacr, eaci, alpha, gamma, ...
            tapr, tapi, idc, vdcr, vdci, 0);
        v_over = max(lcc.vcomp - state.vschd(k), 0);
        tapi_status = inverter_tap_status(tapi, tapi_grid, ...
            lcc.vcomp - state.vschd(k));
        score = [10 * v_over + abs(lcc.vcomp - state.vschd(k)) ...
            abs(lcc.vcomp - state.vschd(k)) ...
            abs(alpha - max(state.anmnr(k), state.anmxr(k))) ...
            abs(tapi - state.tapi(k))];
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
            op.tapr_status = tapr_status;
            op.tapi_status = tapi_status;
            op.valid = true;
        end
    end
end

function op = solve_current_mode(state, k, vmr, vmi, current_limited)
% Solve explicit current control or the VCMOD current-control fallback.
if nargin < 5
    current_limited = 1;
end
op = default_op();
if state.mdc(k) == 2
    idc = abs(state.setvl(k)) / 1000;      %% kA = A / 1000
else
    idc = abs(state.setvl(k)) / state.vschd(k); %% kA = MW / kV
end
if idc <= 0
    return;
end

gamma = state.anmni(k);
tapi = state.tapi(k);
tapi_status = 'RG';
if state.dctaps_enabled && state.tmni(k) > 0
    tapi = state.tmni(k);                  %% low-voltage current mode
    tapi_status = limit_status(tapi, state.tmni(k), state.tmxi(k));
end
eaci = converter_eac(state.ebasi(k), vmi, state.tri(k), tapi);
vdci = inverter_voltage(state, k, eaci, gamma, idc);
vdcr = vdci + state.rdc(k) * idc;

[tapr, alpha, tapr_status, ok] = select_rectifier_tap(state, k, vmr, vdcr, idc);
eacr = converter_eac(state.ebasr(k), vmr, state.trr(k), tapr);
if ~ok
    alpha = min(max(state.anmnr(k), 0), max(state.anmxr(k), state.anmnr(k)));
    tapr_status = limit_status(tapr, state.tmnr(k), state.tmxr(k));
end

op = lcc_quantities(state, k, eacr, eaci, alpha, gamma, tapr, tapi, ...
    idc, vdcr, vdci, current_limited);
op.pf = vdcr * idc;
op.pt = vdci * idc;
op.loss = state.rdc(k) * idc^2;
op.tapr_status = tapr_status;
op.tapi_status = tapi_status;
op.valid = vdci >= 0 && vdcr >= 0;

function idc = power_mode_currents(state, k, p_set, eaci, gamma, target_inverter)
% Return physically meaningful positive current roots for the active-power target.
if nargin < 6
    target_inverter = false;
end
a = state.nbi(k) * (3 * sqrt(2) / pi) * eaci * cosd(gamma);
b = state.nbi(k) * ((3 * state.xci(k)) / pi + 2 * state.rci(k));
if target_inverter
    if abs(b) < 1e-12
        roots_idc = p_set / a;
    else
        roots_idc = roots([-b a -p_set]);
    end
else
    c = state.rdc(k) - b;
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
    vdcr = vdci + state.rdc(k) .* idc;
    idc = idc(vdci > 0 & vdcr > 0);
end

function vdci = inverter_voltage(state, k, eac, gamma, idc)
% Compute non-capacitor-commutated inverter DC voltage in kV.
vdci = state.nbi(k) * ((3 * sqrt(2) / pi) * eac * cosd(gamma) - ...
    (3 * state.xci(k) * idc) / pi - 2 * state.rci(k) * idc);

function alpha = rectifier_alpha_raw(state, k, eac, vdcr, idc)
% Compute rectifier alpha without enforcing the PSS/E angle band.
alpha = NaN;
if eac <= 0 || state.nbr(k) <= 0
    return;
end
ca = (vdcr / state.nbr(k) + (3 * state.xcr(k) * idc) / pi + ...
    2 * state.rcr(k) * idc) / ((3 * sqrt(2) / pi) * eac);
if ca < -1 || ca > 1
    return;
end
alpha = acosd(ca);

function [tapr, alpha, status, ok] = select_rectifier_tap(state, k, vmr, vdcr, idc)
% Select a rectifier tap using PSS/E discrete angle targeting.
tapr_grid = tap_grid(state.tmnr(k), state.tmxr(k), state.stpr(k), ...
    state.tapr(k), state.dctaps_enabled);
angle_fn = @(t) rectifier_alpha_raw(state, k, ...
    converter_eac(state.ebasr(k), vmr, state.trr(k), t), vdcr, idc);
[tapr, alpha, status, ok] = select_tap_by_angle( ...
    tapr_grid, state.tapr(k), state.anmnr(k), state.anmxr(k), angle_fn);

function op = lcc_quantities(state, k, eacr, eaci, alpha, gamma, tapr, ...
        tapi, idc, vdcr, vdci, current_limited)
% Build a complete operating point and reactive-power estimate.
op = default_op();
op.valid = true;
op.current_limited = current_limited;
op.idc = idc;
op.vdcr = vdcr;
op.vdci = vdci;
op.vcomp = vdci + state.rcomp(k) * idc;
op.tapr = tapr;
op.tapi = tapi;
op.alpha = alpha;
op.gamma = gamma;
op.iacr = sqrt(6) * state.nbr(k) / pi * idc;
op.iaci = sqrt(6) * state.nbi(k) / pi * idc;
op.mu_r = overlap_angle(alpha, idc, state.xcr(k), eacr);
op.mu_i = overlap_angle(gamma, idc, state.xci(k), eaci);
op.qacr = converter_q(vdcr * idc, alpha, op.mu_r);
op.qaci = converter_q(vdci * idc, gamma, op.mu_i);

function mu = overlap_angle(angle, idc, xc, eac)
% Compute commutation overlap angle in degrees.
mu = 0;
if eac <= 0
    return;
end
arg = cosd(angle) - sqrt(2) * idc * xc / eac;
mu = acosd(clamp(arg, -1, 1)) - angle;
mu = max(mu, 0);

function q = converter_q(p, angle, mu)
% Compute LCC reactive consumption from the PAGV1 overlap expression.
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
% Convert bus voltage, converter transformer ratio, and tap to kV.
if tap <= 0 || isnan(tap)
    tap = 1;
end
if tr <= 0 || isnan(tr)
    tr = 1;
end
eac = ebase * vm * tr / tap;

function taps = tap_grid(tmin, tmax, step, nominal, enabled)
% Build a discrete tap grid, preserving the nominal tap as a fallback.
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
if isempty(taps)
    taps = nominal;
else
    taps = unique([taps; lo; hi; nominal]);
    taps = taps(taps > 0 & taps >= lo - 1e-9 & taps <= hi + 1e-9);
end
if isempty(taps)
    taps = 1;
end

function [tap, angle, status, ok] = select_tap_by_angle(taps, nominal, amin, amax, angle_fn)
% Keep in-band taps fixed; otherwise target the maximum angle in band.
tol = 1e-9;
loang = min(amin, amax);
hiang = max(amin, amax);
amin = loang;
amax = hiang;
if isempty(taps)
    taps = nominal;
end
taps = sort(unique(taps(:)));
if nominal <= 0 || isnan(nominal)
    nominal = taps(1);
end
cur = nearest_value(taps, nominal);
cur_angle = angle_fn(cur);
if isfinite(cur_angle) && cur_angle >= amin - tol && cur_angle <= amax + tol
    tap = cur;
    angle = cur_angle;
    status = 'RG';
    ok = true;
    return;
end

angles = nan(size(taps));
for ii = 1:length(taps)
    angles(ii) = angle_fn(taps(ii));
end
in_band = isfinite(angles) & angles >= amin - tol & angles <= amax + tol;
if any(in_band)
    cand = find(in_band);
    if isfinite(cur_angle)
        if cur_angle < amin
            directed = cand(angles(cand) >= cur_angle - tol);
        elseif cur_angle > amax
            directed = cand(angles(cand) <= cur_angle + tol);
        else
            directed = cand;
        end
        if ~isempty(directed)
            cand = directed;
        end
    end
    score = [abs(angles(cand) - amax) abs(taps(cand) - cur)];
    [~, jj] = sortrows(score);
    pick = cand(jj(1));
    tap = taps(pick);
    angle = angles(pick);
    status = 'RG';
    ok = true;
    return;
end

finite = find(isfinite(angles));
if isempty(finite)
    tap = cur;
    angle = cur_angle;
    status = limit_status(tap, taps(1), taps(end));
    ok = false;
    return;
end
if isfinite(cur_angle) && cur_angle < amin
    [~, jj] = max(angles(finite));
elseif isfinite(cur_angle) && cur_angle > amax
    [~, jj] = min(angles(finite));
else
    [~, jj] = min(abs(angles(finite) - amax));
end
pick = finite(jj);
tap = taps(pick);
angle = angles(pick);
status = limit_status(tap, taps(1), taps(end));
ok = isfinite(angle);

function status = inverter_tap_status(tap, taps, verr)
% Report PSS/E-style tap status for the inverter voltage target.
if isempty(taps) || isscalar(taps)
    status = 'FX';
elseif tap <= min(taps) + 1e-9 && verr < -1e-6
    status = 'LO';
elseif tap >= max(taps) - 1e-9 && verr > 1e-6
    status = 'HI';
else
    status = 'RG';
end

function status = limit_status(tap, tmin, tmax)
lo = min(tmin, tmax);
hi = max(tmin, tmax);
if tap <= lo + 1e-9
    status = 'LO';
elseif tap >= hi - 1e-9
    status = 'HI';
else
    status = 'RG';
end

function v = nearest_value(values, target)
[~, i] = min(abs(values - target));
v = values(i);

function tf = lex_lt(a, b)
% True when row vector a is lexicographically smaller than b.
tf = false;
for ii = 1:length(a)
    if a(ii) < b(ii) - 1e-9
        tf = true;
        return;
    elseif a(ii) > b(ii) + 1e-9
        return;
    end
end

function y = clamp(x, lo, hi)
y = min(max(x, lo), hi);

function op = default_op()
op = struct( ...
    'valid', false, ...
    'current_limited', false, ...
    'pf', 0, ...
    'pt', 0, ...
    'loss', 0, ...
    'qacr', 0, ...
    'qaci', 0, ...
    'idc', 0, ...
    'vdcr', 0, ...
    'vdci', 0, ...
    'vcomp', 0, ...
    'iacr', 0, ...
    'iaci', 0, ...
    'mu_r', 0, ...
    'mu_i', 0, ...
    'tapr', 1, ...
    'tapi', 1, ...
    'tapr_status', '--', ...
    'tapi_status', '--', ...
    'alpha', 0, ...
    'gamma', 0 ...
);
