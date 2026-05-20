function t_mpxt_psse(quiet)
% t_mpxt_psse - Tests mp.xt_psse extension.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 1
    quiet = 0;
end

num_tests = 48;

t_begin(num_tests, quiet);

[~, ~, ~, ~, ~, ~, ~, ~, ~, BS, ~, VM] = idx_bus;
[~, ~, BR_R, BR_X, ~, ~, ~, ~, TAP] = idx_brch;
[~, ~, QG] = idx_gen;
mpopt = mpoption('verbose', 0, 'out.all', 0);

%% runpf_psse uses PSS/E task and matches runpf without PSS/E data
r0 = runpf('case9', mpopt);
r = runpf_psse('case9', mpopt);
t_ok(r.success, 'runpf_psse(case9) success');
t_ok(isa(r.task, 'mp.task_pf_psse'), 'runpf_psse uses mp.task_pf_psse');
t_is(r.bus(:, VM), r0.bus(:, VM), 10, 'runpf_psse matches runpf VM without psse data');
t_is(r.gen(:, QG), r0.gen(:, QG), 10, 'runpf_psse matches runpf QG without psse data');

%% MODSW = 1, BINIT = 0, creates a shunt row through data model rebuild
mpc = psse_case9_swshunt(1, 1, 0, 1.02, 1.01, 9, 0, [2 25], 2);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'MODSW=1 success');
t_is(r.psse.swshunt.num(1, 10), 25, 10, 'MODSW=1 switched one capacitor step');
t_is(r.bus(9, BS), 25, 10, 'MODSW=1 updates bus BS from BINIT=0');
t_ok(r.psse.swshunt.control.inside_band == 1, 'MODSW=1 reaches voltage band');

mpc = psse_case2_swshunt_discrete();
r = runpf_psse(mpc, mpopt);
t_is(r.psse.swshunt.control.num_adjustments, 6, 10, ...
    'MODSW=1 ADJM=0 advances one block per adjustment');

%% SWSHNT = 0 disables automatic control
mpc = psse_case9_swshunt(1, 1, 0, 1.02, 1.01, 9, 0, [2 25], 0);
r = runpf_psse(mpc, mpopt);
t_is(r.psse.swshunt.num(1, 10), 0, 10, 'SWSHNT=0 leaves BINIT unchanged');
t_is(r.bus(9, BS), 0, 10, 'SWSHNT=0 leaves bus BS unchanged');
t_ok(~r.psse.swshunt.control.enabled, 'SWSHNT=0 report disabled');

%% MODSW = 0 and STAT = 0 remain fixed
mpc = psse_case9_swshunt(0, 1, 15, 1.02, 1.01, 9, 15, [2 25], 2);
r = runpf_psse(mpc, mpopt);
t_is(r.psse.swshunt.num(1, 10), 15, 10, 'MODSW=0 leaves BINIT fixed');
t_is(r.bus(9, BS), 15, 10, 'MODSW=0 leaves bus BS fixed');

mpc = psse_case9_swshunt(1, 0, 25, 1.02, 1.01, 9, 0, [2 25], 2);
r = runpf_psse(mpc, mpopt);
t_is(r.bus(9, BS), 0, 10, 'STAT=0 contributes no bus BS');
t_is(r.psse.swshunt.control.controllable, 0, 10, 'STAT=0 is not controllable');

%% MODSW = 2 is continuous within physical range
mpc = psse_case9_swshunt(2, 1, 0, 1.02, 1.02, 9, 0, [1 40], 2);
r = runpf_psse(mpc, mpopt);
b = r.psse.swshunt.num(1, 10);
t_ok(b > 0 && b < 40, 'MODSW=2 uses continuous B within range');

%% multiple shunts regulating the same bus are controlled as a group
rows = [
    8 1 0 1 1.02 1.01 9 100 0 0 1 25 0
    9 1 0 1 1.02 1.01 9 100 0 0 1 25 0
];
mpc = psse_case9_swshunts(rows, 2, 10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'grouped RMPCT success');
t_is(r.psse.swshunt.control.num_groups, 1, 10, 'grouped RMPCT has one regulated bus group');
t_is(r.psse.swshunt.control.multi_shunt_groups, 1, 10, 'grouped RMPCT reports multi-shunt group');
t_is(r.psse.swshunt.control.max_group_rmpct_sum, 200, 10, 'grouped RMPCT preserves literal sum');
t_is(r.psse.swshunt.num(:, 10), [25; 25], 10, 'grouped RMPCT moves both shunts together');

