function c = idx_branchdc
% idx_branchdc - Defines constants for named column indices to ``branchdc`` matrix.
% ::
%
%   Example:
%
%   c = idx_branchdc;
%
%   Some examples of usage, after defining the constants using the line above,
%   are:
%
%    mpc.branchdc(2, c.BRDC_STATUS) = 0;       % take DC branch 2 out of service
%    Ploss = branchdc(:, c.PFDC) + branchdc(:, c.PTDC); % DC branch losses
%
%   The index, name and meaning of each column of the branchdc matrix is given
%   below:
%
%   columns 1-4 must be included in input matrix (in case file)
%    1  F_BUSDC      f, "from" DC bus number
%    2  T_BUSDC      t,  "to"  DC bus number
%    3  BRDC_R       DC branch resistance (p.u.)
%    4  BRDC_STATUS  initial DC branch status, 1 - in service, 0 - out of service
%
%   columns 5-8 are added to matrix after power flow solution
%   they are typically not present in the input matrix
%    5  PFDC         MW injected at "from" end of DC branch
%    6  PTDC         MW injected at  "to"  end of DC branch
%    7  IFDC         current injected at "from" end of DC branch (p.u.)
%    8  ITDC         current injected at  "to"  end of DC branch (p.u.)
%
% See also idx_busdc, idx_vsc, makeGdc, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%% define the indices
c = struct( ...
    'F_BUSDC',      1, ... %% f, "from" DC bus number
    'T_BUSDC',      2, ... %% t,  "to"  DC bus number
    'BRDC_R',       3, ... %% DC branch resistance (p.u.)
    'BRDC_STATUS',  4, ... %% initial DC branch status, 1 - in service, 0 - out of service
    'PFDC',         5, ... %% MW injected at "from" end of DC branch
    'PTDC',         6, ... %% MW injected at  "to"  end of DC branch
    'IFDC',         7, ... %% current injected at "from" end of DC branch (p.u.)
    'ITDC',         8  );  %% current injected at  "to"  end of DC branch (p.u.)
