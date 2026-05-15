function [mpc, warns] = psse_convert(warns, data, verbose)
% psse_convert - Converts data read from PSS/E RAW file to |MATPOWER| case.
% ::
%
%   [MPC, WARNINGS] = PSSE_CONVERT(WARNINGS, DATA)
%   [MPC, WARNINGS] = PSSE_CONVERT(WARNINGS, DATA, VERBOSE)
%
%   Converts data read from a version RAW data file into a
%   MATPOWER case struct.
%
%   Input:
%       WARNINGS :  cell array of strings containing accumulated
%                   warning messages
%       DATA : struct read by PSSE_READ (see PSSE_READ for details).
%       VERBOSE :   1 to display progress info, 0 (default) otherwise
%
%   Output:
%       MPC : a MATPOWER case struct created from the PSS/E data
%       WARNINGS :  cell array of strings containing updated accumulated
%                   warning messages
%
% See also psse_read.

%   MATPOWER
%   Copyright (c) 2014-2024, Power Systems Engineering Research Center (PSERC)
%   by Yujia Zhu, PSERC ASU
%   and Ray Zimmerman, PSERC Cornell
%   Based on mpraw2mp.m, written by: Yujia Zhu, Jan 2014, yzhu54@asu.edu.
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
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;

%% options
sort_buses = 1;

%% defaults
if nargin < 3
    verbose = 0;
end
haveVlims = 0;
Vmin = 0.9;
Vmax = 1.1;

%%-----  case identification data  -----
baseMVA = data.id.SBASE;
rev = data.id.REV;

%%-----  bus data  -----
numbus = data.bus.num;
[nb, ncols] = size(numbus); %% number of buses, number of cols
bus = zeros(nb, VMIN);      %% initialize bus matrix
if rev < 24
    bus_name_col = 10;
else
    bus_name_col = 2;
end
if sort_buses
    [numbus, i] = sortrows(numbus, 1);
    bus_name = data.bus.txt(i, bus_name_col);
else
    bus_name = data.bus.txt(:, bus_name_col);
end
if rev < 24     %% includes loads
    bus(:, [BUS_I BUS_TYPE PD QD GS BS BUS_AREA VM VA BASE_KV ZONE]) = ...
        numbus(:, [1:9 11:12]);
elseif rev < 31     %% includes GL, BL
    bus(:, [BUS_I BASE_KV BUS_TYPE GS BS BUS_AREA ZONE VM VA]) = ...
        numbus(:, [1 3 4 5 6 7 8 9 10]);
else                %% fixed shunts and loads are in their own tables
    bus(:, [BUS_I BASE_KV BUS_TYPE BUS_AREA ZONE VM VA]) = ...
        numbus(:, [1 3 4 5 6 8 9]);
    if ncols >= 11 && all(all(~isnan(numbus(:, [10 11]))))
        haveVlims = 1;
        bus(:, [VMAX VMIN]) = numbus(:, [10 11]);
    end
end
if ~haveVlims  %% add default voltage magnitude limits if not provided
    warns{end+1} = sprintf('Using default voltage magnitude limits: VMIN = %g p.u., VMAX = %g p.u.', Vmin, Vmax);
    if verbose
        fprintf('WARNING: No bus voltage magnitude limits provided.\n         Using defaults: VMIN = %g p.u., VMAX = %g p.u.\n', Vmin, Vmax);
    end
    bus(:, VMIN) = Vmin;
    bus(:, VMAX) = Vmax;
end

%% create map of external bus numbers to bus indices
i2e = bus(:, BUS_I);
e2i = sparse(i2e, ones(nb, 1), 1:nb, max(i2e), 1);

%%-----  load data  -----
if rev >= 24
    nld = size(data.load.num, 1);
    loadbus = e2i(data.load.num(:,1));
    %% PSS/E loads are divided into:
    %%  1. constant MVA, (I=1)
    %%  2. constant current (I=I)
    %%  3. constant reactance/resistance (I = I^2)
    %% NOTE: reactive power component of constant admittance load is negative
    %%       quantity for inductive load and positive for capacitive load
    Pd = data.load.num(:,6) + data.load.num(:,8) .* bus(loadbus, VM) ...
            + data.load.num(:,10) .* bus(loadbus, VM).^2;
    Qd = data.load.num(:,7) + data.load.num(:,9) .* bus(loadbus, VM) ...
            - data.load.num(:,11) .* bus(loadbus, VM).^2;
    Cld = sparse(1:nld, loadbus, data.load.num(:,3), nld, nb);    %% only in-service-loads
    bus(:, [PD QD]) = Cld' * [Pd Qd];
end

%%-----  fixed shunt data  -----
if isfield(data, 'shunt')   %% rev > 30
    nsh = size(data.shunt.num, 1);
    shuntbus = e2i(data.shunt.num(:,1));
    Csh = sparse(1:nsh, shuntbus, data.shunt.num(:,3), nsh, nb);  %% only in-service shunts
    bus(:, [GS BS]) = Csh' * data.shunt.num(:, 4:5);
end

%%-----  switched shunt data  -----
nswsh = size(data.swshunt.num, 1);
swshuntbus = e2i(data.swshunt.num(:,1));
Cswsh = sparse(1:nswsh, swshuntbus, 1, nswsh, nb);
if rev <= 27
    bus(:, BS) = bus(:, BS) + Cswsh' * data.swshunt.num(:, 6);
elseif rev <= 29
    bus(:, BS) = bus(:, BS) + Cswsh' * data.swshunt.num(:, 7);
elseif rev < 32
    bus(:, BS) = bus(:, BS) + Cswsh' * data.swshunt.num(:, 8);
