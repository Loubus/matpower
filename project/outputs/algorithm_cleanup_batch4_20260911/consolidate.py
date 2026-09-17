from pathlib import Path
root=Path(__file__).resolve().parents[2]
lib=root/'matpower/lib/+mp'
ac=(lib/'psse_swshunt_control.m').read_text()
un=(lib/'psse_unified_control_update.m').read_text()
start=ac.index('function [direction, target, active_members] = group_action')
end=ac.index('function [lo, hi] = voltage_band',start)
group=ac[start:end].replace('= group_action(state, members, v)', '= psse_swshunt_group_action(state, members, v, eligible)')
group=group.replace('% Determine one voltage-control direction for all shunts in a group.', '''%PSSE_SWSHUNT_GROUP_ACTION Pure weighted request for one regulated-bus group.
% See docs/SWSHUNT_DECISION_CONTRACT.md for the shared acceptance boundary.
% The caller supplies current eligibility, including locks applied after
% construction of the group. No electrical acceptance or recovery occurs here.
members = members(eligible(members));''')
bstart=end; bend=ac.index('function b = discrete_next_b',bstart)
group+=ac[bstart:bend]
(lib/'psse_swshunt_group_action.m').write_text(group)
ac=ac[:start]+ac[end:]
start=ac.index('function b = discrete_next_b'); end=ac.index('function b = continuous_next_b',start)
ac=ac[:start]+ac[end:]
ac=ac.replace('group_action(state, members, v)', 'mp.psse_swshunt_group_action( ...\n        state, members, v, state.controllable)')
ac=ac.replace('discrete_next_b(state, k, direction)', 'mp.psse_swshunt_discrete_next(state, k, direction)')
start=un.index('function [direction, active_members] = swshunt_group_action');end=un.index('function [lo, hi] = swshunt_voltage_band',start)
un=un[:start]+un[end:]
start=un.index('function b = discrete_next_b');end=un.index('function b = continuous_next_b',start)
discrete=un[start:end].replace('= discrete_next_b(', '= psse_swshunt_discrete_next(')
discrete=discrete.replace('states = state.states{k};', '''%PSSE_SWSHUNT_DISCRETE_NEXT One adjacent admissible BINIT, or unchanged bound.
% Sorted constructor grid and normalized current state are required.
% See docs/SWSHUNT_DECISION_CONTRACT.md. This does not accept an electrical state.
states = state.states{k};''')
(lib/'psse_swshunt_discrete_next.m').write_text(discrete)
un=un[:start]+un[end:]
un=un.replace('''    % Groups were built before the explicit unified lock mask was applied.
    % Exclude locked rows from both voting and movement in this pass.
    members = members(state.controllable(members));
    [direction, active_members] = swshunt_group_action(state, members, vm(reg));''', '''    [direction, ~, active_members] = mp.psse_swshunt_group_action( ...
        state, members, vm(reg), state.controllable);''')
un=un.replace('discrete_next_b(state, k, direction)', 'mp.psse_swshunt_discrete_next(state, k, direction)')
(lib/'psse_swshunt_control.m').write_text(ac)
(lib/'psse_unified_control_update.m').write_text(un)
