function [xfmr, bus, warns, bus_name, info] = psse_convert_xfmr(warns, trans2, trans3, verbose, baseMVA, bus, bus_name, impcor)
% psse_convert_xfmr - Convert transformer data from PSS/E RAW to |MATPOWER|.
% ::
%
%   [XFMR, BUS, WARNINGS] = PSSE_CONVERT_XFMR(WARNINGS, TRANS2, TRANS3, ...
%                                   VERBOSE, BASEMVA, BUS)
%   [XFMR, BUS, WARNINGS, BUS_NAME] = PSSE_CONVERT_XFMR(WARNINGS, TRANS2, ...
%                                   TRANS3, VERBOSE, BASEMVA, BUS, BUS_NAME)
%
%   Convert all transformer data read from a PSS/E RAW data file
%   into MATPOWER format. Returns a branch matrix corresponding to
%   the transformers and an updated bus matrix, with additional buses
%   added for the star points of three winding transformers.
%
%   Inputs:
%       WARNINGS :  cell array of strings containing accumulated
%                   warning messages
%       TRANS2  : matrix of raw two winding transformer data returned
%                 by PSSE_READ in data.trans2.num
%       TRANS3  : matrix of raw three winding transformer data returned
%                 by PSSE_READ in data.trans3.num
%       VERBOSE :   1 to display progress info, 0 (default) otherwise
%       BASEMVA : system MVA base
%       BUS     : MATPOWER bus matrix
%       BUS_NAME: (optional) cell array of bus names
%
%   Outputs:
%       XFMR    : MATPOWER branch matrix of transformer data
%       BUS     : updated MATPOWER bus matrix, with additional buses
%                 added for star points of three winding transformers
%       WARNINGS :  cell array of strings containing updated accumulated
%                   warning messages
%       BUS_NAME: (optional) updated cell array of bus names
%
% See also psse_convert.

%   MATPOWER
%   Copyright (c) 2014-2024, Power Systems Engineering Research Center (PSERC)
%   by Yujia Zhu, PSERC ASU
%   and Ray Zimmerman, PSERC Cornell
%   Based on mptransin.m and mptransficbus.m, written by:
%       Yujia Zhu, Jan 2014, yzhu54@asu.edu.
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%% define named indices into bus, gen, branch matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;

%% compatibility
use_winding_baseV = 1;  %% If true, will use winding base V for any conversions
                        %% instead of bus base V if they are different.
                        %% Turn off for compatibility with, apparently buggy,
                        %% PSS/E implementation (checked by YZ both for
                        %% PSS/E internal model and conversion from RAW to
                        %% IEEE format)

%% sizes
nb = size(bus, 1);
nt2 = size(trans2, 1);
nt3 = size(trans3, 1);
if nargin < 8
    impcor = [];
end
orig2 = (1:nt2)';
orig3 = (1:nt3)';
info = struct( ...
    'two', struct('raw_idx', [], 'branch_idx', [], ...
        'tab_applied', false(0, 1), 'tab_factor', complex(zeros(0, 1)), ...
        'nominal_rx', zeros(0, 2)), ...
    'three', struct('raw_idx', [], 'branch_idx', [], ...
        'tab_applied', false(0, 3), 'tab_factor', complex(zeros(0, 3)), ...
        'nominal_rx', zeros(0, 3, 2)) );
[t2c, t3c] = psse_xfmr_col_idx(size(trans2, 2), size(trans3, 2));

%%-----  create fictitious buses for star point of 3 winding transformers  -----
starbus = zeros(nt3, VMIN);     %% initialize additional bus matrix
if nt3 > 0
    mb =  max(bus(:, BUS_I));       %% find maximum bus number
    b = 10^ceil(log10(mb+1));       %% start new numbers at next order of magnitude
    wind1bus = trans3(:,1);         %% winding1 bus number
    e2i = sparse(bus(:, BUS_I), ones(nb, 1), 1:nb, max(bus(:, BUS_I)), 1);
    starbus(:, BUS_I) = (b+1:b+nt3)';   %% bus numbers follow originals
    starbus(:, BUS_TYPE) = PQ;
    starbus(trans3(:,12)==0, BUS_TYPE) = NONE;  %% isolated if transformer is off-line
    starbus(:, VA) = trans3(:, t3c.anstar);  %% VA = star point voltage angle
    starbus(:, VM) = trans3(:, t3c.vmstar);  %% VM = star point voltage magnitude (PU)
    starbus(:, [BUS_AREA, ZONE]) = bus(e2i(wind1bus), [7,11]); %% wind1 bus area, zone
    starbus(:, BASE_KV) = 1;        %% baseKV = 1 kV (RayZ: why?)
    starbus(:, VMAX) = 1.1;
    starbus(:, VMIN) = 0.9;
