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
[swshunt_binit_col, swshunt_status_col, swshunt_cols] = psse_swshunt_columns(rev);

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
if nswsh
    swshuntbus = e2i(data.swshunt.num(:,1));
    binit = data.swshunt.num(:, swshunt_binit_col);
    binit(isnan(binit)) = 0;
    if swshunt_status_col && size(data.swshunt.num, 2) >= swshunt_status_col
        swshunt_status = data.swshunt.num(:, swshunt_status_col);
        swshunt_status(isnan(swshunt_status)) = 1;
    else
        swshunt_status = ones(nswsh, 1);
    end
    Cswsh = sparse(1:nswsh, swshuntbus, swshunt_status ~= 0, nswsh, nb);
    bus(:, BS) = bus(:, BS) + Cswsh' * binit;
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
swdev_branch_idx = zeros(0, 1);
if isfield(data, 'swdev') && ~isempty(data.swdev.num)
    nswdev = size(data.swdev.num, 1);
    swdev_cols = psse_swdev_colnames(data.swdev);
    swdev_col = psse_col_struct(swdev_cols);
    swdev_branch_idx = nbr + (1:nswdev)';
    swbranch = zeros(nswdev, ANGMAX);
    swbranch(:, ANGMIN) = -360;
    swbranch(:, ANGMAX) = 360;

    f_bus_ext = parsed_col(data.swdev, swdev_col.i, NaN);
    j_signed = parsed_col(data.swdev, swdev_col.j, NaN);
    t_bus_ext = abs(j_signed);
    x = parsed_col(data.swdev, swdev_col.x, 0);
    x(isnan(x)) = 0;
    rates = psse_swdev_rates(data.swdev, swdev_col);
    status = parsed_col(data.swdev, swdev_col.stat, 1);
    status(isnan(status)) = 1;

    swbranch(:, [F_BUS T_BUS]) = [f_bus_ext t_bus_ext];
    swbranch(:, BR_X) = x;
    swbranch(:, [RATE_A RATE_B RATE_C]) = rates(:, 1:3);
    swbranch(:, BR_STATUS) = status ~= 0;
    branch = [branch; swbranch];

    warns{end+1} = sprintf('Converted %d system switching devices to zero-resistance MATPOWER branches; PSS/E metadata is preserved in mpc.psse.swdev.', nswdev);
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
xfmr_info = [];
xfmr_branch_offset = size(branch, 1);
if isfield(data, 'impcor')
    impcor = data.impcor;
else
    impcor = [];
end
if rev > 27
    [transformer, bus, warns, bus_name, xfmr_info] = psse_convert_xfmr( ...
        warns, data.trans2.num, data.trans3.num, verbose, baseMVA, ...
        bus, bus_name, impcor);
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
mpc.psse.rev = rev;
mpc.psse.swshunt = struct( ...
    'colnames', {swshunt_cols}, ...
    'num', data.swshunt.num, ...
    'txt', {data.swshunt.txt}, ...
    'binit_col', swshunt_binit_col, ...
    'status_col', swshunt_status_col ...
);
if isfield(data, 'gen')
    mpc.psse.genq = psse_genq_metadata(data.gen, mpc, rev);
end
if isfield(data, 'system')
    mpc.psse.system = data.system;
end
if isfield(data, 'swdev')
    mpc.psse.swdev = psse_swdev_metadata(data.swdev, mpc, swdev_branch_idx);
end
if isfield(data, 'impcor')
    mpc.psse.impcor = data.impcor;
end
if isfield(data, 'twodc')
    mpc.psse.twodc = psse_twodc_metadata(data.twodc, dcline, mpc);
end
if isfield(data, 'facts')
    mpc.psse.facts = psse_facts_metadata(data.facts, mpc);
end
if rev > 27
    mpc.psse.xfmr = psse_xfmr_metadata(data, xfmr_info, xfmr_branch_offset, rev);
end
if ~isempty(dcline)
    mpc.dcline = dcline;
    mpc = toggle_dcline(mpc, 'on');
end

function genq = psse_genq_metadata(data, mpc, rev)
% psse_genq_metadata - Preserves PSS/E generator voltage-control metadata.

cols = psse_genq_columns(size(data.num, 2));
col = psse_col_struct(cols);
n = size(data.num, 1);

