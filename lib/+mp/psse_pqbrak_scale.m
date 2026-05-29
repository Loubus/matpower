function scale = psse_pqbrak_scale(vm, pqbrak)
% psse_pqbrak_scale - PSS/E low-voltage constant MVA load scale.
% ::
%
%   SCALE = MP.PSSE_PQBRAK_SCALE(VM, PQBRAK)
%
% Returns the effective constant-MVA load multiplier for the PSS/E PQBRAK
% boundary condition below the configured voltage breakpoint. PSS/E exposes
% the breakpoint as a SYSTEM-WIDE parameter, but not the exact low-voltage
% taper formula. This implementation keeps a smooth cubic transition near the
% breakpoint and uses the empirically calibrated exponent below 0.9 * PQBRAK
% that matches the local PSS/E CLI stress-case validation set.
%
% See also mp.psse_pqbrak_prepare, mp.psse_pqbrak_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

scale = ones(size(vm));
if isempty(vm) || isnan(pqbrak) || pqbrak <= 0
    return;
end

low = vm < pqbrak;
if any(low)
    x = max(min(vm(low) ./ pqbrak, 1), 0);
    % Blend from the stress-case exponent to the standard cubic taper as the
    % voltage approaches PQBRAK, preserving a smooth value at the breakpoint.
    w = max(min((x - 0.9) / 0.1, 1), 0);
    p = 0.94 + 0.06 * (1 - (1 - w) .^ 4);
    z = x .^ p;
    scale(low) = z .^ 2 .* (3 - 2 * z);
end
