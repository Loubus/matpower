function c = idx_vsc
% idx_vsc - Defines constants for named column indices to ``vsc`` matrix.
% ::
%
%   Example:
%
%   c = idx_vsc;
%
%   Some examples of usage, after defining the constants using the line above,
%   are:
%
%    mpc.vsc(1, c.DC_MODE) = c.VSC_DC_VDC;  % make VSC 1 the DC voltage slack
%    mpc.vsc(2, c.AC_MODE) = c.VSC_AC_Q;    % use fixed Qac control
%
%   Sign convention for each VSC converter:
%
%     Pac > 0 is active power injection into the AC network.
%     Pdc > 0 is active power injection into the DC network.
%     Ploss >= 0 and Pac + Pdc + Ploss = 0.
%
%   The index, name and meaning of each column of the vsc matrix is given
%   below. The model is exclusive to VSC-MTDC power flow and CPF. Capability
%   curves are handled as post-solve audits or TESIS-style active-set
%   enforcement controlled by MPOPT.VSC_MTDC and optional MPC.VSC_CAPABILITY
%   metadata; they are not additional VSC matrix columns and are not OPF
%   constraints. The model does not include LCC converters or converter type
%   switching.
%
%   columns 1-29 must be included in input matrix (in case file)
%    1  VSC_BUS          PCC AC bus number
%    2  BUSDC            connected DC bus number
%    3  VSC_STATUS       initial VSC status, 1 - in service, 0 - out of service
%    4  AC_MODE          AC control mode code
%    5  DC_MODE          DC control mode code
%    6  PAC_SET          active power set point or initial value (MW)
%    7  QAC_SET          reactive power set point (MVAr)
%    8  VAC_SET          PCC voltage set point for V modes, initial value otherwise (p.u.)
%    9  PDC_SET          DC power set point (MW)
%   10  VDC_SET          DC voltage set point (p.u.)
%   11  KDROOP           DC droop coefficient, MW/p.u., Pdc = Pdc_set + Kdroop * (Vdc - Vdc_set)
%   12  LOSS_A           constant converter loss coefficient (MW)
%   13  LOSS_B           linear converter loss coefficient (MW/p.u. current)
%   14  LOSS_C           quadratic converter loss coefficient (MW/p.u. current^2)
%   15  TR_R             transformer resistance (p.u.)
%   16  TR_X             transformer reactance (p.u.)
%   17  TR_B             transformer total charging susceptance (p.u.)
%   18  TR_SHIFT         transformer phase shift angle (degrees)
%   19  TR_RATE_A        transformer long term MVA rating
%   20  TR_RATE_B        transformer short term MVA rating
%   21  TR_RATE_C        transformer emergency MVA rating
%   22  FILTER_G         filter shunt conductance (p.u.)
%   23  FILTER_B         filter shunt susceptance (p.u.)
%   24  REACTOR_R        phase reactor resistance (p.u.)
%   25  REACTOR_X        phase reactor reactance (p.u.)
%   26  REACTOR_B        phase reactor total charging susceptance (p.u.)
%   27  REACTOR_RATE_A   phase reactor long term MVA rating
%   28  REACTOR_RATE_B   phase reactor short term MVA rating
%   29  REACTOR_RATE_C   phase reactor emergency MVA rating
%
%   columns 30-44 are added to matrix after power flow solution
%   they are typically not present in the input matrix
%   30  PAC              active power injection into AC network (MW)
%   31  QAC              reactive power injection into AC network (MVAr)
%   32  PDC              active power injection into DC network (MW)
%   33  VDC              DC voltage magnitude (p.u.)
%   34  VAC_PCC          AC voltage magnitude at PCC bus (p.u.)
%   35  VAC_FILTER       AC voltage magnitude at filter bus (p.u.)
%   36  VAC_INTERNAL     AC voltage magnitude at internal VSC bus (p.u.)
%   37  PLOSS            converter loss (MW)
%   38  PTR_LOSS         transformer real power loss (MW)
%   39  PREACTOR_LOSS    phase reactor real power loss (MW)
%   40  IS_DC_SLACK      1 if VSC is a DC voltage slack, 0 otherwise
%   41  FILTER_BUS       generated filter AC bus number
%   42  INTERNAL_BUS     generated internal VSC AC bus number
%   43  TR_BRANCH        generated transformer branch row
%   44  REACTOR_BRANCH   generated phase reactor branch row
%
%   AC control mode codes:
%    1  VSC_AC_Q         fixed Qac, Pac follows the DC-side balance
%    2  VSC_AC_V         fixed PCC Vac, Pac follows the DC-side balance
%    3  VSC_AC_PQ        fixed Pac and Qac
%    4  VSC_AC_PV        fixed Pac and PCC Vac
%
%   DC control mode codes:
%    1  VSC_DC_VDC       DC voltage slack, fixed Vdc and calculated Pdc
%    2  VSC_DC_PDC       fixed Pdc
%    3  VSC_DC_DROOP     Pdc = Pdc_set + Kdroop * (Vdc - Vdc_set)
%
% See also idx_busdc, idx_branchdc, runpf_vsc_mtdc, runcpf_vsc_mtdc,
% check_vsc_capability.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%% define the indices and mode codes
c = struct( ...
    'VSC_BUS',          1, ... %% PCC AC bus number
    'BUSDC',            2, ... %% connected DC bus number
    'VSC_STATUS',       3, ... %% initial VSC status, 1 - in service, 0 - out of service
    'AC_MODE',          4, ... %% AC control mode code
    'DC_MODE',          5, ... %% DC control mode code
    'PAC_SET',          6, ... %% active power set point or initial value (MW)
    'QAC_SET',          7, ... %% reactive power set point (MVAr)
    'VAC_SET',          8, ... %% PCC voltage set point for V modes, initial value otherwise (p.u.)
    'PDC_SET',          9, ... %% DC power set point (MW)
    'VDC_SET',         10, ... %% DC voltage set point (p.u.)
    'KDROOP',          11, ... %% DC droop coefficient (MW/p.u.)
    'LOSS_A',          12, ... %% constant converter loss coefficient (MW)
    'LOSS_B',          13, ... %% linear converter loss coefficient (MW/p.u. current)
    'LOSS_C',          14, ... %% quadratic converter loss coefficient (MW/p.u. current^2)
    'TR_R',            15, ... %% transformer resistance (p.u.)
    'TR_X',            16, ... %% transformer reactance (p.u.)
    'TR_B',            17, ... %% transformer total charging susceptance (p.u.)
    'TR_SHIFT',        18, ... %% transformer phase shift angle (degrees)
    'TR_RATE_A',       19, ... %% transformer long term MVA rating
    'TR_RATE_B',       20, ... %% transformer short term MVA rating
    'TR_RATE_C',       21, ... %% transformer emergency MVA rating
    'FILTER_G',        22, ... %% filter shunt conductance (p.u.)
    'FILTER_B',        23, ... %% filter shunt susceptance (p.u.)
    'REACTOR_R',       24, ... %% phase reactor resistance (p.u.)
    'REACTOR_X',       25, ... %% phase reactor reactance (p.u.)
    'REACTOR_B',       26, ... %% phase reactor total charging susceptance (p.u.)
    'REACTOR_RATE_A',  27, ... %% phase reactor long term MVA rating
    'REACTOR_RATE_B',  28, ... %% phase reactor short term MVA rating
    'REACTOR_RATE_C',  29, ... %% phase reactor emergency MVA rating
    'PAC',             30, ... %% active power injection into AC network (MW)
    'QAC',             31, ... %% reactive power injection into AC network (MVAr)
    'PDC',             32, ... %% active power injection into DC network (MW)
    'VDC',             33, ... %% DC voltage magnitude (p.u.)
    'VAC_PCC',         34, ... %% AC voltage magnitude at PCC bus (p.u.)
    'VAC_FILTER',      35, ... %% AC voltage magnitude at filter bus (p.u.)
    'VAC_INTERNAL',    36, ... %% AC voltage magnitude at internal VSC bus (p.u.)
    'PLOSS',           37, ... %% converter loss (MW)
    'PTR_LOSS',        38, ... %% transformer real power loss (MW)
    'PREACTOR_LOSS',   39, ... %% phase reactor real power loss (MW)
    'IS_DC_SLACK',     40, ... %% 1 if VSC is a DC voltage slack, 0 otherwise
    'FILTER_BUS',      41, ... %% generated filter AC bus number
    'INTERNAL_BUS',    42, ... %% generated internal VSC AC bus number
    'TR_BRANCH',       43, ... %% generated transformer branch row
    'REACTOR_BRANCH',  44, ... %% generated phase reactor branch row
    'VSC_AC_Q',         1, ... %% fixed Qac, Pac follows the DC-side balance
    'VSC_AC_V',         2, ... %% fixed PCC Vac, Pac follows the DC-side balance
    'VSC_AC_PQ',        3, ... %% fixed Pac and Qac
    'VSC_AC_PV',        4, ... %% fixed Pac and PCC Vac
    'VSC_DC_VDC',       1, ... %% DC voltage slack, fixed Vdc and calculated Pdc
    'VSC_DC_PDC',       2, ... %% fixed Pdc
    'VSC_DC_DROOP',     3  );  %% droop Pdc = Pdc_set + Kdroop * (Vdc - Vdc_set)