end

%% two winding transformer data
[tf,fbus] = ismember(trans2(:,1), bus(:, BUS_I));      %% I
[tf,tbus] = ismember(trans2(:,2), bus(:, BUS_I));      %% J
%% check for bad bus numbers
k = find(fbus == 0 | tbus == 0);
if ~isempty(k)
    warns{end+1} = sprintf('Ignoring %d two-winding transformers with bad bus numbers', length(k));
    if verbose
        fprintf('WARNING: Ignoring %d two-winding transformers with bad bus numbers', length(k));
    end
    fbus(k) = [];
    tbus(k) = [];
    orig2(k) = [];
    trans2(k, :) = [];
    nt2 = nt2 - length(k);
end
if use_winding_baseV
    Zbs = bus(:, BASE_KV).^2 / baseMVA;     %% system impedance base
end
if nt2 > 0
    cw2 = find(trans2(:,5) == 2);   %% CW = 2
    cw3 = find(trans2(:,5) == 3);   %% CW = 3
    cw23 = [cw2;cw3];               %% CW = 2 or 3
    cz2 = find(trans2(:,6) == 2);   %% CZ = 2
    cz3 = find(trans2(:,6) == 3);   %% CZ = 3
    cz23 = [cz2;cz3];               %% CZ = 2 or 3

    %% NOMVn = 0 means use the base voltage of the corresponding bus.
    nomv1 = trans2(:,25);
    nomv2 = trans2(:, t2c.nomv2);
    k = find(isnan(nomv1) | nomv1 == 0);
    if ~isempty(k)
        nomv1(k) = bus(fbus(k), BASE_KV);
    end
    k = find(isnan(nomv2) | nomv2 == 0);
    if ~isempty(k)
        nomv2(k) = bus(tbus(k), BASE_KV);
    end

    R = trans2(:,21);
    X = trans2(:,22);
    if use_winding_baseV
        Zb = ones(nt2, 1);
        Zb(cz23) = nomv1(cz23).^2 ./ trans2(cz23,23);
    end
    R(cz3) = 1e-6 * R(cz3, 1) ./ trans2(cz3,23);
    X(cz3) = sqrt(X(cz3).^2 - R(cz3).^2);   %% R, X for cz3, pu on winding bases
    if use_winding_baseV
        R(cz23) = R(cz23) .* Zb(cz23) ./ Zbs(fbus(cz23));
        X(cz23) = X(cz23) .* Zb(cz23) ./ Zbs(fbus(cz23));
    else    %% use bus base V (even if winding base V is different)
        R(cz23) = baseMVA * R(cz23, 1) ./ trans2(cz23,23);
        X(cz23) = baseMVA * X(cz23, 1) ./ trans2(cz23,23);
    end
    tap = trans2(:, t2c.windv1) ./ trans2(:, t2c.windv2);   %% WINDV1/WINDV2
    tap(cw23) = tap(cw23, 1) .* bus(tbus(cw23), BASE_KV)./bus(fbus(cw23), BASE_KV);
    tap(cw3)  = tap(cw3, 1)  .* nomv1(cw3)./nomv2(cw3);
    shift = trans2(:, t2c.ang1);

    R_nom2 = R;
    X_nom2 = X;
    [R, X, tab_applied2, tab_factor2] = apply_tab_winding( ...
        R, X, impcor, trans2(:, t2c.tab1), ...
        tab_ratio(trans2(:, 5), trans2(:, t2c.windv1), bus(fbus, BASE_KV)), ...
        shift);