%% repeated BINIT states are resolved by selecting the best visited state
rows = [9 1 0 1 1.03 1.03 9 100 0 0 1 50 0];
mpc = psse_case9_swshunts(rows, 2, 10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'cycle memory success');
t_ok(r.psse.swshunt.control.cycle_detected, 'cycle memory detects repeated BINIT state');
t_ok(r.psse.swshunt.control.cycle_resolved, 'cycle memory resolves repeated BINIT state');
t_ok(r.psse.swshunt.control.cycle_resolution_changes > 0, ...
    'cycle memory applies best visited BINIT');

%% PSS/E transformer tap control is gated by ACTAPS and COD
mpc = psse_case2_xfmr_tap(1, 1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'COD=1 transformer tap success');
t_is(r.branch(1, TAP), 0.95, 10, 'COD=1 transformer tap moves one step');
t_is(r.psse.xfmr.two.num(1, 24), 0.95, 10, 'COD=1 transformer WINDV updated');
t_ok(r.psse.xfmr.control.inside_band == 1, 'COD=1 transformer reaches voltage band');

mpc = psse_case2_xfmr_tab();
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TAB transformer correction success');
t_is(r.branch(1, TAP), 0.95, 10, 'TAB transformer tap moves one step');
t_is(r.branch(1, [BR_R BR_X]), [0.0095 0.095], 10, 'TAB updates branch R/X from corrected tap');
t_is(r.psse.xfmr.control.tab_corrected, 1, 10, 'TAB correction reported');

mpc = psse_case3_xfmr_tap_remote();
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.05, 10, 'remote transformer tap reaches voltage band');
t_ok(r.psse.xfmr.control.inside_band == 1, 'remote transformer reaches voltage band');

mpc = psse_case3_xfmr_tap_remote_limit();
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.10, 10, 'remote transformer tap reaches upper limit');
t_is(r.psse.xfmr.control.at_max, 1, 10, 'remote transformer upper limit reported');

mpc = psse_case3_xfmr_tap_remote_cont_pos();
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 0.95, 10, 'positive CONT remote transformer tap matches PSS/E direction');
t_ok(r.psse.xfmr.control.inside_band == 1, 'positive CONT remote transformer reaches voltage band');

mpc = psse_case2_xfmr_tap(1, 1, 2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 0.95, 10, 'positive CONT terminal transformer tap matches PSS/E direction');
t_ok(r.psse.xfmr.control.inside_band == 1, 'positive CONT terminal transformer reaches voltage band');

mpc = psse_case2_xfmr_tap(0, 1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.00, 10, 'ACTAPS=0 leaves transformer tap fixed');
t_ok(~r.psse.xfmr.control.enabled, 'ACTAPS=0 report disabled');

mpc = psse_case2_xfmr_tap(1, -1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.00, 10, 'COD=-1 suppresses automatic tap adjustment');
t_is(r.psse.xfmr.control.suppressed_auto, 1, 10, 'COD=-1 reported suppressed');

mpc = psse_case2_xfmr_tap(1, 1, -2, 0.90, 1.09, 1.08, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 0.90, 10, 'transformer tap lower limit is respected');
t_is(r.psse.xfmr.control.at_min, 1, 10, 'transformer lower limit reported');

t_end;

