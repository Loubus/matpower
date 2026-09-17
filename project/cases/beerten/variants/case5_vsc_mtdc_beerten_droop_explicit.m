function mpc = case5_vsc_mtdc_beerten_droop_explicit
% case5_vsc_mtdc_beerten_droop_explicit - Explicit 5-bus VSC-MTDC droop case.
%
% This file is a self-contained, documented version of
% CASE5_VSC_MTDC_BEERTEN_DROOP. It intentionally does not call the base case
% or helper builders, so the AC buses, loads, branches, DC grid and VSC
% stations can be inspected and edited directly from this file.
%
% VSC sign convention:
%   Pac > 0 injects active power into the AC grid.
%   Pdc > 0 injects active power into the DC grid.
%   Ploss >= 0 and Pac + Pdc + Ploss = 0 after solution.
%
% The station topology used by RUNPF_VSC_MTDC is explicit:
%   PCC bus -> station transformer -> filter bus -> phase reactor -> VSC.
%
% See also case5_vsc_mtdc_beerten_droop, idx_vsc, runpf_vsc_mtdc,
% runcpf_vsc_mtdc.

%   MATPOWER

%%-----  User configuration and option legend  -----%%
% Keep editable parameters here, before the case matrices. The numeric mode
% codes match IDX_VSC and are repeated here to keep the test case readable.
opt = struct();
opt.profile = 'beerten_droop';
opt.baseMVA = 100;
opt.enable_psse_ultc = 0;
opt.enable_psse_switched_shunt = 0;
opt.recommended_pf_method = 'unified';      % also supports 'sequential'
opt.recommended_cpf_method = 'unified';
opt.ac_modes = struct( ...
    'VSC_AC_Q', 1, ...      % fixed Qac, Pac follows DC-side balance
    'VSC_AC_V', 2, ...      % fixed PCC voltage, Pac follows DC-side balance
    'VSC_AC_PQ', 3, ...     % fixed Pac and Qac
    'VSC_AC_PV', 4 );       % fixed Pac and PCC voltage
opt.dc_modes = struct( ...
    'VSC_DC_VDC', 1, ...    % DC voltage slack, calculated Pdc
    'VSC_DC_PDC', 2, ...    % fixed Pdc
    'VSC_DC_DROOP', 3 );    % Pdc = Pdc_set + Kdroop * (Vdc - Vdc_set)
opt.dc_reference_ac_bus = 2;
opt.droop_ac_buses = [3; 5];
opt.droop_coefficients_MW_per_pu = [-180; -280];

%% MATPOWER Case Format : Version 2
mpc.version = '2';
mpc.explicit_options = opt;

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = opt.baseMVA;

%% bus data
% bus_i type Pd Qd Gs Bs area Vm Va baseKV zone Vmax Vmin
% Bus 4 load is represented behind auxiliary load bus 7 to preserve the
% same physical AC network used by the ULTC/switched-shunt regression case,
% but the PSS/E control metadata is intentionally disabled in this fixture.
mpc.bus = [
    1   3     0    0   0   0   1   1.060   0   230    1   1.1   0.9;
    2   1    20   10   0   0   1   1.000   0   230    1   1.1   0.9;
    3   1    45   15   0   0   1   1.000   0   230    1   1.1   0.9;
    4   1     0    0   0   0   1   1.000   0   230    1   1.1   0.9;
    5   1    60   10   0   0   1   1.000   0   230    1   1.1   0.9;
    6   2     0    0   0   0   1   1.000   0    13.8  1   1.1   0.9;
    7   1    40    5   0   0   1   1.000   0   230    1   1.1   0.9;
];

%% generator data
% bus Pg Qg Qmax Qmin Vg mBase status Pmax Pmin Pc1 Pc2 Qc1min Qc1max
% Qc2min Qc2max ramp_agc ramp_10 ramp_30 ramp_q apf
mpc.gen = [
    1    0   0   500  -500   1.060   100   1   500  -500   0 0 0 0 0 0 0 0 0 0 0;
    6   40   0   300  -300   1.000   100   1   300     0   0 0 0 0 0 0 0 0 0 0 0;
];

%% branch data
% fbus tbus r x b rateA rateB rateC ratio angle status angmin angmax
% Branch 6-2 is the generator-side transformer with a fixed tap.
% Branch 4-7 carries the bus-4 load to the auxiliary load bus.
mpc.branch = [
    1   2   0.020   0.060   0.060   250 250 250   0   0   1  -360 360;
    1   3   0.080   0.240   0.050   250 250 250   0   0   1  -360 360;
    2   3   0.060   0.180   0.040   250 250 250   0   0   1  -360 360;
    2   4   0.060   0.180   0.040   250 250 250   0   0   1  -360 360;
    2   5   0.040   0.120   0.030   250 250 250   0   0   1  -360 360;
    3   4   0.010   0.030   0.020   250 250 250   0   0   1  -360 360;
    4   5   0.080   0.240   0.050   250 250 250   0   0   1  -360 360;
    6   2   0.005   0.050   0.000   250 250 250   1   0   1  -360 360;
    4   7   0.005   0.050   0.000   250 250 250   1   0   1  -360 360;
];

%%-----  VSC-MTDC Data  -----%%
%% DC bus data
% busdc_i status Vdc baseKVdc
mpc.busdc = [
    2   1   1.008   300;
    3   1   1.000   300;
    5   1   0.998   300;
];

%% DC branch data
% fbusdc tbusdc r status
mpc.branchdc = [
    2   3   0.02633   1;
    3   5   0.02337   1;
    2   5   0.03601   1;
];

%% VSC data
% acbus busdc status ac_mode dc_mode Pac Qac VacPCC Pdc Vdc Kdroop
% lossA lossB lossC tr_r tr_x tr_b tr_shift tr_rateA tr_rateB tr_rateC
% filter_g filter_b reactor_r reactor_x reactor_b
% reactor_rateA reactor_rateB reactor_rateC
% VSC 1 at AC bus 2 is the DC-voltage reference and holds fixed Q.
% VSC 2 at AC bus 3 holds AC voltage and uses DC droop.
% VSC 3 at AC bus 5 holds fixed Q and uses DC droop.
mpc.vsc = [
    2 2 1 1 1  -60.00 -40.00 0.984  58.59 1.008    0 1.1033 0.1999949 0.1466667 0 0.0001 0 0 150 150 150 0 0 0.0009615 0.0399 0 150 150 150;
    3 3 1 2 3   20.68   7.17 1.000 -21.84 1.000 -180 1.1033 0.1999949 0.2222333 0 0.0001 0 0 150 150 150 0 0 0.0000000 0.0392 0 150 150 150;
    5 5 1 1 3   35.00   5.00 0.993 -36.21 0.998 -280 1.1033 0.1999949 0.2222333 0 0.0001 0 0 150 150 150 0 0 0.0007850 0.0399 0 150 150 150;
];
