function report = check_capability_limits(results, opt)
% check_capability_limits - Post-solve audit for generator and VSC capability.
% ::
%
%   REPORT = CHECK_CAPABILITY_LIMITS(RESULTS)
%   REPORT = CHECK_CAPABILITY_LIMITS(RESULTS, OPT)
%
%   Evaluates conventional generators and VSC converters after a PF/CPF
%   solution, returning the projected/saturated point that would be used by a
%   TESIS-style post-solve saturation layer. This helper does not modify
%   RESULTS, does not run OPF and does not change bus or converter controls.
%   Active-set enforcement is performed by RUNPF_VSC_MTDC/RUNCPF_VSC_MTDC
%   when the corresponding MPOPT.VSC_MTDC capability options are enabled.
%
% See also check_gen_capability, check_vsc_capability, runpf_vsc_mtdc,
% runcpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 2 || isempty(opt)
    opt = struct();
end

gen = check_gen_capability(results, opt);
vsc = check_vsc_capability(results, opt);

report = struct( ...
    'type',        'capability', ...
    'gen',         gen, ...
    'vsc',         vsc, ...
    'count',       gen.count + vsc.count, ...
    'violations',  gen.violations + vsc.violations );
