function mpc = case5_vsc_mtdc_beerten_droop_target_explicit
% case5_vsc_mtdc_beerten_droop_target_explicit - Explicit CPF target case.
%
% This file is the self-contained CPF target corresponding to
% CASE5_VSC_MTDC_BEERTEN_DROOP_TARGET. It writes the doubled loads, VSC
% set-point changes and VSC/HVDC dispatch metadata directly in the file.
%
% Target policy represented explicitly:
%   load_scale = 2.0
%   total active load increment = 165 MW
%   HVDC scheduled share = 2%, i.e. 3.3 MW
%   droop VSC at bus 3 receives 30% of the active support
%   droop VSC at bus 5 receives 70% of the active support
%   Qac schedule applies +1 MVAr at bus 2 and +2 MVAr at bus 5
%
% See also case5_vsc_mtdc_beerten_droop_explicit, runcpf_vsc_mtdc.

%   MATPOWER

%%-----  User configuration and option legend  -----%%
opt = struct();
opt.profile = 'beerten_droop_cpf_target';
opt.baseMVA = 100;
opt.load_scale = 2.0;
opt.hvdc_policy = 'droop_scheduled';
opt.hvdc_share = 0.02;
opt.hvdc_dispatch_ac_buses = [3; 5];
opt.hvdc_dispatch_weights = [0.30; 0.70];
opt.qac_dispatch_ac_buses = [2; 5];
opt.qac_delta_mvar = [1; 2];
opt.recommended_pf_method = 'unified';
opt.recommended_cpf_method = 'unified';
opt.ac_modes = struct('VSC_AC_Q', 1, 'VSC_AC_V', 2, ...
    'VSC_AC_PQ', 3, 'VSC_AC_PV', 4);
opt.dc_modes = struct('VSC_DC_VDC', 1, 'VSC_DC_PDC', 2, ...
    'VSC_DC_DROOP', 3);

%% MATPOWER Case Format : Version 2
mpc.version = '2';
mpc.explicit_options = opt;

%%-----  Power Flow Data  -----%%
mpc.baseMVA = opt.baseMVA;

%% bus data
% bus_i type Pd Qd Gs Bs area Vm Va baseKV zone Vmax Vmin
mpc.bus = [
    1   3     0    0   0   0   1   1.060   0   230    1   1.1   0.9;
    2   1    40   20   0   0   1   1.000   0   230    1   1.1   0.9;
    3   1    90   30   0   0   1   1.000   0   230    1   1.1   0.9;
    4   1     0    0   0   0   1   1.000   0   230    1   1.1   0.9;
    5   1   120   20   0   0   1   1.000   0   230    1   1.1   0.9;
    6   2     0    0   0   0   1   1.000   0    13.8  1   1.1   0.9;
    7   1    80   10   0   0   1   1.000   0   230    1   1.1   0.9;
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
mpc.vsc = [
    2 2 1 1 1  -60.00 -39.00 0.984  58.59 1.008    0 1.1033 0.1999949 0.1466667 0 0.0001 0 0 150 150 150 0 0 0.0009615 0.0399 0 150 150 150;
    3 3 1 2 3   20.68   7.17 1.000 -22.83 1.000 -180 1.1033 0.1999949 0.2222333 0 0.0001 0 0 150 150 150 0 0 0.0000000 0.0392 0 150 150 150;
    5 5 1 1 3   35.00   7.00 0.993 -38.52 0.998 -280 1.1033 0.1999949 0.2222333 0 0.0001 0 0 150 150 150 0 0 0.0007850 0.0399 0 150 150 150;
];

%% Explicit VSC/HVDC dispatch metadata used by CPF orchestration.
mpc.vsc_hvdc_dispatch = struct( ...
    'policy',              'droop_scheduled', ...
    'delta_pd',            165, ...
    'delta_qd',            40, ...
    'hvdc_share',          0.02, ...
    'delta_hvdc_mw',       3.3, ...
    'weights_used',        [0.30; 0.70], ...
    'converter_idx',       [2; 3], ...
    'ac_buses',            [3; 5], ...
    'dc_buses',            [3; 5], ...
    'delta_pdc_set',       [0; -0.99; -2.31], ...
    'qac_policy',          'delta', ...
    'qac_share',           0, ...
    'delta_qac_mvar',      3, ...
    'qac_weights_used',    zeros(0, 1), ...
    'qac_converter_idx',   [1; 3], ...
    'qac_ac_buses',        [2; 5], ...
    'qac_delta_set',       [1; 0; 2], ...
    'affected_converters', [1; 2; 3], ...
    'affected_ac_buses',   [2; 3; 5] );