else
    bus(:, BS) = bus(:, BS) + Cswsh' * data.swshunt.num(:, 10);
end

%%-----  branch data  -----
nbr = size(data.branch.num, 1);
branch = zeros(nbr, ANGMAX);
branch(:, ANGMIN) = -360;
branch(:, ANGMAX) = 360;
if rev >= 34 && size(data.branch.num, 2) >= 24
    branch(:, [F_BUS BR_R BR_X BR_B RATE_A RATE_B RATE_C]) = ...
        data.branch.num(:, [1 4 5 6 8 9 10]);
    branch(:, BR_STATUS) = data.branch.num(:, 24);
    brsh_f = 20:21;
    brsh_t = 22:23;
    warns{end+1} = sprintf('For PSS/E rev %d branch data, branch names, ratings 4-12, metered end, length, and ownership data were not retained.', rev);
    if verbose
        fprintf('WARNING: For PSS/E rev %d branch data, only ratings 1-3 were retained.\n', rev);
    end
else
    branch(:, [F_BUS BR_R BR_X BR_B RATE_A RATE_B RATE_C]) = ...
        data.branch.num(:, [1 4 5 6 7 8 9]);
    if rev <= 27        %% includes transformer ratio, angle
        branch(:, BR_STATUS) = data.branch.num(:, 16);
        branch(~isnan(data.branch.num(:, 10)), TAP) = ...
            data.branch.num(~isnan(data.branch.num(:, 10)), 10);
        branch(~isnan(data.branch.num(:, 11)), SHIFT) = ...
            data.branch.num(~isnan(data.branch.num(:, 11)), 11);
    else
        branch(:, BR_STATUS)    = data.branch.num(:, 14);
    end
    if rev <= 27
        brsh_f = 12:13;
        brsh_t = 14:15;
    else
        brsh_f = 10:11;
        brsh_t = 12:13;
    end
end
branch(:, T_BUS) = abs(data.branch.num(:, 2));  %% can be negative to indicate metered end
%% integrate branch shunts (explicit shunts, not line-charging)
ibr = (1:nbr)';
fbus = e2i(branch(:, F_BUS));
tbus = e2i(branch(:, T_BUS));
nzf = find(fbus);               %% ignore branches with bad bus numbers
nzt = find(tbus);
if length(nzf) < nbr
    warns{end+1} = sprintf('%d branches have bad ''from'' bus numbers', nbr-length(nzf));
    if verbose
        fprintf('WARNING: %d branches have bad ''from'' bus numbers\n', nbr-length(nzf));
    end
end
if length(nzt) < nbr
    warns{end+1} = sprintf('%d branches have bad ''to'' bus numbers', nbr-length(nzt));
    if verbose
        fprintf('WARNING: %d branches have bad ''to'' bus numbers\n', nbr-length(nzt));
    end
end
Cf = sparse(ibr(nzf), fbus(nzf), branch(nzf, BR_STATUS), nbr, nb);  %% only in-service branches
Ct = sparse(ibr(nzt), tbus(nzt), branch(nzt, BR_STATUS), nbr, nb);  %% only in-service branches
if ~isempty(brsh_f) && size(data.branch.num, 2) >= brsh_t(end)
    bus(:, [GS BS]) = bus(:, [GS BS]) + ...
        Cf' * data.branch.num(:, brsh_f)*baseMVA + ...
        Ct' * data.branch.num(:, brsh_t)*baseMVA;
end

%%-----  system switching device data  -----
if isfield(data, 'swdev') && ~isempty(data.swdev.num)
    nswdev = size(data.swdev.num, 1);
    swdev = data.swdev.num;
    swbranch = zeros(nswdev, ANGMAX);
    swbranch(:, ANGMIN) = -360;
    swbranch(:, ANGMAX) = 360;

    x = swdev(:, 4);
    x(isnan(x)) = 0;
    rates = swdev(:, 5:7);
    rates(isnan(rates)) = 0;
    status = swdev(:, 17);
    status(isnan(status)) = 1;

    swbranch(:, [F_BUS T_BUS]) = [swdev(:, 1) abs(swdev(:, 2))];
    swbranch(:, BR_X) = x;
    swbranch(:, [RATE_A RATE_B RATE_C]) = rates;
    swbranch(:, BR_STATUS) = status;
    branch = [branch; swbranch];

    warns{end+1} = sprintf('Converted %d system switching devices to zero-resistance MATPOWER branches; normal status, switching type, names, and ratings 4-12 were not retained.', nswdev);
    if verbose
        fprintf('WARNING: Converted %d system switching devices to zero-resistance MATPOWER branches.\n', nswdev);
    end
end

%%-----  generator data  -----
ng = size(data.gen.num, 1);
genbus = e2i(data.gen.num(:,1));
gen = zeros(ng, APF);
gen(:, [GEN_BUS PG QG QMAX QMIN VG MBASE GEN_STATUS PMAX PMIN]) = ...
    data.gen.num(:, [1 3 4 5 6 7 9 15 17 18]);

%%-----  transformer data  -----
if rev > 27
    [transformer, bus, warns, bus_name] = psse_convert_xfmr(warns, data.trans2.num, data.trans3.num, verbose, baseMVA, bus, bus_name);
    branch = [branch; transformer];
end

%%-----  two-terminal DC transmission line data  -----
dcline = psse_convert_hvdc(data.twodc.num, bus);

%% assemble MPC
mpc = struct( ...
    'baseMVA',  baseMVA, ...
    'bus', bus, ...
    'bus_name', {bus_name}, ...
    'branch', branch, ...
    'gen', gen ...
);
if ~isempty(dcline)
    mpc.dcline = dcline;
    mpc = toggle_dcline(mpc, 'on');
end
