function dc = solve_vsc_dc_pf(mpc, state, opt)
% solve_vsc_dc_pf - Solves the resistive DC network for VSC-MTDC power flow.
% ::
%
%   DC = SOLVE_VSC_DC_PF(MPC, STATE, OPT)
%
%   Solves the DC network equations
%
%       Idc = Gdc * Vdc
%       Pdc_net_m = Vdc_m * Idc_m * baseMVA
%
%   with VSC DC voltage slack converters fixing Vdc and receiving Pdc as a
%   result. Fixed Pdc and optional droop converters provide specified DC
%   injections using the sign convention in IDX_VSC.
%
% See also makeGdc, idx_vsc, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 3 || isempty(opt)
    opt = struct;
end
if ~isfield(opt, 'max_it'), opt.max_it = 20; end
if ~isfield(opt, 'tol_p'),  opt.tol_p = 1e-8; end
if ~isfield(opt, 'tol_v'),  opt.tol_v = 1e-8; end

bdc = idx_busdc;
brdc = idx_branchdc;
c = idx_vsc;

busdc = mpc.busdc;
branchdc = mpc.branchdc;
vsc = mpc.vsc;
baseMVA = mpc.baseMVA;
nb = size(busdc, 1);
nv = size(vsc, 1);

if size(busdc, 2) < bdc.IDC
    busdc = [busdc zeros(nb, bdc.IDC - size(busdc, 2))];
end
if size(branchdc, 2) < brdc.ITDC
    branchdc = [branchdc zeros(size(branchdc, 1), brdc.ITDC - size(branchdc, 2))];
end

Gdc = makeGdc(busdc, branchdc);
bus_on = find(busdc(:, bdc.BUSDC_STATUS) > 0);
vsc_on = find(vsc(:, c.VSC_STATUS) > 0);

bus_lookup = zeros(nv, 1);
for k = vsc_on'
    i = find(busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1);
    if isempty(i)
        error('solve_vsc_dc_pf: VSC row %d refers to an unknown DC bus', k);
    end
    bus_lookup(k) = i;
end

slack_vsc = vsc_on(vsc(vsc_on, c.DC_MODE) == c.VSC_DC_VDC);
if isempty(slack_vsc)
    error('solve_vsc_dc_pf: at least one in-service VSC must use VSC_DC_VDC mode');
end

fixed = unique(bus_lookup(slack_vsc));
V = busdc(:, bdc.VDC);
for k = slack_vsc'
    V(bus_lookup(k)) = vsc(k, c.VDC_SET);
end
if any(V(bus_on) <= 0)
    error('solve_vsc_dc_pf: in-service DC bus voltages must be positive');
end

fixed_mask = false(nb, 1);
fixed_mask(fixed) = true;
var = bus_on(~fixed_mask(bus_on));

success = 0;
iterations = 0;
max_mismatch = 0;

if isempty(var)
    success = 1;
else
    x = V(var);
    for iterations = 1:opt.max_it
        V(var) = x;
        [F, J] = dc_mismatch_jac(V, var);
        max_mismatch = max(abs(F));
        if isempty(max_mismatch)
            max_mismatch = 0;
        end
        if max_mismatch < opt.tol_p
            success = 1;
            break;
        end
        dx = -J \ F;
        x = x + dx;
        if max(abs(dx)) < opt.tol_v
            V(var) = x;
            F = dc_mismatch_jac(V, var);
            max_mismatch = max(abs(F));
            if max_mismatch < opt.tol_p
                success = 1;
                break;
            end
        end
    end
    V(var) = x;
end

I = Gdc * V;
Pnet = V .* I * baseMVA;

pdc = zeros(nv, 1);
for k = vsc_on'
    if vsc(k, c.DC_MODE) == c.VSC_DC_VDC
        continue;
    end
    if isfield(state, 'pdc_override') && ~isnan(state.pdc_override(k))
        pdc(k) = state.pdc_override(k);
    elseif vsc(k, c.DC_MODE) == c.VSC_DC_PDC
        pdc(k) = vsc(k, c.PDC_SET);
    elseif vsc(k, c.DC_MODE) == c.VSC_DC_DROOP
        pdc(k) = vsc(k, c.PDC_SET) + vsc(k, c.KDROOP) * (V(bus_lookup(k)) - vsc(k, c.VDC_SET));
    else
        error('solve_vsc_dc_pf: VSC row %d has an unknown DC_MODE', k);
    end