else
    R_nom2 = zeros(0, 1);
    X_nom2 = zeros(0, 1);
    tab_applied2 = false(0, 1);
    tab_factor2 = complex(zeros(0, 1));
end

%% three winding transformer data
[tf,ind1] = ismember(trans3(:,1), bus(:, BUS_I));
[tf,ind2] = ismember(trans3(:,2), bus(:, BUS_I));
[tf,ind3] = ismember(trans3(:,3), bus(:, BUS_I));
%% check for bad bus numbers
k = find(ind1 == 0 | ind2 == 0 | ind3 == 0);
if ~isempty(k)
    warns{end+1} = sprintf('Ignoring %d three-winding transformers with bad bus numbers', length(k));
    if verbose
        fprintf('WARNING: Ignoring %d three-winding transformers with bad bus numbers', length(k));
    end
    ind1(k) = [];
    ind2(k) = [];
    ind3(k) = [];
    orig3(k) = [];
    trans3(k, :) = [];
    starbus(k, :) = [];
    nt3 = nt3 - length(k);
end
%% Each three winding transformer will be converted into 3 branches:
%% The branches will be in the order of
%% # winding1 -> # winding2
%% # winding2 -> # winding3
%% # winding3 -> # winding1
if nt3 > 0
    cw2 = find(trans3(:,5) == 2);   %% CW = 2
    cw3 = find(trans3(:,5) == 3);   %% CW = 3
    cw23 = [cw2;cw3];               %% CW = 2 or 3
    cz2 = find(trans3(:,6) == 2);   %% CZ = 2
    cz3 = find(trans3(:,6) == 3);   %% CZ = 3
    cz23 = [cz2;cz3];               %% CZ = 2 or 3

    %% NOMVn = 0 means use the base voltage of the corresponding bus.
    nomv1 = trans3(:, t3c.nomv1);
    nomv2 = trans3(:, t3c.nomv2);
    nomv3 = trans3(:, t3c.nomv3);
    k = find(isnan(nomv1) | nomv1 == 0);
    if ~isempty(k)
        nomv1(k) = bus(ind1(k), BASE_KV);
    end
    k = find(isnan(nomv2) | nomv2 == 0);
    if ~isempty(k)
        nomv2(k) = bus(ind2(k), BASE_KV);
    end
    k = find(isnan(nomv3) | nomv3 == 0);
    if ~isempty(k)
        nomv3(k) = bus(ind3(k), BASE_KV);
    end

    tap1 = trans3(:, t3c.windv1);   %% off nominal tap ratio of branch 1
    tap2 = trans3(:, t3c.windv2);   %% off nominal tap ratio of branch 2
    tap3 = trans3(:, t3c.windv3);   %% off nominal tap ratio of branch 3
    tap1(cw23) = tap1(cw23, 1) ./ bus(ind1(cw23), BASE_KV);
    tap2(cw23) = tap2(cw23, 1) ./ bus(ind2(cw23), BASE_KV);
    tap3(cw23) = tap3(cw23, 1) ./ bus(ind3(cw23), BASE_KV);
    tap1(cw3)  = tap1(cw3, 1)  .* nomv1(cw3);
    tap2(cw3)  = tap2(cw3, 1)  .* nomv2(cw3);
    tap3(cw3)  = tap3(cw3, 1)  .* nomv3(cw3);
    shift1 = trans3(:, t3c.ang1);
    shift2 = trans3(:, t3c.ang2);
    shift3 = trans3(:, t3c.ang3);

    %% replace winding base voltage with bus base voltage
    % commented out: Yujia thinks this is wrong
    % trans3(cz3, 33) = bus(ind1(cz3), BASE_KV);
    % trans3(cz3, 49) = bus(ind1(cz3), BASE_KV);
    % trans3(cz3, 65) = bus(ind1(cz3), BASE_KV);

    R12 = trans3(:, t3c.r12);
    X12 = trans3(:, t3c.x12);
    R23 = trans3(:, t3c.r23);
    X23 = trans3(:, t3c.x23);
    R31 = trans3(:, t3c.r31);
    X31 = trans3(:, t3c.x31);
    Zb1 = nomv1.^2 ./ trans3(:, t3c.sbase12);
    Zb2 = nomv2.^2 ./ trans3(:, t3c.sbase23);
    Zb3 = nomv3.^2 ./ trans3(:, t3c.sbase31);

    R12(cz3) = 1e-6 * R12(cz3, 1) ./ trans3(cz3, t3c.sbase12);
    X12(cz3) = sqrt(X12(cz3).^2 - R12(cz3).^2);
    R23(cz3) = 1e-6 * R23(cz3, 1) ./ trans3(cz3, t3c.sbase23);
    X23(cz3) = sqrt(X23(cz3).^2 - R23(cz3).^2);
    R31(cz3) = 1e-6 * R31(cz3, 1) ./ trans3(cz3, t3c.sbase31);
    X31(cz3) = sqrt(X31(cz3).^2 - R31(cz3).^2);

    if use_winding_baseV
        R12(cz23) = R12(cz23) .* Zb1(cz23) ./ Zbs(ind1(cz23));
        X12(cz23) = X12(cz23) .* Zb1(cz23) ./ Zbs(ind1(cz23));
        R23(cz23) = R23(cz23) .* Zb2(cz23) ./ Zbs(ind2(cz23));
        X23(cz23) = X23(cz23) .* Zb2(cz23) ./ Zbs(ind2(cz23));
        R31(cz23) = R31(cz23) .* Zb3(cz23) ./ Zbs(ind3(cz23));
        X31(cz23) = X31(cz23) .* Zb3(cz23) ./ Zbs(ind3(cz23));
    else    %% use bus base V (even if winding base V is different)
        R12(cz23) = baseMVA * R12(cz23, 1) ./ trans3(cz23, t3c.sbase12);
        X12(cz23) = baseMVA * X12(cz23, 1) ./ trans3(cz23, t3c.sbase12);
        R23(cz23) = baseMVA * R23(cz23, 1) ./ trans3(cz23, t3c.sbase23);
        X23(cz23) = baseMVA * X23(cz23, 1) ./ trans3(cz23, t3c.sbase23);
        R31(cz23) = baseMVA * R31(cz23, 1) ./ trans3(cz23, t3c.sbase31);
        X31(cz23) = baseMVA * X31(cz23, 1) ./ trans3(cz23, t3c.sbase31);
    end

    R1 = (R12+R31-R23) ./ 2;
    R2 = (R12+R23-R31) ./ 2;
    R3 = (R31+R23-R12) ./ 2;
    X1 = (X12+X31-X23) ./ 2;
    X2 = (X12+X23-X31) ./ 2;
    X3 = (X31+X23-X12) ./ 2;

    zcod_ok = true(nt3, 1);
    if t3c.zcod > 0
        zcod = trans3(:, t3c.zcod);
        zcod_ok = isnan(zcod) | zcod == 0;
    end

    R_nom31 = R1;
    R_nom32 = R2;
    R_nom33 = R3;
    X_nom31 = X1;
    X_nom32 = X2;
    X_nom33 = X3;
    [R1, X1, tab_applied31, tab_factor31] = apply_tab_winding( ...
        R1, X1, impcor, trans3(:, t3c.tab1), ...
        tab_ratio(trans3(:, 5), trans3(:, t3c.windv1), bus(ind1, BASE_KV)), ...
        trans3(:, t3c.ang1), zcod_ok);
    [R2, X2, tab_applied32, tab_factor32] = apply_tab_winding( ...
        R2, X2, impcor, trans3(:, t3c.tab2), ...
        tab_ratio(trans3(:, 5), trans3(:, t3c.windv2), bus(ind2, BASE_KV)), ...
        trans3(:, t3c.ang2), zcod_ok);
    [R3, X3, tab_applied33, tab_factor33] = apply_tab_winding( ...
        R3, X3, impcor, trans3(:, t3c.tab3), ...
        tab_ratio(trans3(:, 5), trans3(:, t3c.windv3), bus(ind3, BASE_KV)), ...
        trans3(:, t3c.ang3), zcod_ok);
