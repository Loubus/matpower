function mpopt = psse_mpx_options(mpopt)
% psse_mpx_options - Enables the PSS/E MP-Core extension.
% ::
%
%   MPOPT = MP.PSSE_MPX_OPTIONS(MPOPT)
%
% Forces MP-Core execution and appends ``mp.xt_psse`` to ``mpopt.exp.mpx``
% when it is not already present.
%
% See also mp.xt_psse, runpf_psse, runcpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

mpopt.exp.use_legacy_core = 0;
if isfield(mpopt.exp, 'mpx') && ~isempty(mpopt.exp.mpx)
    if iscell(mpopt.exp.mpx)
        mpx = mpopt.exp.mpx;
    else
        mpx = { mpopt.exp.mpx };
    end
else
    mpx = {};
end

has_psse = 0;
for k = 1:length(mpx)
    if isa(mpx{k}, 'mp.xt_psse')
        has_psse = 1;
        break;
    end
end
if ~has_psse
    mpx{end+1} = mp.xt_psse();
end
mpopt.exp.mpx = mpx;
