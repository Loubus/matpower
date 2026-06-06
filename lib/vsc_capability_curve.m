function [sat, P, Q, S, info] = ...
        vsc_capability_curve(P, Q, Smax, V, vsc_row, mode, Vmax, baseMVA)
% vsc_capability_curve - MATPOWER VSC wrapper for geometric P-Q capability.
% ::
%
%   [SAT, P, Q, S, INFO] = VSC_CAPABILITY_CURVE(P0, Q0, SMAX, V, VSC_ROW)
%   [SAT, P, Q, S, INFO] = VSC_CAPABILITY_CURVE(..., MODE, VMAX, BASEMVA)
%
%   P0, Q0 and SMAX are in MW/MVAr/MVA by default. The capability geometry
%   is evaluated internally in p.u. on the VSC nominal apparent-power base
%   SMAX. Inputs and outputs remain in MW/MVAr/MVA. BASEMVA is used only to
%   convert the station impedance from MATPOWER system base to the VSC
%   element base. If BASEMVA is omitted, 1 is used.
%
%   VSC_ROW is a row from MPC.VSC or RESULTS.VSC. Its transformer and reactor
%   impedance columns define XEQ = abs((TR_R + REACTOR_R) + j*(TR_X +
%   REACTOR_X)). If SMAX is empty, the minimum positive long-term transformer
%   or reactor rating is used.
%
%   When MODE is omitted, VSC_CAPABILITY_POLICY selects the default:
%   DC slack and droop converters use 'preservar_p'; fixed-PDC converters
%   use 'radial'.
%
%   This helper implements the post-solve saturation projection used by the
%   VSC-MTDC capability audit and active-set enforcement layers. It does not
%   add OPF constraints or modify a MATPOWER case/result struct.
%
% See also vsc_capability_geometry, vsc_capability_policy,
% check_vsc_capability.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 6
    mode = [];
end
if nargin < 7 || isempty(Vmax)
    Vmax = 1.15;
end
if nargin < 8 || isempty(baseMVA)
    baseMVA = 1;
end
if isempty(baseMVA) || ~isscalar(baseMVA) || ~isnumeric(baseMVA) || ...
        ~isfinite(baseMVA) || baseMVA <= 0
    error('vsc_capability_curve: baseMVA must be a positive finite scalar');
end

c = idx_vsc;
[xEq, Smax, policy, xEq_system] = ...
    vsc_params(vsc_row, Smax, mode, c, baseMVA);
mode = policy.projection_mode;
Sbase = Smax;

[sat, Ppu, Qpu, Spu, info_pu] = vsc_capability_geometry( ...
    P / Sbase, Q / Sbase, 1, V, xEq, mode, Vmax);
P = Ppu * Sbase;
Q = Qpu * Sbase;
S = Spu * Sbase;

info = scale_info(info_pu, Sbase);
info.baseMVA = baseMVA;
info.element_base_mva = Sbase;
info.per_unit_base = 'element';
info.xEq_element = xEq;
info.xEq_system = xEq_system;
info.P_original_pu = info_pu.P_original;
info.Q_original_pu = info_pu.Q_original;
info.S_original_pu = info_pu.S_original;
info.P_pu = info_pu.P;
info.Q_pu = info_pu.Q;
info.S_pu = info_pu.S;
info.Smax_pu = info_pu.Smax;
info.qMin_pu = info_pu.qMin;
info.qMax_pu = info_pu.qMax;
info.pFactible_pu = info_pu.pFactible;
info.pMax_pu = info_pu.pMax;
info.iMax_pu = info_pu.iMax;
info.qCenter_pu = info_pu.qCenter;
info.vRadius_pu = info_pu.vRadius;
info.margin_pu = info_pu.margin;
info.projection_norm_pu = info_pu.projection_norm;
info.policy = policy;
info.policy_reason = policy.reason;
info.target_ac_mode_if_saturated = policy.target_ac_mode_if_saturated;
info.target_ac_mode_if_p_preserved = policy.target_ac_mode_if_p_preserved;
info.target_ac_mode_if_p_changed = policy.target_ac_mode_if_p_changed;
info.source = 'vsc_capability_curve';


function [xEq, Smax, policy, xEq_system] = ...
        vsc_params(vsc_row, Smax, mode, c, baseMVA)
if isempty(vsc_row) || ~isnumeric(vsc_row) || ~ismatrix(vsc_row) || ...
        size(vsc_row, 1) ~= 1
    error('vsc_capability_curve: vsc_row must be one VSC row or scalar xEq');
end

if isscalar(vsc_row)
    xEq = abs(vsc_row);
    xEq_system = NaN;
    policy = vsc_capability_policy(vsc_row, struct('mode', mode));
else
    needed = c.REACTOR_RATE_A;
    if size(vsc_row, 2) < needed
        error('vsc_capability_curve: vsc_row is missing VSC station columns');
    end
    xEq = abs(vsc_row(c.TR_R) + vsc_row(c.REACTOR_R) + ...
        1j * (vsc_row(c.TR_X) + vsc_row(c.REACTOR_X)));
    if isempty(Smax)
        ratings = vsc_row([c.TR_RATE_A c.REACTOR_RATE_A]);
        ratings = ratings(isfinite(ratings) & ratings > 0);
        if isempty(ratings)
            error('vsc_capability_curve: Smax must be provided when VSC ratings are missing');
        end
        Smax = min(ratings);
    end
    xEq_system = xEq;
    xEq = xEq_system * Smax / baseMVA;
    policy = vsc_capability_policy(vsc_row, struct('mode', mode));
end


function info = scale_info(info, baseMVA)
info.Smax = info.Smax * baseMVA;
info.P_original = info.P_original * baseMVA;
info.Q_original = info.Q_original * baseMVA;
info.S_original = info.S_original * baseMVA;
info.P = info.P * baseMVA;
info.Q = info.Q * baseMVA;
info.S = info.S * baseMVA;
info.qMin = info.qMin * baseMVA;
info.qMax = info.qMax * baseMVA;
info.pFactible = info.pFactible * baseMVA;
info.pMax = info.pMax * baseMVA;
info.iMax = info.iMax * baseMVA;
info.qCenter = info.qCenter * baseMVA;
info.vRadius = info.vRadius * baseMVA;
info.margin = info.margin * baseMVA;
info.projection_norm = info.projection_norm * baseMVA;
