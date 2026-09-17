function acceptance = psse_unified_control_acceptance(report, policy)
%PSSE_UNIFIED_CONTROL_ACCEPTANCE Classify a solved, unchanged direct pass.
% This is control settlement, not electrical convergence or operating-limit
% certification. No state, eligibility, tolerance or lock is changed here.
%
%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%   Covered by the 3-clause BSD License (see LICENSE file for details).
if nargin < 2 || isempty(policy), policy = 'saturate'; end
assert(ischar(policy) && any(strcmpi(policy, {'saturate','stop','freeze'})), ...
    'Unknown vsc_mtdc.psse_control_limit policy');
required = {'supported','changed','requires_auxiliary_pf', ...
    'control_violations','blocked_violations','unsupported_controls'};
authoritative = all(isfield(report, required));
if authoritative
    authoritative = report.supported && ~report.requires_auxiliary_pf && ...
        report.unsupported_controls == 0;
end
violations = 0; blocked = 0; cycles = 0;
if isfield(report,'control_violations'), violations=report.control_violations; end
if isfield(report,'blocked_violations'), blocked=report.blocked_violations; end
if isfield(report,'control_cycles'), cycles=report.control_cycles; end
settled = authoritative && ~report.changed && cycles == 0;
saturated = settled && violations > 0 && blocked == violations;
accepted = settled && (violations == 0 || ...
    (strcmpi(policy,'saturate') && saturated));
status = 'unresolved';
if accepted
    status = 'in_band';
    if saturated, status = 'saturated'; end
elseif saturated
    status = 'control_bound';
end
acceptance = struct('policy',lower(policy),'status',status, ...
    'accepted',logical(accepted),'saturated',logical(saturated), ...
    'regulation_satisfied',logical(settled && violations == 0), ...
    'voltage_source','full_model','authoritative',logical(authoritative), ...
    'control_violations',violations,'blocked_violations',blocked);
end
