function [state, conv] = update_vsc_state(mpc, state, ac, dc, map)
% update_vsc_state - Updates VSC-MTDC state from AC and DC power flow results.
% ::
%
%   [STATE, CONV] = UPDATE_VSC_STATE(MPC, STATE, AC, DC, MAP)
%
%   Reads AC voltages, AC reactive output, converter losses, DC voltages and
%   DC converter powers, then updates the VSC state using
%
%       Pac + Pdc + Ploss = 0.
%
% See also idx_vsc, apply_vsc_ac_model, solve_vsc_dc_pf, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, BUS_I, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
[~, ~, QG] = idx_gen;
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, PF, ~, PT, QT] = idx_brch;
bdc = idx_busdc;
c = idx_vsc;

old = state;
vsc = mpc.vsc;
nv = size(vsc, 1);
active = find(vsc(:, c.VSC_STATUS) > 0);

for k = active'
    pcc = find(ac.bus(:, BUS_I) == vsc(k, c.VSC_BUS), 1);
    filter = find(ac.bus(:, BUS_I) == map.filter_bus(k), 1);
    internal = find(ac.bus(:, BUS_I) == map.internal_bus(k), 1);
    state.vac_pcc(k) = ac.bus(pcc, VM);
    state.vac_filter(k) = ac.bus(filter, VM);
    state.vac_internal(k) = ac.bus(internal, VM);
    if map.uses_gen(k)
        state.qac(k) = ac.gen(map.gen(k), QG);
    else
        state.qac(k) = vsc(k, c.QAC_SET);
    end
end

[state.ploss, state.iac] = calc_vsc_losses(mpc.baseMVA, state.pac, ...
    state.qac, state.vac_internal, vsc);
state.ploss(vsc(:, c.VSC_STATUS) <= 0) = 0;
state.pdc = dc.pdc;

for k = active'
    b = find(dc.busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1);
    state.vdc(k) = dc.busdc(b, bdc.VDC);
end

fixed_pac = vsc(:, c.AC_MODE) == c.VSC_AC_PQ | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
state.pac(active) = -state.pdc(active) - state.ploss(active);
state.pac(fixed_pac & vsc(:, c.VSC_STATUS) > 0) = vsc(fixed_pac & vsc(:, c.VSC_STATUS) > 0, c.PAC_SET);

state.ptr_loss(:) = 0;
state.preactor_loss(:) = 0;
for k = active'
    if map.tr_branch(k) > 0 && size(ac.branch, 2) >= QT
        state.ptr_loss(k) = ac.branch(map.tr_branch(k), PF) + ac.branch(map.tr_branch(k), PT);
    end
    if map.reactor_branch(k) > 0 && size(ac.branch, 2) >= QT
        state.preactor_loss(k) = ac.branch(map.reactor_branch(k), PF) + ac.branch(map.reactor_branch(k), PT);
    end
end

state.filter_bus = map.filter_bus;
state.internal_bus = map.internal_bus;
state.tr_branch = map.tr_branch;
state.reactor_branch = map.reactor_branch;
state.is_dc_slack = zeros(nv, 1);
state.is_dc_slack(vsc(:, c.DC_MODE) == c.VSC_DC_VDC & vsc(:, c.VSC_STATUS) > 0) = 1;

vac_ctrl = vsc(:, c.AC_MODE) == c.VSC_AC_V | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
ctrl_v = active(vac_ctrl(active));
vac_error = zeros(nv, 1);
if ~isempty(ctrl_v)
    vac_error(ctrl_v) = vsc(ctrl_v, c.VAC_SET) - state.vac_pcc(ctrl_v);
    state.vac_internal_set(ctrl_v) = state.vac_internal_set(ctrl_v) + vac_error(ctrl_v);
end

conv = struct( ...
    'max_delta_pac', max(abs(state.pac - old.pac)), ...
    'max_delta_pdc', max(abs(state.pdc - old.pdc)), ...
    'max_delta_vdc', max(abs(state.vdc - old.vdc)), ...
    'max_delta_qac', max(abs(state.qac - old.qac)), ...
    'max_delta_vac_set', max(abs(state.vac_internal_set - old.vac_internal_set)), ...
    'max_vac_ctrl_error', max(abs(vac_error)), ...
    'max_balance',   max(abs(state.pac + state.pdc + state.ploss)) );
end