bus_ext = parsed_col(data, col.i, NaN);
id = parsed_txt(data, col.id, n);
reg_bus_ext = parsed_col(data, col.ireg, 0);
local = isnan(reg_bus_ext) | reg_bus_ext == 0;
reg_bus_ext(local) = bus_ext(local);

genq = struct( ...
    'rev', rev, ...
    'colnames', {cols}, ...
    'num', data.num, ...
    'txt', {data.txt}, ...
    'col', col, ...
    'raw_row_idx', (1:n)', ...
    'gen_idx', (1:n)', ...
    'bus_idx', psse_bus_map(mpc, bus_ext), ...
    'bus_ext', bus_ext, ...
    'reg_bus_idx', psse_bus_map(mpc, reg_bus_ext), ...
    'reg_bus_ext', reg_bus_ext, ...
    'id', {id}, ...
    'status', parsed_col(data, col.stat, 1), ...
    'vs', parsed_col(data, col.vs, NaN), ...
    'rmpct', parsed_col(data, col.rmpct, 100), ...
    'qmax', parsed_col(data, col.qt, NaN), ...
    'qmin', parsed_col(data, col.qb, NaN), ...
    'qg', parsed_col(data, col.qg, NaN), ...
    'ireg_col', col.ireg, ...
    'rmpct_col', col.rmpct ...
);

function cols = psse_genq_columns(ncols)
% psse_genq_columns - Returns PSS/E generator column metadata.

cols = {'I', 'ID', 'PG', 'QG', 'QT', 'QB', 'VS', 'IREG', ...
    'MBASE', 'ZR', 'ZX', 'RT', 'XT', 'GTAP', 'STAT', 'RMPCT', ...
    'PT', 'PB', 'O1', 'F1', 'O2', 'F2', 'O3', 'F3', 'O4', 'F4', ...
    'WMOD', 'WPF'};
for k = length(cols)+1:ncols
    cols{end+1} = sprintf('COL%d', k);
end

function v = parsed_col(data, col, default)
% parsed_col - Parses a numeric column from num first, then txt.

n = size(data.num, 1);
v = default * ones(n, 1);
if ~col || col > max(size(data.num, 2), size(data.txt, 2))
    return;
end
if col <= size(data.num, 2)
    num = data.num(:, col);
    ok = ~isnan(num);
    v(ok) = num(ok);
else
    ok = false(n, 1);