else
    R_nom31 = zeros(0, 1);
    R_nom32 = zeros(0, 1);
    R_nom33 = zeros(0, 1);
    X_nom31 = zeros(0, 1);
    X_nom32 = zeros(0, 1);
    X_nom33 = zeros(0, 1);
    tab_applied31 = false(0, 1);
    tab_applied32 = false(0, 1);
    tab_applied33 = false(0, 1);
    tab_factor31 = complex(zeros(0, 1));
    tab_factor32 = complex(zeros(0, 1));
    tab_factor33 = complex(zeros(0, 1));
end

%%-----  assemble transformer data into MATPOWER branch format  -----
%%% two winding transformers %%%
xfmr2 = zeros(nt2, ANGMAX);
if nt2 > 0
    xfmr2(:, [F_BUS T_BUS]) = trans2(:,[1,2]);
    xfmr2(:, [BR_R BR_X TAP SHIFT]) = [R X tap shift];
    xfmr2(:, [RATE_A RATE_B RATE_C]) = trans2(:, t2c.rate1(1:3));
    xfmr2(:, BR_STATUS) = trans2(:,12);
    xfmr2(:, ANGMIN) = -360;
    xfmr2(:, ANGMAX) = 360;
end

%%% three winding transformers %%%
xfmr3 = zeros(3*nt3, ANGMAX);
if nt3 > 0
    idx1 = (1:3:3*nt3)';        %% indices of winding 1
    idx2 = idx1+1;              %% indices of winding 2
    idx3 = idx1+2;              %% indices of winding 3
    %% bus numbers
    xfmr3(idx1, [F_BUS T_BUS]) = [trans3(:,1), starbus(:,1)];
    xfmr3(idx2, [F_BUS T_BUS]) = [trans3(:,2), starbus(:,1)];
    xfmr3(idx3, [F_BUS T_BUS]) = [trans3(:,3), starbus(:,1)];
    %% impedances, tap ratios & phase shifts
    xfmr3(idx1, [BR_R BR_X TAP SHIFT]) = [R1 X1 tap1 shift1];
    xfmr3(idx2, [BR_R BR_X TAP SHIFT]) = [R2 X2 tap2 shift2];
    xfmr3(idx3, [BR_R BR_X TAP SHIFT]) = [R3 X3 tap3 shift3];
    %% ratings
    xfmr3(idx1, [RATE_A RATE_B RATE_C]) = trans3(:, t3c.rate1(1:3));
    xfmr3(idx2, [RATE_A RATE_B RATE_C]) = trans3(:, t3c.rate2(1:3));
    xfmr3(idx3, [RATE_A RATE_B RATE_C]) = trans3(:, t3c.rate3(1:3));
    xfmr3(:, ANGMIN) = -360;        %% angle limits
    xfmr3(:, ANGMAX) =  360;
    %% winding status
    xfmr3(:, BR_STATUS) = 1;        %% initialize to all in-service
    status = trans3(:, 12);
    k1 = find(status == 0 | status == 4);   %% winding 1 out-of-service
    k2 = find(status == 0 | status == 2);   %% winding 2 out-of-service
    k3 = find(status == 0 | status == 3);   %% winding 3 out-of-service
    if ~isempty(k1)
        xfmr3(idx1(k1), BR_STATUS) = 0;
    end
    if ~isempty(k2)
        xfmr3(idx2(k2), BR_STATUS) = 0;
    end
    if ~isempty(k3)
        xfmr3(idx3(k3), BR_STATUS) = 0;
    end
