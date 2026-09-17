function [direction, target, active_members] = psse_swshunt_group_action(state, members, v, eligible)
%PSSE_SWSHUNT_GROUP_ACTION Pure weighted request for one regulated-bus group.
% See docs/SWSHUNT_DECISION_CONTRACT.md for the shared acceptance boundary.
% The caller supplies current eligibility, including locks applied after
% construction of the group. No electrical acceptance or recovery occurs here.
%
%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%   This file is part of MATPOWER, covered by the 3-clause BSD License.
%   See LICENSE and https://matpower.org for details.

members = members(eligible(members));
err = zeros(length(members), 1);
target_k = NaN(length(members), 1);
for jj = 1:length(members)
    k = members(jj);
    [lo, hi] = voltage_band(state, k);
    if isnan(lo) || isnan(hi)
        continue;
    end
    if state.modsw(k) == 1
        if v < lo - state.vtol
            target_k(jj) = lo;
            err(jj) = lo - v;
        elseif v > hi + state.vtol
            target_k(jj) = hi;
            err(jj) = hi - v;
        end
    elseif state.modsw(k) == 2
        target_k(jj) = (lo + hi) / 2;
        if abs(target_k(jj) - v) > state.vtol
            err(jj) = target_k(jj) - v;
        end
    end
end

up = find(err > 0);
dn = find(err < 0);
up_score = sum(abs(err(up)) .* state.rmpct(members(up)) / 100);
dn_score = sum(abs(err(dn)) .* state.rmpct(members(dn)) / 100);
if up_score == 0 && dn_score == 0
    direction = 0;
    target = NaN;
    active_members = [];
    return;
elseif up_score >= dn_score
    direction = 1;
    active = up;
else
    direction = -1;
    active = dn;
end

active_members = members(active);
weights = state.rmpct(active_members);
if isempty(weights) || sum(weights) == 0
    target = mean(target_k(active));
else
    target = sum(target_k(active) .* weights) / sum(weights);
end

function [lo, hi] = voltage_band(state, k)
% Return a normalized voltage band for one switched shunt.
lo = state.vswlo(k);
hi = state.vswhi(k);
if isnan(lo) || isnan(hi)
    return;
end
if hi < lo
    tmp = hi;
    hi = lo;
    lo = tmp;
end

