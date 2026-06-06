function c = idx_busdc
% idx_busdc - Defines constants for named column indices to ``busdc`` matrix.
% ::
%
%   Example:
%
%   c = idx_busdc;
%
%   Some examples of usage, after defining the constants using the line above,
%   are:
%
%    Vdc = mpc.busdc(2, c.VDC);       % get the DC voltage at bus 2
%    mpc.busdc(3, c.BUSDC_STATUS) = 0; % take DC bus 3 out of service
%
%   The index, name and meaning of each column of the busdc matrix is given
%   below:
%
%   columns 1-4 must be included in input matrix (in case file)
%    1  BUSDC_I       DC bus number (positive integer)
%    2  BUSDC_STATUS  initial DC bus status, 1 - in service, 0 - out of service
%    3  VDC           DC voltage magnitude (p.u.)
%    4  BASE_KVDC     base DC voltage (kV)
%
%   columns 5-6 are added to matrix after power flow solution
%   they are typically not present in the input matrix
%    5  PDC           net converter power injection at DC bus (MW)
%    6  IDC           net current injection from DC bus into DC network (p.u.)
%
% See also idx_branchdc, idx_vsc, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%% define the indices
c = struct( ...
    'BUSDC_I',       1, ... %% DC bus number
    'BUSDC_STATUS',  2, ... %% initial DC bus status, 1 - in service, 0 - out of service
    'VDC',           3, ... %% DC voltage magnitude (p.u.)
    'BASE_KVDC',     4, ... %% base DC voltage (kV)
    'PDC',           5, ... %% net converter power injection at DC bus (MW)
    'IDC',           6  );  %% net current injection from DC bus into DC network (p.u.)
