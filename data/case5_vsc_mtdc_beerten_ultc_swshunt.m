function mpc = case5_vsc_mtdc_beerten_ultc_swshunt
% case5_vsc_mtdc_beerten_ultc_swshunt - Beerten VSC-MTDC case with PSS/E controls.
%
% Based on case5_vsc_mtdc_beerten, the 5-bus, 3-terminal VSC-MTDC
% example from:
%
%   J. Beerten, S. Cole, R. Belmans, "A Sequential AC/DC Power Flow
%   Algorithm for Networks Containing Multi-terminal VSC HVDC Systems",
%   IEEE PES General Meeting, 2010.
%
% This variant keeps the original VSC-MTDC data and adds PSS/E-style
% voltage controls on the AC side:
%   - the original bus-4 load is connected behind a two-winding ULTC
%     transformer at auxiliary load bus 7, with ACTAPS enabled;
%   - bus 5 has a local discrete switched shunt, with SWSHNT enabled.
%
% The VSC station model still follows the explicit topology used by
% runpf_vsc_mtdc:
%
%     PCC -> transformer -> filter bus -> phase reactor -> internal VSC
%
% See also case5_vsc_mtdc_beerten, runpf_vsc_mtdc, runpf_psse,
% runcpf_psse.

%   MATPOWER

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1.060	0	230	1	1.1	0.9;
	2	1	20	10	0	0	1	1.000	0	230	1	1.1	0.9;
	3	1	45	15	0	0	1	1.000	0	230	1	1.1	0.9;
	4	1	0	0	0	0	1	1.000	0	230	1	1.1	0.9;
	5	1	60	10	0	0	1	1.000	0	230	1	1.1	0.9;
	6	2	0	0	0	0	1	1.000	0	13.8	1	1.1	0.9;
	7	1	40	5	0	0	1	1.000	0	230	1	1.1	0.9;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	0	0	500	-500	1.060	100	1	500	-500	0	0	0	0	0	0	0	0	0	0	0;
	6	40	0	300	-300	1.000	100	1	300	0	0	0	0	0	0	0	0	0	0	0	0;
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.02	0.06	0.06	250	250	250	0	0	1	-360	360;
	1	3	0.08	0.24	0.05	250	250	250	0	0	1	-360	360;
	2	3	0.06	0.18	0.04	250	250	250	0	0	1	-360	360;
	2	4	0.06	0.18	0.04	250	250	250	0	0	1	-360	360;
	2	5	0.04	0.12	0.03	250	250	250	0	0	1	-360	360;
	3	4	0.01	0.03	0.02	250	250	250	0	0	1	-360	360;
	4	5	0.08	0.24	0.05	250	250	250	0	0	1	-360	360;
	6	2	0.005	0.05	0.00	250	250	250	1.00	0	1	-360	360;
	4	7	0.005	0.05	0.00	250	250	250	1.00	0	1	-360	360;
];

%%-----  VSC-MTDC Data  -----%%
%% DC bus data
%	busdc_i	status	Vdc	baseKVdc
mpc.busdc = [
	2	1	1.008	300;
	3	1	1.000	300;
	5	1	0.998	300;
];

%% DC branch data
%	fbusdc	tbusdc	r	status
mpc.branchdc = [
	2	3	0.02633	1;
	3	5	0.02337	1;
	2	5	0.03601	1;
];

%% VSC data
%	acbus	busdc	status	ac_mode	dc_mode	Pac	Qac	VacPCC	Pdc	Vdc	Kdroop	lossA	lossB	lossC	tr_r	tr_x	tr_b	tr_shift	tr_rateA	tr_rateB	tr_rateC	filter_g	filter_b	reactor_r	reactor_x	reactor_b	reactor_rateA	reactor_rateB	reactor_rateC
mpc.vsc = [
	2	2	1	3	2	-60.00	-40.00	0.984	58.59	1.008	0	1.1033	0.1999949	0.1466667	0	0.0001	0	0	150	150	150	0	0	0.0009615	0.0399	0	150	150	150;
	3	3	1	2	1	20.68	7.17	1.000	-21.84	1.000	0	1.1033	0.1999949	0.2222333	0	0.0001	0	0	150	150	150	0	0	0.0000000	0.0392	0	150	150	150;
	5	5	1	3	2	35.00	5.00	0.993	-36.21	0.998	0	1.1033	0.1999949	0.2222333	0	0.0001	0	0	150	150	150	0	0	0.0007850	0.0399	0	150	150	150;
];

%%-----  PSS/E Control Metadata  -----%%
%% SYSTEM-WIDE control options for runpf_psse/runcpf_psse.
mpc.psse.rev = 34;
mpc.psse.system.solver.ACTAPS = 1;
mpc.psse.system.solver.SWSHNT = 1;
mpc.psse.system.adjust.MXTPSS = 10;
mpc.psse.system.newton.VCTOLV = 1e-5;

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