end

%% combine 2-winding and 3-winding transformer data
xfmr = [xfmr2; xfmr3];
info.two.raw_idx = orig2;
info.two.branch_idx = (1:nt2)';
if nt2 > 0
    info.two.tab_applied = tab_applied2;
    info.two.tab_factor = tab_factor2;
    info.two.nominal_rx = [R_nom2 X_nom2];
end
info.three.raw_idx = orig3;
if nt3 > 0
    info.three.branch_idx = [idx1 idx2 idx3] + nt2;
    info.three.tab_applied = [tab_applied31 tab_applied32 tab_applied33];
    info.three.tab_factor = [tab_factor31 tab_factor32 tab_factor33];
    info.three.nominal_rx = cat(3, ...
        [R_nom31 R_nom32 R_nom33], ...
        [X_nom31 X_nom32 X_nom33]);
else
    info.three.branch_idx = zeros(0, 3);
end

% %% delete out-of-service windings
% k = find(xfmr(:, BR_STATUS) == 0);
% xfmr(k, :) = [];
% k = find(trans3(:,12) <= 0);
% starbus(k, :) = [];

%% finish adding the star point bus
bus = [bus; starbus];
if nt3 > 0
    warns{end+1} = sprintf('Added buses %d-%d as star-points for 3-winding transformers.', ...
        starbus(1, BUS_I), starbus(end, BUS_I));
    if verbose
        fprintf('Added buses %d-%d as star-points for 3-winding transformers.\n', ...
            starbus(1, BUS_I), starbus(end, BUS_I));
    end
