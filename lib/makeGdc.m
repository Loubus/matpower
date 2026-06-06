function Gdc = makeGdc(busdc, branchdc)
% makeGdc - Builds the DC conductance matrix for a resistive DC network.
% ::
%
%   GDC = MAKEGDC(BUSDC, BRANCHDC)
%
%   Builds the sparse DC conductance matrix from the in-service rows of
%   BRANCHDC. For a DC branch between buses m and n, with resistance Rdc,
%   the conductance is gdc = 1/Rdc. The resulting matrix is used with
%
%       Idc = Gdc * Vdc
%
%   where Vdc is in p.u. and Idc is in p.u.
%
% See also idx_busdc, idx_branchdc, solve_vsc_dc_pf.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

bdc = idx_busdc;
brdc = idx_branchdc;

nb = size(busdc, 1);
Gdc = sparse(nb, nb);

if isempty(branchdc)
    return;
end

if size(busdc, 2) < bdc.BASE_KVDC
    error('makeGdc: busdc matrix must have at least %d columns', bdc.BASE_KVDC);
end
if size(branchdc, 2) < brdc.BRDC_STATUS
    error('makeGdc: branchdc matrix must have at least %d columns', brdc.BRDC_STATUS);
end

on = find(branchdc(:, brdc.BRDC_STATUS) > 0);
ii = zeros(4 * length(on), 1);
jj = zeros(4 * length(on), 1);
vv = zeros(4 * length(on), 1);
nz = 0;
for k = on'
    f = find(busdc(:, bdc.BUSDC_I) == branchdc(k, brdc.F_BUSDC), 1);
    t = find(busdc(:, bdc.BUSDC_I) == branchdc(k, brdc.T_BUSDC), 1);
    if isempty(f) || isempty(t)
        error('makeGdc: branchdc row %d refers to an unknown DC bus', k);
    end
    if busdc(f, bdc.BUSDC_STATUS) <= 0 || busdc(t, bdc.BUSDC_STATUS) <= 0
        continue;
    end
    r = branchdc(k, brdc.BRDC_R);
    if r <= 0
        error('makeGdc: branchdc row %d has non-positive resistance', k);
    end
    g = 1 / r;
    rows = nz + (1:4);
    ii(rows) = [f; t; f; t];
    jj(rows) = [f; t; t; f];
    vv(rows) = [g; g; -g; -g];
    nz = nz + 4;
end
Gdc = sparse(ii(1:nz), jj(1:nz), vv(1:nz), nb, nb);
