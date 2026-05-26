function val = psse_system_value(mpc, section, key, default)
% psse_system_value - Returns a PSS/E SYSTEM-WIDE option value.
% ::
%
%   VAL = MP.PSSE_SYSTEM_VALUE(MPC, SECTION, KEY, DEFAULT)
%
% Returns an explicit PSS/E RAW value from ``mpc.psse.system`` when present.
% Otherwise, if ``mpc.psse.solver_options.effective`` is available, returns
% the reported effective value from the solver policy. Falls back to DEFAULT.
%
% See also mp.psse_solver_options.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 4
    default = NaN;
end

val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
    return;
end

if isfield(mpc, 'psse') && isfield(mpc.psse, 'solver_options') && ...
        isfield(mpc.psse.solver_options, 'effective')
    entries = mpc.psse.solver_options.effective;
    for k = 1:length(entries)
        if strcmpi(entries(k).section, section) && ...
                strcmpi(entries(k).name, key)
            val = entries(k).value;
            return;
        end
    end
end