end
if nargin > 6 && nargout > 3
    starbus_name = cell(nt3, 1);
    for k = 1:nt3
        starbus_name{k} = sprintf('STR_PT_XF_%-2d', k);
    end
    bus_name = [bus_name; starbus_name];
end

function [R, X, applied, factor] = apply_tab_winding(R, X, impcor, tab, ratio, angle, enabled)
%APPLY_TAB_WINDING  Applies PSS/E transformer impedance correction factors.

if nargin < 7
    enabled = true(size(tab));
end
[factor, applied] = mp.psse_xfmr_tab_factor(impcor, tab, ratio, angle);
applied = applied & enabled;
factor(~applied) = 1;
if any(applied)
    z = (R(applied) + 1j * X(applied)) .* factor(applied);
    R(applied) = real(z);
    X(applied) = imag(z);
end

function ratio = tab_ratio(cw, windv, basekv)
%TAB_RATIO  Converts PSS/E WINDV to a pu tap-ratio table input.

ratio = windv;
k = find(cw == 2 & basekv ~= 0);
ratio(k) = windv(k) ./ basekv(k);

function [t2c, t3c] = psse_xfmr_col_idx(nc2, nc3)
%PSSE_XFMR_COL_IDX  Column indices for parsed transformer winding records.

if nc2 >= 52       %% Rev34 normalized/full winding record
    t2c.windv1 = 24;
    t2c.nomv1  = 25;
    t2c.ang1   = 26;
    t2c.rate1  = 27:38;
    t2c.cod1   = 39;
    t2c.cont1  = 40;
    t2c.rma1   = 41;
    t2c.rmi1   = 42;
    t2c.vma1   = 43;
    t2c.vmi1   = 44;
    t2c.ntp1   = 45;
    t2c.tab1   = 46;
    t2c.cr1    = 47;
    t2c.cx1    = 48;
    t2c.cnxa1  = 49;
    t2c.node1  = 50;
    t2c.windv2 = 51;
    t2c.nomv2  = 52;
else
    t2c.windv1 = 24;
    t2c.nomv1  = 25;
    t2c.ang1   = 26;
    t2c.rate1  = 27:29;
    t2c.cod1   = 30;
    t2c.cont1  = 31;
    t2c.rma1   = 32;
    t2c.rmi1   = 33;
    t2c.vma1   = 34;
    t2c.vmi1   = 35;
    t2c.ntp1   = 36;
    t2c.tab1   = 37;
    t2c.cr1    = 38;
    t2c.cx1    = 39;
    t2c.node1  = 0;
    t2c.cnxa1  = 0;
    t2c.windv2 = 40;
    t2c.nomv2  = 41;
end