function mpc = psse_case9_swshunt(modsw, stat, binit, vswhi, vswlo, swreg, bus_bs, block, swshnt)
[~, ~, ~, ~, ~, ~, ~, ~, ~, BS] = idx_bus;
mpc = loadcase('case9');
mpc.bus(9, BS) = bus_bs;
cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
row = nan(1, 27);
row([1:8 10:12 27]) = [9 modsw 0 stat vswhi vswlo swreg 100 binit block 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = swshnt;
mpc.psse.system.adjust.MXTPSS = 10;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', row, ...
    'txt', {cell(1, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case9_swshunts(rows, swshnt, maxtpss)
[~, ~, ~, ~, ~, ~, ~, ~, ~, BS] = idx_bus;
mpc = loadcase('case9');
mpc.bus(:, BS) = 0;
cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
nr = size(rows, 1);
num = nan(nr, 27);
num(:, [1:12 27]) = rows;
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = swshnt;
mpc.psse.system.adjust.MXTPSS = maxtpss;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {cell(nr, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case2_swshunt_discrete()
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 70 45 0 0 1 0.96 0 230 1 1.1 0.9
];
mpc.gen = [
    1 70 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.02 0.15 0 200 200 200 0 0 1 -360 360
];
cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
row = nan(1, 27);
row([1:8 10:14 27]) = [2 1 0 1 1.03 0.99 2 100 0 6 10 0 0 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = 2;
mpc.psse.system.adjust.MXTPSS = 20;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', row, ...
    'txt', {cell(1, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case2_xfmr_tap(actaps, cod, cont, tap, vma, vmi, rma, rmi, ntp, pd, qd)
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 pd qd 0 0 1 1.00 0 115 1 1.1 0.9
];
mpc.gen = [
    1 pd 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.01 0.10 0 250 250 250 tap 0 1 -360 360
];

cols = {'I', 'J', 'K', 'CKT', 'CW', 'CZ', 'CM', 'MAG1', ...
    'MAG2', 'NMETR', 'NAME', 'STAT', 'O1', 'F1', 'O2', 'F2', ...
    'O3', 'F3', 'O4', 'F4', 'R1_2', 'X1_2', 'SBASE1_2', ...
    'WINDV1', 'NOMV1', 'ANG1', ...
    'RATE11', 'RATE21', 'RATE31', 'RATE41', 'RATE51', 'RATE61', ...
    'RATE71', 'RATE81', 'RATE91', 'RATE101', 'RATE111', 'RATE121', ...
    'COD1', 'CONT1', 'RMA1', 'RMI1', 'VMA1', 'VMI1', ...
    'NTP1', 'TAB1', 'CR1', 'CX1', 'CNXA1', 'NOD1', 'WINDV2', 'NOMV2'};
col = struct();
for k = 1:length(cols)
    col.(lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'))) = k;
end

num = nan(1, 52);
num([1 2 3 5 6 7 12 21 22 23 24 25 26 27:38 39 40 ...
        41 42 43 44 45 46 47 48 49 50 51 52]) = ...
    [1 2 0 1 1 1 1 0.01 0.10 100 tap 0 0 zeros(1, 12) ...
        cod cont rma rmi vma vmi ntp 0 0 0 0 0 1 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.ACTAPS = actaps;
mpc.psse.system.adjust.MXTPSS = 10;
mpc.psse.xfmr.two = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {cell(1, 52)}, ...
    'branch_idx', 1, ...
    'col', col ...
);
mpc.psse.xfmr.three = struct( ...
    'colnames', {{}}, ...
    'num', zeros(0, 112), ...
    'txt', {cell(0, 112)}, ...
    'branch_idx', zeros(0, 3), ...
    'col', struct() ...
);

function mpc = psse_case2_xfmr_tab()
mpc = psse_case2_xfmr_tap(1, 1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
mpc.psse.xfmr.two.num(1, 46) = 1;
mpc.psse.xfmr.two.tab_applied = true;
mpc.psse.xfmr.two.tab_factor = complex(1);
mpc.psse.xfmr.two.nominal_rx = mpc.branch(1, [3 4]);
mpc.psse.impcor = struct( ...
    'colnames', {{'I', 'T', 'RE', 'IM'}}, ...
    'num', [1 0.90 0.90 0; 1 1.10 1.10 0], ...
    'txt', {cell(2, 4)} ...
);

function mpc = psse_case3_xfmr_tap_remote()
mpc = psse_case2_xfmr_tap(1, 1, -3, 1.00, 0.98, 0.95, 1.1, 0.9, 5, 0, 0);
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 0 0 0 0 1 1.00 0 115 1 1.1 0.9
    3 1 80 35 0 0 1 1.00 0 115 1 1.1 0.9
];
mpc.gen(1, 2) = 80;
mpc.branch = [
    2 1 0.01 0.10 0 250 250 250 1.00 0 1 -360 360
    2 3 0.01 0.08 0 250 250 250 0 0 1 -360 360
];
mpc.psse.xfmr.two.num(1, 1:2) = [2 1];

function mpc = psse_case3_xfmr_tap_remote_limit()
mpc = psse_case3_xfmr_tap_remote();
mpc.branch = [
    1 2 0.01 0.10 0 250 250 250 1.00 0 1 -360 360
    2 3 0.01 0.08 0 250 250 250 0 0 1 -360 360
];
mpc.psse.xfmr.two.num(1, 1:2) = [1 2];

function mpc = psse_case3_xfmr_tap_remote_cont_pos()
mpc = psse_case3_xfmr_tap_remote_limit();
mpc.psse.xfmr.two.num(1, 40) = 3;
