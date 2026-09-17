function [ac, map] = apply_vsc_ac_model(mpc, state)
% apply_vsc_ac_model - Builds the extended AC case for VSC-MTDC stations.
% ::
%
%   [AC, MAP] = APPLY_VSC_AC_MODEL(MPC, STATE)
%
%   Adds, for each in-service VSC, the explicit AC topology
%
%       PCC AC bus -> transformer -> filter bus -> phase reactor
%           -> VSC internal AC bus -> VSC/DC interface
%
%   The transformer, filter shunt and phase reactor are modeled as separate
%   MATPOWER elements. Converter active/reactive injections are applied at
%   the internal VSC AC bus using the sign convention from IDX_VSC.
%
% See also idx_vsc, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[PQ, PV, ~, ~, BUS_I, BUS_TYPE, PD, QD, GS, BS, ~, VM, VA] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, ~, ~, ~, ~, ~, ~, ANGMIN, ANGMAX] = idx_brch;
c = idx_vsc;

ac = mpc;
fields = {'busdc', 'branchdc', 'vsc'};
for k = 1:length(fields)
    if isfield(ac, fields{k})
        ac = rmfield(ac, fields{k});
    end
end

vsc = mpc.vsc;
nv = size(vsc, 1);
map = struct( ...
    'active',        find(vsc(:, c.VSC_STATUS) > 0), ...
    'filter_bus',    zeros(nv, 1), ...
    'internal_bus',  zeros(nv, 1), ...
    'tr_branch',     zeros(nv, 1), ...
    'reactor_branch', zeros(nv, 1), ...
    'gen',           zeros(nv, 1), ...
    'uses_gen',      zeros(nv, 1) );

if isempty(map.active)
    return;
end

%% ensure standard matrix widths
if size(ac.branch, 2) < ANGMAX
    ac.branch = [ac.branch zeros(size(ac.branch, 1), ANGMAX - size(ac.branch, 2))];
end
if isempty(ac.gen)
    ac.gen = zeros(0, APF);
elseif size(ac.gen, 2) < APF
    ac.gen = [ac.gen zeros(size(ac.gen, 1), APF - size(ac.gen, 2))];
end

max_bus = max(ac.bus(:, BUS_I));
next_bus = max_bus + 1;
baseMVA = ac.baseMVA;

for kk = 1:length(map.active)
    k = map.active(kk);
    pcc = find(ac.bus(:, BUS_I) == vsc(k, c.VSC_BUS), 1);
    if isempty(pcc)
        error('apply_vsc_ac_model: VSC row %d refers to an unknown AC bus', k);
    end

    filter_bus = next_bus;
    internal_bus = next_bus + 1;
    next_bus = next_bus + 2;

    filter = ac.bus(pcc, :);
    filter(BUS_I) = filter_bus;
    filter(BUS_TYPE) = PQ;
    filter([PD QD]) = 0;
    filter(GS) = vsc(k, c.FILTER_G) * baseMVA;
    filter(BS) = vsc(k, c.FILTER_B) * baseMVA;
    filter(VM) = ac.bus(pcc, VM);
    filter(VA) = ac.bus(pcc, VA);

    internal = ac.bus(pcc, :);
    internal(BUS_I) = internal_bus;
    internal(BUS_TYPE) = PQ;
    internal([PD QD GS BS]) = 0;
    internal(VM) = state.vac_internal_set(k);
    internal(VA) = ac.bus(pcc, VA);

    ac_mode = vsc(k, c.AC_MODE);
    if ac_mode == c.VSC_AC_Q || ac_mode == c.VSC_AC_PQ
        internal(PD) = -state.pac(k);
        internal(QD) = -state.qac(k);
    elseif ac_mode == c.VSC_AC_V || ac_mode == c.VSC_AC_PV
        internal(BUS_TYPE) = PV;
    else
        error('apply_vsc_ac_model: VSC row %d has an unknown AC_MODE', k);
    end

    ac.bus = [ac.bus; filter; internal];

    tr = zeros(1, size(ac.branch, 2));
    tr([F_BUS T_BUS BR_R BR_X BR_B RATE_A RATE_B RATE_C TAP SHIFT BR_STATUS ANGMIN ANGMAX]) = ...
        [vsc(k, c.VSC_BUS) filter_bus vsc(k, c.TR_R) vsc(k, c.TR_X) vsc(k, c.TR_B) ...
         vsc(k, c.TR_RATE_A) vsc(k, c.TR_RATE_B) vsc(k, c.TR_RATE_C) ...
         0 vsc(k, c.TR_SHIFT) 1 -360 360];
    ac.branch = [ac.branch; tr];
    map.tr_branch(k) = size(ac.branch, 1);

    reactor = zeros(1, size(ac.branch, 2));
    reactor([F_BUS T_BUS BR_R BR_X BR_B RATE_A RATE_B RATE_C TAP SHIFT BR_STATUS ANGMIN ANGMAX]) = ...
        [filter_bus internal_bus vsc(k, c.REACTOR_R) vsc(k, c.REACTOR_X) vsc(k, c.REACTOR_B) ...
         vsc(k, c.REACTOR_RATE_A) vsc(k, c.REACTOR_RATE_B) vsc(k, c.REACTOR_RATE_C) ...
         0 0 1 -360 360];
    ac.branch = [ac.branch; reactor];
    map.reactor_branch(k) = size(ac.branch, 1);

    if ac_mode == c.VSC_AC_V || ac_mode == c.VSC_AC_PV
        gen = zeros(1, size(ac.gen, 2));
        gen(GEN_BUS) = internal_bus;
        gen(PG) = state.pac(k);
        gen(QG) = state.qac(k);
        gen(QMAX) = 1e9;
        gen(QMIN) = -1e9;
        gen(VG) = state.vac_internal_set(k);
        gen(MBASE) = baseMVA;
        gen(GEN_STATUS) = 1;
        gen(PMAX) = 1e9;
        gen(PMIN) = -1e9;
        ac.gen = [ac.gen; gen];
        map.gen(k) = size(ac.gen, 1);
        map.uses_gen(k) = 1;
    end

    map.filter_bus(k) = filter_bus;
    map.internal_bus(k) = internal_bus;
end
