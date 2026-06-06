function mpc = case5_vsc_mtdc_beerten_all_controls
% case5_vsc_mtdc_beerten_all_controls - VSC-MTDC case with all local controls.
%
% This integration fixture extends CASE5_VSC_MTDC_BEERTEN_ULTC_SWSHUNT
% with a fourth VSC terminal and enables representative controls in the
% same small AC/DC network:
%   - conventional slack and non-slack generation;
%   - PSS/E-style transformer tap control and switched shunt metadata;
%   - VSC AC modes Q, V, PQ and PV;
%   - VSC DC modes VDC, PDC and DROOP.
%
% It is intended as a compact regression case for PF/CPF orchestration,
% active VSC/generator capability enforcement and VSC-HVDC dispatch helpers.
% It deliberately avoids PSS/E TWODC/FACTS records because the monolithic
% VSC-MTDC formulation does not include MATPOWER dcline or FACTS state
% variables.
%
% See also case5_vsc_mtdc_beerten_all_controls_target,
% case5_vsc_mtdc_beerten_ultc_swshunt, runcpf_vsc_mtdc.

%   MATPOWER

c = idx_vsc;

mpc = case5_vsc_mtdc_beerten_ultc_swshunt;

%% Expand the MTDC grid to four terminals by adding a converter at AC bus 4.
mpc.busdc = [
    mpc.busdc;
    4   1   1.000   300
];

mpc.branchdc = [
    mpc.branchdc;
    3   4   0.02500   1;
    4   5   0.02500   1
];

%% VSC 1, AC bus 2: fixed Q on AC side, DC voltage reference.
mpc.vsc(1, c.AC_MODE) = c.VSC_AC_Q;
mpc.vsc(1, c.DC_MODE) = c.VSC_DC_VDC;
mpc.vsc(1, c.QAC_SET) = -40;
mpc.vsc(1, c.VDC_SET) = 1.008;
mpc.vsc(1, c.KDROOP) = 0;

%% VSC 2, AC bus 3: AC voltage control and DC droop.
mpc.vsc(2, c.AC_MODE) = c.VSC_AC_V;
mpc.vsc(2, c.DC_MODE) = c.VSC_DC_DROOP;
mpc.vsc(2, c.VAC_SET) = 1.000;
mpc.vsc(2, c.KDROOP) = -180;

%% VSC 3, AC bus 5: fixed AC P/Q converter.
mpc.vsc(3, c.AC_MODE) = c.VSC_AC_PQ;
mpc.vsc(3, c.DC_MODE) = c.VSC_DC_PDC;
mpc.vsc(3, c.PAC_SET) = 35;
mpc.vsc(3, c.QAC_SET) = 5;
mpc.vsc(3, c.KDROOP) = 0;

%% VSC 4, AC bus 4: fixed active power with AC voltage control.
v4 = mpc.vsc(2, :);
v4(c.VSC_BUS) = 4;
v4(c.BUSDC) = 4;
v4(c.AC_MODE) = c.VSC_AC_PV;
v4(c.DC_MODE) = c.VSC_DC_PDC;
v4(c.PAC_SET) = 15;
v4(c.QAC_SET) = 0;
v4(c.VAC_SET) = 0.995;
v4(c.PDC_SET) = -16;
v4(c.VDC_SET) = 1.000;
v4(c.KDROOP) = 0;
mpc.vsc = [mpc.vsc; v4];

%% Use one rating across the converter stations in this synthetic fixture.
rate_cols = [c.TR_RATE_A c.TR_RATE_B c.TR_RATE_C ...
    c.REACTOR_RATE_A c.REACTOR_RATE_B c.REACTOR_RATE_C];
mpc.vsc(:, rate_cols) = 250;

