function [Ploss, Iac] = calc_vsc_losses(baseMVA, Pac, Qac, Vac, vsc)
% calc_vsc_losses - Computes VSC converter losses.
% ::
%
%   [PLOSS, IAC] = CALC_VSC_LOSSES(BASEMVA, PAC, QAC, VAC, VSC)
%
%   Computes converter losses using
%
%       Ploss = a + b * I + c * I^2
%
%   with
%
%       I = sqrt(Pac^2 + Qac^2) / (baseMVA * Vac)
%
%   where Pac is positive for active power injection into the AC network,
%   Qac is positive for reactive power injection into the AC network, and
%   Vac is the internal VSC AC voltage magnitude in p.u.
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

Vac = max(abs(Vac), eps);
Iac = sqrt(Pac.^2 + Qac.^2) ./ (baseMVA .* Vac);
Ploss = vsc(:, c.LOSS_A) + vsc(:, c.LOSS_B) .* Iac + vsc(:, c.LOSS_C) .* Iac.^2;
