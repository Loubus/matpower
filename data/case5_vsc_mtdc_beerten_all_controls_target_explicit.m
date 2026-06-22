function mpc = case5_vsc_mtdc_beerten_all_controls_target_explicit
% case5_vsc_mtdc_beerten_all_controls_target_explicit - Explicit CPF target.
%
% This is the self-contained CPF target for
% CASE5_VSC_MTDC_BEERTEN_ALL_CONTROLS_TARGET. Loads, generator redispatch,
% VSC set-point changes and dispatch metadata are written directly here.
%
% Target policy represented explicitly:
%   load_scale = 2.0
%   non-slack generator at bus 6 carries 100% of active load increment
%   droop VSC at bus 3 receives 2% of active load increment as HVDC support
%   Qac schedule applies +1 MVAr at bus 2 and +2 MVAr at bus 5
%
% See also case5_vsc_mtdc_beerten_all_controls_explicit,
% runcpf_vsc_mtdc.

%   MATPOWER

%%-----  User configuration and option legend  -----%%
opt = struct();
opt.profile = 'beerten_all_controls_cpf_target';
opt.baseMVA = 100;
opt.load_scale = 2.0;
opt.gen_dispatch_policy = 'participation';
opt.gen_dispatch_bus = 6;
opt.gen_load_share = 1.0;
opt.hvdc_policy = 'droop_scheduled';
opt.hvdc_share = 0.02;
opt.hvdc_dispatch_ac_buses = 3;
opt.hvdc_dispatch_weights = 1;
opt.qac_dispatch_ac_buses = [2; 5];
opt.qac_delta_mvar = [1; 2];
opt.enable_psse_ultc = 1;
opt.enable_psse_switched_shunt = 1;
opt.recommended_pf_method = 'unified';
opt.recommended_cpf_method = 'unified';
opt.ac_modes = struct('VSC_AC_Q', 1, 'VSC_AC_V', 2, ...
    'VSC_AC_PQ', 3, 'VSC_AC_PV', 4);
opt.dc_modes = struct('VSC_DC_VDC', 1, 'VSC_DC_PDC', 2, ...
    'VSC_DC_DROOP', 3);
opt.psse_solver = struct('ACTAPS', 1, 'SWSHNT', 1, ...
    'MXTPSS', 10, 'VCTOLV', 1e-5);

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
    1     0   0   500  -500   1.060   100   1   500  -500   0 0 0 0 0 0 0 0 0 0 0;
    6   205   0   300  -300   1.000   100   1   300     0   0 0 0 0 0 0 0 0 0 0 0;
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
    4   1   1.000   300;
];

%% DC branch data
% fbusdc tbusdc r status
mpc.branchdc = [
    2   3   0.02633   1;
    3   5   0.02337   1;
    2   5   0.03601   1;
    3   4   0.02500   1;
    4   5   0.02500   1;
];

%% VSC data
% acbus busdc status ac_mode dc_mode Pac Qac VacPCC Pdc Vdc Kdroop
% lossA lossB lossC tr_r tr_x tr_b tr_shift tr_rateA tr_rateB tr_rateC
% filter_g filter_b reactor_r reactor_x reactor_b
% reactor_rateA reactor_rateB reactor_rateC
mpc.vsc = [
    2 2 1 1 1  -60.00 -39.00 0.984  58.59 1.008    0 1.1033 0.1999949 0.1466667 0 0.0001 0 0 250 250 250 0 0 0.0009615 0.0399 0 250 250 250;
    3 3 1 2 3   20.68   7.17 1.000 -25.14 1.000 -180 1.1033 0.1999949 0.2222333 0 0.0001 0 0 250 250 250 0 0 0.0000000 0.0392 0 250 250 250;
    5 5 1 3 2   35.00   7.00 0.993 -36.21 0.998    0 1.1033 0.1999949 0.2222333 0 0.0001 0 0 250 250 250 0 0 0.0007850 0.0399 0 250 250 250;
    4 4 1 4 2   15.00   0.00 0.995 -16.00 1.000    0 1.1033 0.1999949 0.2222333 0 0.0001 0 0 250 250 250 0 0 0.0000000 0.0392 0 250 250 250;
];

