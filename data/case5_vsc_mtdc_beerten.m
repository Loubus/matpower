function mpc = case5_vsc_mtdc_beerten
% case5_vsc_mtdc_beerten - 5-bus VSC-MTDC case based on Beerten et al.
%
% This case reproduces the data used for the 5-bus, 3-terminal VSC-MTDC
% example in:
%
%   J. Beerten, S. Cole, R. Belmans, "A Sequential AC/DC Power Flow
%   Algorithm for Networks Containing Multi-terminal VSC HVDC Systems",
%   IEEE PES General Meeting, 2010.
%
% The paper reports the following AC bus voltages with MTDC:
%   bus 1: 1.060 /  0.00 deg
%   bus 2: 1.000 / -2.39 deg
%   bus 3: 1.000 / -3.90 deg
%   bus 4: 0.996 / -4.27 deg
%   bus 5: 0.991 / -4.15 deg
%
% The converter table in the paper reports Pdc with the opposite sign from
% idx_vsc, where Pdc > 0 is injection into the DC network and
% Pac + Pdc + Ploss = 0. Thus, paper Pdc values should be compared against
% -results.vsc(:, c.PDC).
%
% Beerten's station model uses a lumped converter-side impedance Zc. This
% case keeps the explicit MATPOWER topology used by runpf_vsc_mtdc:
%
%     PCC -> no-tap transformer -> filter bus -> phase reactor -> internal VSC
%
% and places almost all of Zc in the reactor branch, with a very small
% no-tap transformer reactance to keep the auxiliary bus well-defined.
%
% Please see caseformat, idx_busdc, idx_branchdc and idx_vsc for details.
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
	1	3	0	0	0	0	1	1.060	0	230	1	1.1	0.9;
	2	2	20	10	0	0	1	1.000	0	230	1	1.1	0.9;
	3	1	45	15	0	0	1	1.000	0	230	1	1.1	0.9;
	4	1	40	5	0	0	1	1.000	0	230	1	1.1	0.9;
	5	1	60	10	0	0	1	1.000	0	230	1	1.1	0.9;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	0	0	500	-500	1.060	100	1	500	-500	0	0	0	0	0	0	0	0	0	0	0;
	2	40	0	300	-300	1.000	100	1	300	0	0	0	0	0	0	0	0	0	0	0	0;
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
