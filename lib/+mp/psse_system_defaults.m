function defs = psse_system_defaults()
% psse_system_defaults - Returns effective PSS/E SYSTEM-WIDE defaults.
% ::
%
%   DEFS = MP.PSSE_SYSTEM_DEFAULTS()
%
% Returns the effective PSS/E SYSTEM-WIDE defaults reported by the local
% PSS/E CLI validation path. ``ADJUST.MXTPSS`` is reported as 100 by that
% path; some manual RAW/default evidence uses 99, so explicit RAW values
% always take priority in ``runpf_psse``.
%
% See also mp.psse_solver_options, mp.psse_system_value.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

rows = {
    'general', 'PQBRAK', 0.7, 'psse_default';
    'general', 'THRSHZ', 0.0001, 'psse_default';
    'solver', 'METHOD', 'FNSL', 'psse_default';
    'solver', 'ACTAPS', 1, 'psse_default';
    'solver', 'AREAIN', 1, 'psse_default';
    'solver', 'PHSHFT', 1, 'psse_default';
    'solver', 'DCTAPS', 1, 'psse_default';
    'solver', 'SWSHNT', 1, 'psse_default';
    'solver', 'FLATST', 0, 'psse_default';
    'solver', 'VARLIM', 99, 'psse_default';
    'solver', 'NONDIV', 0, 'psse_default';
    'newton', 'ITMXN', 20, 'psse_default';
    'newton', 'ACCN', 1, 'psse_default';
    'newton', 'TOLN', 0.1, 'psse_default';
    'newton', 'DVLIM', 0.99, 'psse_default';
    'newton', 'NDVFCT', 0.99, 'psse_default';
    'newton', 'VCTOLQ', 0.1, 'psse_default';
    'newton', 'VCTOLV', 1e-5, 'psse_default';
    'adjust', 'ADJTHR', 0.005, 'psse_default';
    'adjust', 'ACCTAP', 1, 'psse_default';
    'adjust', 'TAPLIM', 0.05, 'psse_default';
    'adjust', 'SWVBND', 100, 'psse_default';
    'adjust', 'MXTPSS', 100, 'psse_default';
    'adjust', 'MXSWIM', 10, 'psse_default';
};
defs = struct('section', {}, 'name', {}, 'value', {}, 'origin', {});
for k = 1:size(rows, 1)
    defs(k) = struct('section', rows{k, 1}, 'name', rows{k, 2}, ...
        'value', rows{k, 3}, 'origin', rows{k, 4});
end
