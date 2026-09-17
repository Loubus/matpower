function mpc = case5_matacdc_directional
%CASE5_MATACDC_DIRECTIONAL

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1.06	0	345	1	1.1	0.9;
	2	2	20	10	0	0	1	1	0	345	1	1.1	0.9;
	3	1	45	15	0	0	1	1	0	345	1	1.1	0.9;
	4	1	40	5	0	0	1	1	0	345	1	1.1	0.9;
	5	1	60	10	0	0	1	1	0	345	1	1.1	0.9;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	0	0	500	-500	1.06	100	1	250	10	0	0	0	0	0	0	0	0	0	0	0;
	2	40	0	300	-300	1	100	1	300	10	0	0	0	0	0	0	0	0	0	0	0;
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.02	0.06	0.06	100	100	100	0	0	1	-360	360;
	1	3	0.08	0.24	0.05	100	100	100	0	0	1	-360	360;
	2	3	0.06	0.18	0.04	100	100	100	0	0	1	-360	360;
	2	4	0.06	0.18	0.04	100	100	100	0	0	1	-360	360;
	2	5	0.04	0.12	0.03	100	100	100	0	0	1	-360	360;
	3	4	0.01	0.03	0.02	100	100	100	0	0	1	-360	360;
	4	5	0.08	0.24	0.05	100	100	100	0	0	1	-360	360;
];

%%-----  VSC-MTDC Data  -----%%
%% DC bus data
%	busdc_i	status	Vdc	baseKVdc
mpc.busdc = [
	1	1	1	345;
	2	1	1	345;
	3	1	1	345;
];

%% DC branch data
%	fbusdc	tbusdc	r	status
mpc.branchdc = [
	1	2	0.026	1;
	2	3	0.026	1;
	1	3	0.0365	1;
];

%% VSC converter data
%	acbus	busdc	status	ac_mode	dc_mode	Pac_set	Qac_set	Vac_set	Pdc_set	Vdc_set	Kdroop	lossA	lossB	lossC	tr_r	tr_x	tr_b	tr_shift	tr_rateA	tr_rateB	tr_rateC	filter_g	filter_b	reactor_r	reactor_x	reactor_b	reactor_rateA	reactor_rateB	reactor_rateC
mpc.vsc = [
	2	1	1	3	2	-60	-40	1	0	1	0	1.103	0.148437591	0.122411258	0.0015	0.1121	0	0	0	0	0	0	0.0887	0.0001	0.16428	0	0	0	0;
	3	2	1	2	1	0	0	1	0	1	0	1.103	0.148437591	0.0807953511	0.0015	0.1121	0	0	0	0	0	0	0.0887	0.0001	0.16428	0	0	0	0;
	5	3	1	3	2	35	5	1	0	1	0	1.103	0.148437591	0.0807953511	0.0015	0.1121	0	0	0	0	0	0	0.0887	0.0001	0.16428	0	0	0	0;
];

%% VSC directional loss metadata
mpc.vsc_loss = struct();
mpc.vsc_loss.c_positive = 0.0807953511167122;
mpc.vsc_loss.c_negative = 0.122411258139046;

%% VSC capability metadata
mpc.vsc_capability = struct();
mpc.vsc_capability.Snom = [120;120;120];
mpc.vsc_capability.VconvMax = [1.1;1.1;1.1];
