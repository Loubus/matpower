function mpc = case5_vsc_mtdc_beerten_droop
% case5_vsc_mtdc_beerten_droop - Beerten VSC-MTDC case with DC droop.
%
% This variant uses case5_vsc_mtdc_beerten_ultc_swshunt, disables the
% PSS/E-style ULTC and switched shunt controls, and configures the MTDC grid
% with one DC-voltage reference converter and two DC-droop converters.
%
% The DC reference is the converter at AC bus 2. The converters at AC buses 3
% and 5 act through Pdc = Pdc_set + Kdroop * (Vdc - Vdc_set).
%
% See also case5_vsc_mtdc_beerten_droop_target, runcpf_vsc_mtdc.

%   MATPOWER

c = idx_vsc;
[~, ~, ~, ~, ~, ~, ~, ~, BS] = idx_bus;
[F_BUS, T_BUS, ~, ~, ~, ~, ~, ~, TAP] = idx_brch;

mpc = case5_vsc_mtdc_beerten_ultc_swshunt;

%% Keep the generator-side transformer as a fixed branch and remove the
%% outer AC-side controls, so the example isolates VSC droop action.
xf = mpc.branch(:, F_BUS) == 6 & mpc.branch(:, T_BUS) == 2;
mpc.branch(xf, TAP) = 1;
mpc.bus(:, BS) = 0;

if isfield(mpc, 'psse')
    if isfield(mpc.psse, 'system') && isfield(mpc.psse.system, 'solver')
        mpc.psse.system.solver.ACTAPS = 0;
        mpc.psse.system.solver.SWSHNT = 0;
    end
    if isfield(mpc.psse, 'xfmr')
        mpc.psse = rmfield(mpc.psse, 'xfmr');
    end
    if isfield(mpc.psse, 'swshunt')
        mpc.psse = rmfield(mpc.psse, 'swshunt');
    end
end

%% VSC 1, AC bus 2: DC voltage reference, fixed Q on the AC side.
mpc.vsc(1, c.AC_MODE) = c.VSC_AC_Q;
mpc.vsc(1, c.DC_MODE) = c.VSC_DC_VDC;
mpc.vsc(1, c.KDROOP) = 0;

%% VSC 2, AC bus 3: DC droop, fixed AC voltage.
mpc.vsc(2, c.AC_MODE) = c.VSC_AC_V;
mpc.vsc(2, c.DC_MODE) = c.VSC_DC_DROOP;
mpc.vsc(2, c.KDROOP) = -180;

%% VSC 3, AC bus 5: DC droop, fixed Q on the AC side.
mpc.vsc(3, c.AC_MODE) = c.VSC_AC_Q;
mpc.vsc(3, c.DC_MODE) = c.VSC_DC_DROOP;
mpc.vsc(3, c.KDROOP) = -280;