if nc3 >= 112      %% Rev34 normalized/full winding records
    if nc3 >= 113
        off = 1;
        t3c.zcod = 21;
    else
        off = 0;
        t3c.zcod = 0;
    end
    t3c.r12      = 21 + off;
    t3c.x12      = 22 + off;
    t3c.sbase12  = 23 + off;
    t3c.r23      = 24 + off;
    t3c.x23      = 25 + off;
    t3c.sbase23  = 26 + off;
    t3c.r31      = 27 + off;
    t3c.x31      = 28 + off;
    t3c.sbase31  = 29 + off;
    t3c.vmstar   = 30 + off;
    t3c.anstar   = 31 + off;
    t3c.windv1 = 32 + off;
    t3c.nomv1  = 33 + off;
    t3c.ang1   = 34 + off;
    t3c.rate1  = (35:46) + off;
    t3c.cod1   = 47 + off;
    t3c.cont1  = 48 + off;
    t3c.rma1   = 49 + off;
    t3c.rmi1   = 50 + off;
    t3c.vma1   = 51 + off;
    t3c.vmi1   = 52 + off;
    t3c.ntp1   = 53 + off;
    t3c.tab1   = 54 + off;
    t3c.cr1    = 55 + off;
    t3c.cx1    = 56 + off;
    t3c.cnxa1  = 57 + off;
    t3c.node1  = 58 + off;
    t3c.windv2 = 59 + off;
    t3c.nomv2  = 60 + off;
    t3c.ang2   = 61 + off;
    t3c.rate2  = (62:73) + off;
    t3c.cod2   = 74 + off;
    t3c.cont2  = 75 + off;
    t3c.rma2   = 76 + off;
    t3c.rmi2   = 77 + off;
    t3c.vma2   = 78 + off;
    t3c.vmi2   = 79 + off;
    t3c.ntp2   = 80 + off;
    t3c.tab2   = 81 + off;
    t3c.cr2    = 82 + off;
    t3c.cx2    = 83 + off;
    t3c.cnxa2  = 84 + off;
    t3c.node2  = 85 + off;
    t3c.windv3 = 86 + off;
    t3c.nomv3  = 87 + off;
    t3c.ang3   = 88 + off;
    t3c.rate3  = (89:100) + off;
    t3c.cod3   = 101 + off;
    t3c.cont3  = 102 + off;
    t3c.rma3   = 103 + off;
    t3c.rmi3   = 104 + off;
    t3c.vma3   = 105 + off;
    t3c.vmi3   = 106 + off;
    t3c.ntp3   = 107 + off;
    t3c.tab3   = 108 + off;
    t3c.cr3    = 109 + off;
    t3c.cx3    = 110 + off;
    t3c.cnxa3  = 111 + off;
    t3c.node3  = 112 + off;
else
    t3c.zcod   = 0;
    t3c.r12    = 21;
    t3c.x12    = 22;
    t3c.sbase12 = 23;
    t3c.r23    = 24;
    t3c.x23    = 25;
    t3c.sbase23 = 26;
    t3c.r31    = 27;
    t3c.x31    = 28;
    t3c.sbase31 = 29;
    t3c.vmstar = 30;
    t3c.anstar = 31;
    t3c.windv1 = 32;
    t3c.nomv1  = 33;
    t3c.ang1   = 34;
    t3c.rate1  = 35:37;
    t3c.cod1   = 38;
    t3c.cont1  = 39;
    t3c.rma1   = 40;
    t3c.rmi1   = 41;
    t3c.vma1   = 42;
    t3c.vmi1   = 43;
    t3c.ntp1   = 44;
    t3c.tab1   = 45;
    t3c.cr1    = 46;
    t3c.cx1    = 47;
    t3c.node1  = 0;
    t3c.cnxa1  = 0;
    t3c.windv2 = 48;
    t3c.nomv2  = 49;
    t3c.ang2   = 50;
    t3c.rate2  = 51:53;
    t3c.cod2   = 54;
    t3c.cont2  = 55;
    t3c.rmi2   = 57;
    t3c.rma2   = 56;
    t3c.vma2   = 58;
    t3c.vmi2   = 59;
    t3c.ntp2   = 60;
    t3c.tab2   = 61;
    t3c.cr2    = 62;
    t3c.cx2    = 63;
    t3c.node2  = 0;
    t3c.cnxa2  = 0;
    t3c.windv3 = 64;
    t3c.nomv3  = 65;
    t3c.ang3   = 66;
    t3c.rate3  = 67:69;
    t3c.cod3   = 70;
    t3c.cont3  = 71;
    t3c.rma3   = 72;
    t3c.rmi3   = 73;
    t3c.vma3   = 74;
    t3c.vmi3   = 75;
    t3c.ntp3   = 76;
    t3c.tab3   = 77;
    t3c.cr3    = 78;
    t3c.cx3    = 79;
    t3c.node3  = 0;
    t3c.cnxa3  = 0;
end