end

for bb = fixed(:)'
    ks = slack_vsc(bus_lookup(slack_vsc) == bb);
    other = vsc_on(bus_lookup(vsc_on) == bb & vsc(vsc_on, c.DC_MODE) ~= c.VSC_DC_VDC);
    p = Pnet(bb) - sum(pdc(other));
    pdc(ks) = p / length(ks);
end

branchdc(:, brdc.PFDC:brdc.ITDC) = 0;
for k = 1:size(branchdc, 1)
    if branchdc(k, brdc.BRDC_STATUS) <= 0
        continue;
    end
    f = find(busdc(:, bdc.BUSDC_I) == branchdc(k, brdc.F_BUSDC), 1);
    t = find(busdc(:, bdc.BUSDC_I) == branchdc(k, brdc.T_BUSDC), 1);
    if busdc(f, bdc.BUSDC_STATUS) <= 0 || busdc(t, bdc.BUSDC_STATUS) <= 0
        continue;
    end
    g = 1 / branchdc(k, brdc.BRDC_R);
    If = g * (V(f) - V(t));
    It = -If;
    branchdc(k, brdc.IFDC) = If;
    branchdc(k, brdc.ITDC) = It;
    branchdc(k, brdc.PFDC) = V(f) * If * baseMVA;
    branchdc(k, brdc.PTDC) = V(t) * It * baseMVA;
end

busdc(:, bdc.VDC) = V;
busdc(:, bdc.IDC) = I;
busdc(:, bdc.PDC) = 0;
for k = vsc_on'
    busdc(bus_lookup(k), bdc.PDC) = busdc(bus_lookup(k), bdc.PDC) + pdc(k);
end

dc = struct( ...
    'success',      success, ...
    'iterations',   iterations, ...
    'max_mismatch', max_mismatch, ...
    'busdc',        busdc, ...
    'branchdc',     branchdc, ...
    'vdc',          V, ...
    'pdc',          pdc, ...
    'Gdc',          Gdc );

    function [F, J, Pspec, dPspec_dV] = dc_mismatch_jac(V, var)
        I = Gdc * V;
        Pnet = V .* I * baseMVA;
        Pspec = zeros(nb, 1);
        dPspec_dV = zeros(nb, 1);
        for kk = vsc_on'
            if vsc(kk, c.DC_MODE) == c.VSC_DC_VDC
                continue;
            end
            bus_idx = bus_lookup(kk);
            if isfield(state, 'pdc_override') && ~isnan(state.pdc_override(kk))
                p = state.pdc_override(kk);
                dp = 0;
            elseif vsc(kk, c.DC_MODE) == c.VSC_DC_PDC
                p = vsc(kk, c.PDC_SET);
                dp = 0;
            elseif vsc(kk, c.DC_MODE) == c.VSC_DC_DROOP
                p = vsc(kk, c.PDC_SET) + vsc(kk, c.KDROOP) * (V(bus_idx) - vsc(kk, c.VDC_SET));
                dp = vsc(kk, c.KDROOP);
            else
                error('solve_vsc_dc_pf: VSC row %d has an unknown DC_MODE', kk);
            end
            Pspec(bus_idx) = Pspec(bus_idx) + p;
            dPspec_dV(bus_idx) = dPspec_dV(bus_idx) + dp;
        end

        F = Pnet(var) - Pspec(var);
        nvar = length(var);
        J = zeros(nvar, nvar);
        for rr = 1:nvar
            i = var(rr);
            for cc = 1:nvar
                j = var(cc);
                J(rr, cc) = baseMVA * ((i == j) * I(i) + V(i) * Gdc(i, j));
                if i == j
                    J(rr, cc) = J(rr, cc) - dPspec_dV(i);
                end
            end
        end
    end
end
