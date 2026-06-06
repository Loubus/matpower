function mpc = case5_vsc_mtdc_3term
% case5_vsc_mtdc_3term - 5-bus AC case with a 3-terminal VSC-MTDC grid.
%
% Please see caseformat, idx_busdc, idx_branchdc and idx_vsc for details
% on the case file format.
%
% See also runpf_vsc_mtdc.

%   MATPOWER

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1	0	230	1	1.1	0.9;
	2	1	35	12	0	0	1	1	0	230	1	1.1	0.9;
	3	1	30	10	0	0	1	1	0	230	1	1.1	0.9;
	4	1	45	15	0	0	1	1	0	230	1	1.1	0.9;
	5	1	25	8	0	0	1	1	0	230	1	1.1	0.9;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	150	0	400	-400	1	100	1	400	0	0	0	0	0	0	0	0	0	0	0	0;
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.010	0.080	0.020	200	200	200	0	0	1	-360	360;
	1	3	0.012	0.090	0.025	200	200	200	0	0	1	-360	360;
	2	4	0.015	0.100	0.030	200	200	200	0	0	1	-360	360;
	3	4	0.018	0.110	0.030	200	200	200	0	0	1	-360	360;
	4	5	0.012	0.085	0.020	200	200	200	0	0	1	-360	360;
	2	5	0.020	0.130	0.025	200	200	200	0	0	1	-360	360;
];

%%-----  VSC-MTDC Data  -----%%
%% DC bus data
%	busdc_i	status	Vdc	baseKVdc
mpc.busdc = [
	1	1	1.000	320;
	2	1	1.000	320;
	3	1	1.000	320;
];

%% DC branch data
%	fbusdc	tbusdc	r	status
mpc.branchdc = [
	1	2	0.015	1;
	2	3	0.012	1;
	1	3	0.020	1;
];

%% VSC data
%	acbus	busdc	status	ac_mode	dc_mode	Pac	Qac	VacPCC	Pdc	Vdc	Kdroop	lossA	lossB	lossC	tr_r	tr_x	tr_b	tr_shift	tr_rateA	tr_rateB	tr_rateC	filter_g	filter_b	reactor_r	reactor_x	reactor_b	reactor_rateA	reactor_rateB	reactor_rateC
mpc.vsc = [
	2	1	1	2	1	0	0	1.010	0	1.000	0	0.25	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
	4	2	1	1	2	0	0	1.000	35	1.000	0	0.20	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
	5	3	1	1	2	0	0	1.000	20	1.000	0	0.20	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
	3	2	0	1	2	0	0	1.000	5	1.000	0	0.20	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
];
