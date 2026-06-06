function mpc = case3_vsc_mtdc_2term
% case3_vsc_mtdc_2term - 3-bus AC case with a 2-terminal VSC-MTDC link.
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
	2	1	70	30	0	0	1	1	0	230	1	1.1	0.9;
	3	1	60	20	0	0	1	1	0	230	1	1.1	0.9;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	140	0	300	-300	1	100	1	300	0	0	0	0	0	0	0	0	0	0	0	0;
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.010	0.085	0.020	150	150	150	0	0	1	-360	360;
	1	3	0.012	0.092	0.025	150	150	150	0	0	1	-360	360;
	2	3	0.018	0.120	0.030	150	150	150	0	0	1	-360	360;
];

%%-----  VSC-MTDC Data  -----%%
%% DC bus data
%	busdc_i	status	Vdc	baseKVdc
mpc.busdc = [
	1	1	1.000	320;
	2	1	1.000	320;
];

%% DC branch data
%	fbusdc	tbusdc	r	status
mpc.branchdc = [
	1	2	0.010	1;
	1	2	0.001	0;
];

%% VSC data
%	acbus	busdc	status	ac_mode	dc_mode	Pac	Qac	VacPCC	Pdc	Vdc	Kdroop	lossA	lossB	lossC	tr_r	tr_x	tr_b	tr_shift	tr_rateA	tr_rateB	tr_rateC	filter_g	filter_b	reactor_r	reactor_x	reactor_b	reactor_rateA	reactor_rateB	reactor_rateC
mpc.vsc = [
	2	1	1	1	1	0	0	1.000	0	1.000	0	0.20	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
	3	2	1	1	2	0	0	1.000	50	1.000	0	0.20	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
	3	2	0	1	2	0	0	1.000	10	1.000	0	0.20	0.10	0.05	0.001	0.010	0.001	0	100	100	100	0	0.020	0.001	0.015	0.001	100	100	100;
];