end
if col <= size(data.txt, 2)
    for kk = 1:n
        if ok(kk)
            continue;
        end
        str = data.txt{kk, col};
        if isempty(str)
            continue;
        end
        if numel(str) >= 2 && ((str(1) == '''' && str(end) == '''') || ...
                (str(1) == '"' && str(end) == '"'))
            str = str(2:end-1);
        end
        num = str2double(strtrim(str));
        if ~isnan(num)
            v(kk) = num;
        end
    end
end

function txt = parsed_txt(data, col, n)
% parsed_txt - Returns dequoted text for a preserved RAW column.

txt = cell(n, 1);
for kk = 1:n
    txt{kk} = '';
end
if ~col || col > size(data.txt, 2)
    return;
end
for kk = 1:n
    str = data.txt{kk, col};
    if isempty(str) && col <= size(data.num, 2) && ~isnan(data.num(kk, col))
        str = sprintf('%g', data.num(kk, col));
    end
    if numel(str) >= 2 && ((str(1) == '''' && str(end) == '''') || ...
            (str(1) == '"' && str(end) == '"'))
        str = str(2:end-1);
    end
    txt{kk} = strtrim(str);
end

function twodc = psse_twodc_metadata(data, dcline, mpc)
% psse_twodc_metadata - Preserves PSS/E two-terminal DC metadata.

c = idx_dcline;
cols = psse_twodc_columns(size(data.num, 2));
col = psse_col_struct(cols);
n = size(data.num, 1);
rect_bus_idx = zeros(n, 1);
inv_bus_idx = zeros(n, 1);
loss_mw = zeros(n, 1);
if n
    rect_bus_idx = psse_bus_map(mpc, data.num(:, col.ipr));
    inv_bus_idx = psse_bus_map(mpc, data.num(:, col.ipi));
    if ~isempty(dcline)
        loss_mw = dcline(:, c.LOSS0) + dcline(:, c.LOSS1) .* dcline(:, c.PF);
    end
end

twodc = struct( ...
    'colnames', {cols}, ...
    'num', data.num, ...
    'txt', {data.txt}, ...
    'col', col, ...
    'dcline_idx', (1:n)', ...
    'rect_bus_idx', rect_bus_idx, ...
    'inv_bus_idx', inv_bus_idx, ...
    'loss_mw', loss_mw ...
);

function cols = psse_twodc_columns(ncols)
% psse_twodc_columns - Returns PSS/E two-terminal DC column metadata.

cols = {'NAME', 'MDC', 'RDC', 'SETVL', 'VSCHD', 'VCMOD', ...
    'RCOMP', 'DELTI', 'METER', 'DCVMIN', 'CCCITMX', 'CCCACC', ...
    'IPR', 'NBR', 'ANMXR', 'ANMNR', 'RCR', 'XCR', 'EBASR', ...
    'TRR', 'TAPR', 'TMXR', 'TMNR', 'STPR', 'ICR', 'IFR', ...
    'ITR', 'IDR', 'XCAPR', 'NDR', 'IPI', 'NBI', 'ANMXI', ...
    'ANMNI', 'RCI', 'XCI', 'EBASI', 'TRI', 'TAPI', 'TMXI', ...
    'TMNI', 'STPI', 'ICI', 'IFI', 'ITI', 'IDI', 'XCAPI', 'NDI'};
for k = length(cols)+1:ncols
    cols{end+1} = sprintf('COL%d', k);
end

function facts = psse_facts_metadata(data, mpc)
% psse_facts_metadata - Preserves PSS/E FACTS device metadata.

cols = data.colnames;
col = psse_col_struct(cols);
n = size(data.num, 1);
bus_idx = zeros(n, 1);
reg_bus_idx = zeros(n, 1);
if n
    bus_idx = psse_bus_map(mpc, data.num(:, col.i));
    fcreg = data.num(:, col.fcreg);
    fcreg(isnan(fcreg) | fcreg == 0) = data.num(isnan(fcreg) | fcreg == 0, col.i);
    reg_bus_idx = psse_bus_map(mpc, fcreg);
end

facts = struct( ...
    'colnames', {cols}, ...
    'num', data.num, ...
    'txt', {data.txt}, ...
    'col', col, ...
    'bus_idx', bus_idx, ...
    'reg_bus_idx', reg_bus_idx ...
);

function swdev = psse_swdev_metadata(data, mpc, branch_idx)
% psse_swdev_metadata - Preserves PSS/E system switching device metadata.

cols = psse_swdev_colnames(data);
col = psse_col_struct(cols);
n = size(data.num, 1);

f_bus_ext = parsed_col(data, col.i, NaN);
j_signed = parsed_col(data, col.j, NaN);
t_bus_ext = abs(j_signed);
rates = psse_swdev_rates(data, col);
status = parsed_col(data, col.stat, 1);
normal_status = parsed_col(data, col.nstat, 1);
metered_end = parsed_col(data, col.met, 1);
stype = parsed_col(data, col.stype, NaN);

swdev = struct( ...
    'colnames', {cols}, ...
    'num', data.num, ...
    'txt', {data.txt}, ...
    'col', col, ...
    'raw_row_idx', (1:n)', ...
    'branch_idx', branch_idx(:), ...
    'f_bus_ext', f_bus_ext, ...
    't_bus_ext', t_bus_ext, ...
    'j_signed', j_signed, ...
    'f_bus_idx', psse_bus_map(mpc, f_bus_ext), ...
    't_bus_idx', psse_bus_map(mpc, t_bus_ext), ...
    'ckt', {parsed_txt(data, col.ckt, n)}, ...
    'name', {parsed_txt(data, col.name, n)}, ...
    'status', status, ...
    'normal_status', normal_status, ...
    'metered_end', metered_end, ...
    'stype', stype, ...
    'x', parsed_col(data, col.x, 0), ...
    'rates', rates ...
);
if isfield(col, 'rsetnam')
    swdev.rsetnam = parsed_txt(data, col.rsetnam, n);
end

function rates = psse_swdev_rates(data, col)
% psse_swdev_rates - Returns RATE1-RATE12 values, zero-filled when absent.

n = size(data.num, 1);
rates = zeros(n, 12);
for k = 1:12
    name = sprintf('rate%d', k);
    if isfield(col, name)
        rates(:, k) = parsed_col(data, col.(name), 0);
    end
end
rates(isnan(rates)) = 0;

function cols = psse_swdev_colnames(data)
% psse_swdev_colnames - Returns system switching device column names.

if isfield(data, 'colnames') && ~isempty(data.colnames)
    cols = data.colnames;
else
    ncols = max(size(data.num, 2), size(data.txt, 2));
    if ncols == 10
        cols = {'I', 'J', 'CKT', 'X', 'RSETNAM', 'STAT', ...
            'NSTAT', 'MET', 'STYPE', 'NAME'};
    else
        cols = {'I', 'J', 'CKT', 'X'};
        for k = 1:12
            cols{end+1} = sprintf('RATE%d', k);
        end
        cols = [cols {'STAT', 'NSTAT', 'MET', 'STYPE', 'NAME'}];
    end
end

function xfmr = psse_xfmr_metadata(data, info, branch_offset, rev)
% psse_xfmr_metadata - Preserves PSS/E transformer control metadata.

[two_cols, three_cols, two_col, three_col] = psse_xfmr_columns(rev, ...
    size(data.trans2.num, 2), size(data.trans3.num, 2));

nt2 = size(data.trans2.num, 1);
nt3 = size(data.trans3.num, 1);
two_branch_idx = NaN(nt2, 1);
three_branch_idx = NaN(nt3, 3);
two_tab_applied = false(nt2, 1);
three_tab_applied = false(nt3, 3);
two_tab_factor = complex(NaN(nt2, 1));
three_tab_factor = complex(NaN(nt3, 3));
two_nominal_rx = NaN(nt2, 2);
three_nominal_rx = NaN(nt3, 3, 2);
if ~isempty(info)
    if ~isempty(info.two.raw_idx)
        two_branch_idx(info.two.raw_idx) = branch_offset + info.two.branch_idx;
        two_tab_applied(info.two.raw_idx) = info.two.tab_applied;
        two_tab_factor(info.two.raw_idx) = info.two.tab_factor;
        two_nominal_rx(info.two.raw_idx, :) = info.two.nominal_rx;
    end
    if ~isempty(info.three.raw_idx)
        three_branch_idx(info.three.raw_idx, :) = branch_offset + info.three.branch_idx;
        three_tab_applied(info.three.raw_idx, :) = info.three.tab_applied;
        three_tab_factor(info.three.raw_idx, :) = info.three.tab_factor;
        three_nominal_rx(info.three.raw_idx, :, :) = info.three.nominal_rx;
    end
end

xfmr = struct( ...
    'two', struct( ...
        'colnames', {two_cols}, ...
        'num', data.trans2.num, ...
        'txt', {data.trans2.txt}, ...
        'branch_idx', two_branch_idx, ...
        'tab_applied', two_tab_applied, ...
        'tab_factor', two_tab_factor, ...
        'nominal_rx', two_nominal_rx, ...
        'col', two_col), ...
    'three', struct( ...
        'colnames', {three_cols}, ...
        'num', data.trans3.num, ...
        'txt', {data.trans3.txt}, ...
        'branch_idx', three_branch_idx, ...
        'tab_applied', three_tab_applied, ...
        'tab_factor', three_tab_factor, ...
        'nominal_rx', three_nominal_rx, ...
        'col', three_col) ...
);

function [two_cols, three_cols, two_col, three_col] = psse_xfmr_columns(rev, nc2, nc3)
% psse_xfmr_columns - Returns preserved transformer column metadata.

base_cols = {'I', 'J', 'K', 'CKT', 'CW', 'CZ', 'CM', 'MAG1', ...
    'MAG2', 'NMETR', 'NAME', 'STAT', 'O1', 'F1', 'O2', 'F2', ...
    'O3', 'F3', 'O4', 'F4'};
base3_cols = [base_cols {'ZCOD'}];
z_cols = {'R1_2', 'X1_2', 'SBASE1_2'};
z3_cols = {'R1_2', 'X1_2', 'SBASE1_2', 'R2_3', 'X2_3', ...
    'SBASE2_3', 'R3_1', 'X3_1', 'SBASE3_1', 'VMSTAR', 'ANSTAR'};

if rev >= 34 || nc2 >= 52 || nc3 >= 112
    w1 = psse_xfmr_winding_cols(1, 12, 1);
    w2 = psse_xfmr_winding_cols(2, 12, 1);
    w3 = psse_xfmr_winding_cols(3, 12, 1);
else
    w1 = psse_xfmr_winding_cols(1, 3, 0);
    w2 = psse_xfmr_winding_cols(2, 3, 0);
    w3 = psse_xfmr_winding_cols(3, 3, 0);
end

two_cols = [base_cols z_cols w1 {'WINDV2', 'NOMV2'}];
if nc3 >= 113
    three_cols = [base3_cols z3_cols w1 w2 w3];
else
    three_cols = [base_cols z3_cols w1 w2 w3];
end
two_col = psse_xfmr_col_struct(two_cols);
three_col = psse_xfmr_col_struct(three_cols);

function cols = psse_xfmr_winding_cols(w, nrates, include_node)
% psse_xfmr_winding_cols - Returns one winding column-name block.

cols = {sprintf('WINDV%d', w), sprintf('NOMV%d', w), sprintf('ANG%d', w)};
for k = 1:nrates
    cols{end+1} = sprintf('RATE%d%d', k, w);
end
cols = [cols {sprintf('COD%d', w), sprintf('CONT%d', w)}];
cols = [cols {sprintf('RMA%d', w), sprintf('RMI%d', w), ...
    sprintf('VMA%d', w), sprintf('VMI%d', w), sprintf('NTP%d', w), ...
    sprintf('TAB%d', w), sprintf('CR%d', w), sprintf('CX%d', w)}];
if include_node
    cols = [cols {sprintf('CNXA%d', w), sprintf('NOD%d', w)}];
end

function col = psse_xfmr_col_struct(cols)
% psse_xfmr_col_struct - Builds case-insensitive name-to-column struct.

col = struct();
for k = 1:length(cols)
    name = lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'));
    col.(name) = k;
end

function col = psse_col_struct(cols)
% psse_col_struct - Builds a case-insensitive name-to-column struct.

col = struct();
for k = 1:length(cols)
    name = lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'));
    col.(name) = k;
end

function idx = psse_bus_map(mpc, bus)
% psse_bus_map - Maps external bus numbers to MPC bus rows.

[~, ~, ~, ~, BUS_I] = idx_bus;
idx = zeros(size(bus));
[tf, loc] = ismember(bus, mpc.bus(:, BUS_I));
idx(tf) = loc(tf);

function [binit_col, status_col, cols] = psse_swshunt_columns(rev)
% psse_swshunt_columns - Returns PSS/E switched shunt column metadata.

if rev <= 27
    cols = {'I', 'MODSW', 'VSWHI', 'VSWLO', 'SWREG', 'BINIT'};
    binit_col = 6;
    status_col = 0;
elseif rev <= 29
    cols = {'I', 'MODSW', 'VSWHI', 'VSWLO', 'SWREG', 'RMIDNT', 'BINIT'};
    binit_col = 7;
    status_col = 0;
elseif rev < 32
    cols = {'I', 'MODSW', 'VSWHI', 'VSWLO', 'SWREG', 'NREG', 'RMIDNT', 'BINIT'};
    binit_col = 8;
    status_col = 0;
elseif rev < 34
    cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', 'SWREM', ...
        'RMPCT', 'RMIDNT', 'BINIT', ...
        'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
        'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8'};
    binit_col = 10;
    status_col = 4;
elseif rev < 35
    cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', 'SWREG', ...
        'RMPCT', 'RMIDNT', 'BINIT', ...
        'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
        'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
    binit_col = 10;
    status_col = 4;
elseif rev < 36
    cols = {'I', 'ID', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
        'SWREG', 'NREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
        'S1', 'N1', 'B1', 'S2', 'N2', 'B2', 'S3', 'N3', 'B3', ...
        'S4', 'N4', 'B4', 'S5', 'N5', 'B5', 'S6', 'N6', 'B6', ...
        'S7', 'N7', 'B7', 'S8', 'N8', 'B8'};
    binit_col = 12;
    status_col = 5;
else
    cols = {'I', 'ID', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
        'SWREG', 'NREG', 'RMPCT', 'RMIDNT', 'BINIT', 'NAME', ...
        'S1', 'N1', 'B1', 'S2', 'N2', 'B2', 'S3', 'N3', 'B3', ...
        'S4', 'N4', 'B4', 'S5', 'N5', 'B5', 'S6', 'N6', 'B6', ...
        'S7', 'N7', 'B7', 'S8', 'N8', 'B8'};
    binit_col = 12;
    status_col = 5;
end
