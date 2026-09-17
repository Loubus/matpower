function [Ploss, Iac] = calc_vsc_losses(baseMVA, Pconv, Qconv, Uconv, vsc)
% calc_vsc_losses - Computes VSC converter losses.
% Inputs PCONV/QCONV are INTERNAL terminal powers, not PCC PAC/QAC.
% UCONV is the internal voltage; current is on the system MVA base.
% ::
%
%   [PLOSS, IAC] = CALC_VSC_LOSSES(BASEMVA, PCONV, QCONV, UCONV, VSC)
%
%   Computes converter losses using
%
%       Ploss = a + b * I + c * I^2
%
%   with
%
%       I = sqrt(Pconv^2 + Qconv^2) / (baseMVA * Uconv)
%
%   where Pconv is positive for active power injection into the AC network,
%   Qconv is positive for reactive power injection into the AC network, and
%   Uconv is the internal VSC AC voltage magnitude in p.u.
%
% See also idx_vsc, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

c = idx_vsc;

if size(vsc, 2) < c.LOSS_C
    error('calc_vsc_losses: vsc matrix must have at least %d columns', c.LOSS_C);
end
if any(vsc(:, c.LOSS_A) < 0 | vsc(:, c.LOSS_B) < 0 | vsc(:, c.LOSS_C) < 0)
    error('calc_vsc_losses: VSC loss coefficients must be non-negative');
end

Uconv = max(abs(Uconv), eps);
Iac = sqrt(Pconv.^2 + Qconv.^2) ./ (baseMVA .* Uconv);
Ploss = vsc(:, c.LOSS_A) + vsc(:, c.LOSS_B) .* Iac + vsc(:, c.LOSS_C) .* Iac.^2;
