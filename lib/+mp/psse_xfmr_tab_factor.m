function [factor, applied] = psse_xfmr_tab_factor(impcor, tab, ratio, angle)
% psse_xfmr_tab_factor - Computes PSS/E transformer impedance correction factors.
% ::
%
%   [FACTOR, APPLIED] = MP.PSSE_XFMR_TAB_FACTOR(IMPCOR, TAB, RATIO, ANGLE)
%
% Returns the complex scaling factor from PSS/E transformer impedance
% correction table metadata. Tables whose first point is below 0.5 or whose
% last point is above 1.5 are treated as phase-shift angle tables; otherwise
% the table input is the off-nominal turns ratio.
%
% See also psse_convert_xfmr, mp.psse_xfmr_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

factor = complex(ones(size(tab)));
applied = false(size(tab));

if isempty(impcor) || ~isstruct(impcor) || ~isfield(impcor, 'num') || ...
        isempty(impcor.num)
    return;
end

tabs = unique(tab(tab ~= 0 & ~isnan(tab)));
for kk = 1:length(tabs)
    tnum = tabs(kk);
    rows = impcor.num(impcor.num(:, 1) == tnum, :);
    x = rows(:, 2);
    f = complex(rows(:, 3), rows(:, 4));
    idx = find(tab == tnum);
    if size(rows, 1) == 1
        factor(idx) = f;
        applied(idx) = true;
        continue;
    end
    [x, ord] = sort(x);
    f = f(ord);
    phase_table = x(1) < 0.5 || x(end) > 1.5;
    if phase_table
        xi = angle(idx);
    else
        xi = ratio(idx);
    end
    factor(idx) = interp1(x, f, xi, 'linear', 'extrap');
    applied(idx) = true;
end