%% Explicit VSC/HVDC dispatch metadata used by CPF orchestration.
mpc.vsc_hvdc_dispatch = struct( ...
    'policy',              'droop_scheduled', ...
    'delta_pd',            165, ...
    'delta_qd',            40, ...
    'hvdc_share',          0.02, ...
    'delta_hvdc_mw',       3.3, ...
    'weights_used',        1, ...
    'converter_idx',       2, ...
    'ac_buses',            3, ...
    'dc_buses',            3, ...
    'delta_pdc_set',       [0; -3.3; 0; 0], ...
    'qac_policy',          'delta', ...
    'qac_share',           0, ...
    'delta_qac_mvar',      3, ...
    'qac_weights_used',    zeros(0, 1), ...
    'qac_converter_idx',   [1; 3], ...
    'qac_ac_buses',        [2; 5], ...
    'qac_delta_set',       [1; 0; 2; 0], ...
    'affected_converters', [1; 2; 3], ...
    'affected_ac_buses',   [2; 3; 5] );

%%-----  PSS/E Control Metadata  -----%%
mpc = add_explicit_psse_controls(mpc, opt);


function mpc = add_explicit_psse_controls(mpc, opt)
%% SYSTEM-WIDE control options for runpf_psse/runcpf_psse.
mpc.psse.rev = 34;
mpc.psse.system.solver.ACTAPS = opt.psse_solver.ACTAPS;
mpc.psse.system.solver.SWSHNT = opt.psse_solver.SWSHNT;
mpc.psse.system.adjust.MXTPSS = opt.psse_solver.MXTPSS;
mpc.psse.system.newton.VCTOLV = opt.psse_solver.VCTOLV;

%% PSS/E two-winding transformer metadata for the load-side ULTC 4-7.
xf_cols = {'I', 'J', 'K', 'CKT', 'CW', 'CZ', 'CM', 'MAG1', ...
    'MAG2', 'NMETR', 'NAME', 'STAT', 'O1', 'F1', 'O2', 'F2', ...
    'O3', 'F3', 'O4', 'F4', 'R1_2', 'X1_2', 'SBASE1_2', ...
    'WINDV1', 'NOMV1', 'ANG1', ...
    'RATE11', 'RATE21', 'RATE31', 'RATE41', 'RATE51', 'RATE61', ...
    'RATE71', 'RATE81', 'RATE91', 'RATE101', 'RATE111', 'RATE121', ...
    'COD1', 'CONT1', 'RMA1', 'RMI1', 'VMA1', 'VMI1', ...
    'NTP1', 'TAB1', 'CR1', 'CX1', 'CNXA1', 'NOD1', 'WINDV2', 'NOMV2'};
xf_col = struct();
for k = 1:length(xf_cols)
    xf_col.(lower(regexprep(xf_cols{k}, '[^A-Za-z0-9_]', '_'))) = k;
end
xf_num = nan(1, 52);
xf_num([1 2 3 5 6 7 12 21 22 23 24 25 26 27:38 39 40 ...
        41 42 43 44 45 46 47 48 49 50 51 52]) = ...
    [4 7 0 1 1 1 1 ...
        0.005 0.05 100 1.00 0 0 ...
        250 * ones(1, 12) 1 7 1.10 0.90 1.03 0.95 5 0 0 0 0 0 1 0];
mpc.psse.xfmr.two = struct( ...
    'colnames', {xf_cols}, ...
    'num', xf_num, ...
    'txt', {cell(1, 52)}, ...
    'branch_idx', 9, ...
    'col', xf_col );
mpc.psse.xfmr.three = struct( ...
    'colnames', {{}}, ...
    'num', zeros(0, 112), ...
    'txt', {cell(0, 112)}, ...
    'branch_idx', zeros(0, 3), ...
    'col', struct() );

%% PSS/E switched shunt metadata: bus 5 local discrete voltage control.
sw_cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
sw_num = nan(1, 27);
sw_num([1:8 10:12 27]) = [5 1 0 1 1.03 0.95 5 100 0 3 5 0];
mpc.psse.swshunt = struct( ...
    'colnames', {sw_cols}, ...
    'num', sw_num, ...
    'txt', {cell(1, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 );
