function b = psse_swshunt_discrete_next(state, k, direction)
%PSSE_SWSHUNT_DISCRETE_NEXT One adjacent admissible BINIT, or unchanged bound.
% Sorted constructor grid and normalized current state are required.
% See docs/SWSHUNT_DECISION_CONTRACT.md. This does not accept an electrical state.
%
%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%   This file is part of MATPOWER, covered by the 3-clause BSD License.
%   See LICENSE and https://matpower.org for details.

states = state.states{k};
if isempty(states)
    b = state.current_b(k);
    return;
end
[~, cur] = min(abs(states - state.current_b(k)));
if direction > 0
    cand = find(states > states(cur) + 1e-9, 1);
else
    cand = find(states < states(cur) - 1e-9, 1, 'last');
end
if isempty(cand)
    b = state.current_b(k);
else
    b = states(cand);
end

