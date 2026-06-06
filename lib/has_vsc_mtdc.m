function TorF = has_vsc_mtdc(mpc)
% has_vsc_mtdc - True if a case contains explicit VSC-MTDC data.
% ::
%
%   TORF = HAS_VSC_MTDC(MPC)
%
% Returns true for MATPOWER case structs that include the VSC-MTDC fields
% required by RUNPF_VSC_MTDC and RUNCPF_VSC_MTDC.
%
% See also runpf_vsc_mtdc, runcpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

TorF = isstruct(mpc) && isfield(mpc, 'busdc') && ...
    isfield(mpc, 'branchdc') && isfield(mpc, 'vsc');
