function fname_out = savecase(fname, varargin)
% savecase - Saves a |MATPOWER| case file, given a filename and the data.
% ::
%
%   SAVECASE(FNAME, CASESTRUCT)
%   SAVECASE(FNAME, CASESTRUCT, VERSION)
%   SAVECASE(FNAME, BASEMVA, BUS, GEN, BRANCH)
%   SAVECASE(FNAME, BASEMVA, BUS, GEN, BRANCH, GENCOST)
%   SAVECASE(FNAME, BASEMVA, BUS, GEN, BRANCH, AREAS, GENCOST)
%   SAVECASE(FNAME, COMMENT, CASESTRUCT)
%   SAVECASE(FNAME, COMMENT, CASESTRUCT, VERSION)
%   SAVECASE(FNAME, COMMENT, BASEMVA, BUS, GEN, BRANCH)
%   SAVECASE(FNAME, COMMENT, BASEMVA, BUS, GEN, BRANCH, GENCOST)
%   SAVECASE(FNAME, COMMENT, BASEMVA, BUS, GEN, BRANCH, AREAS, GENCOST)
%
%   FNAME = SAVECASE(FNAME, ...)
%
%   Writes a MATPOWER case file, given a filename and data struct or list of
%   data matrices. The FNAME parameter is the name of the file to be created or
%   overwritten. If FNAME ends with '.mat' it saves the case as a MAT-file
%   otherwise it saves it as an M-file. Optionally returns the filename,
%   with extension added if necessary. The optional COMMENT argument is
%   either string (single line comment) or a cell array of strings which
%   are inserted as comments. When using a MATPOWER case struct, if the
%   optional VERSION argument is '1' it will modify the data matrices to
%   version 1 format before saving.

%   MATPOWER
%   Copyright (c) 1996-2024, Power Systems Engineering Research Center (PSERC)
%   by Carlos E. Murillo-Sanchez, PSERC Cornell & Universidad Nacional de Colombia
%   and Ray Zimmerman, PSERC Cornell
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%% define named indices into bus, gen, branch matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;
[PW_LINEAR, POLYNOMIAL, MODEL, STARTUP, SHUTDOWN, NCOST, COST] = idx_cost;

%% default arguments
if ischar(varargin{1}) || iscell(varargin{1})
    if ischar(varargin{1})
        comment = {varargin{1}};    %% convert char to single element cell array
    else
        comment = varargin{1};
    end
    [args{1:(length(varargin)-1)}] = deal(varargin{2:end});
else
    comment = {''};
    args = varargin;
end
mpc_ver = '2';              %% default MATPOWER case file version
if isstruct(args{1})        %% 1st real argument is a struct
    mpc = args{1};
    if length(args) > 1
        mpc.version = args{2};
        mpc_ver = mpc.version;
    end
    baseMVA = mpc.baseMVA;
    bus     = mpc.bus;
    gen     = mpc.gen;
    branch  = mpc.branch;
    if isfield(mpc, 'areas')
        areas   = mpc.areas;
    end
    if isfield(mpc, 'gencost')
        gencost = mpc.gencost;
    end
else                        %% 1st real argument is NOT a struct
    baseMVA = args{1};
    bus     = args{2};
    gen     = args{3};
    branch  = args{4};
    mpc.baseMVA = baseMVA;
    mpc.bus     = bus;
    mpc.gen     = gen;
    mpc.branch  = branch;
    if length(args) == 5
        gencost = args{5};
        mpc.gencost = gencost;
    end
    if length(args) == 6
        areas   = args{5};
        gencost = args{6};
        mpc.areas   = areas;
        mpc.gencost = gencost;
    end
end

%% modifications for version 1 format
if strcmp(mpc_ver, '1')
    %% remove extra columns of gen
    if size(gen, 2) >= MU_QMIN
        gen = gen(:, [1:PMIN, MU_PMAX:MU_QMIN]);
    else
        gen = gen(:, 1:PMIN);
    end
    %% use the version 1 values for column names
    shift = MU_PMAX - PMIN - 1;
    tmp = num2cell([MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN] - shift);
    [MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN] = deal(tmp{:});

    %% remove extra columns of branch
    if size(branch, 2) >= MU_ST
        branch = branch(:, [1:BR_STATUS, PF:MU_ST]);
    elseif size(branch, 2) >= QT
        branch = branch(:, [1:BR_STATUS, PF:QT]);
    else
        branch = branch(:, 1:BR_STATUS);
    end
    %% use the version 1 values for column names
    shift = PF - BR_STATUS - 1;
    tmp = num2cell([PF, QF, PT, QT, MU_SF, MU_ST] - shift);
    [PF, QF, PT, QT, MU_SF, MU_ST] = deal(tmp{:});
end

%% verify valid filename
[pathstr, fcn_name, extension] = fileparts(fname);
if isempty(extension)
    extension = '.m';
end
if regexp(fcn_name, '\W')
    old_fcn_name = fcn_name;
    fcn_name = regexprep(fcn_name, '\W', '_');
    fprintf('WARNING: ''%s'' is not a valid function name, changed to ''%s''\n', old_fcn_name, fcn_name);
end
fname = fullfile(pathstr, [fcn_name extension]);

%% open and write the file
if strcmp(upper(extension), '.MAT')     %% MAT-file
    if strcmp(mpc_ver, '1')
        if exist('areas', 'var') && exist('gencost', 'var')
            save(fname, 'baseMVA', 'bus', 'gen', 'branch', 'areas', 'gencost');
        else
            save(fname, 'baseMVA', 'bus', 'gen', 'branch');
        end
    else
        save(fname, 'baseMVA', 'mpc');
    end
else                                %% M-file
    %% open file
    [fd, msg] = fopen(fname, 'wt');     %% print it to an M-file
    if fd == -1
        error(['savecase: ', msg]);
    end

    %% function header, etc.
    if strcmp(mpc_ver, '1')
        if exist('areas', 'var') && exist('gencost', 'var') && ~isempty(gencost)
            fprintf(fd, 'function [baseMVA, bus, gen, branch, areas, gencost] = %s\n', fcn_name);
        else
            fprintf(fd, 'function [baseMVA, bus, gen, branch] = %s\n', fcn_name);
        end
        prefix = '';
    else
        fprintf(fd, 'function mpc = %s\n', fcn_name);
        prefix = 'mpc.';
    end
    if isempty(comment{1})
        comment{1} = sprintf('%s', upper(fcn_name));
    else
        comment{1} = sprintf('%s  %s', upper(fcn_name), comment{1});
    end
    for k = 1:length(comment)
        fprintf(fd, '%%%s\n', comment{k});
    end
    fprintf(fd, '\n%%%% MATPOWER Case Format : Version %s\n', mpc_ver);
    if ~strcmp(mpc_ver, '1')
        fprintf(fd, 'mpc.version = ''%s'';\n', mpc_ver);
    end
    fprintf(fd, '\n%%%%-----  Power Flow Data  -----%%%%\n');
    fprintf(fd, '%%%% system MVA base\n');
    fprintf(fd, '%sbaseMVA = %.9g;\n', prefix, baseMVA);

    %% bus data
    ncols = size(bus, 2);
    fprintf(fd, '\n%%%% bus data\n');
    fprintf(fd, '%%\tbus_i\ttype\tPd\tQd\tGs\tBs\tarea\tVm\tVa\tbaseKV\tzone\tVmax\tVmin');
    if ncols >= MU_VMIN             %% opf SOLVED, save with lambda's & mu's
        fprintf(fd, '\tlam_P\tlam_Q\tmu_Vmax\tmu_Vmin');
    end
    fprintf(fd, '\n%sbus = [', prefix);
    if ~isempty(bus)
        fprintf(fd, '\n');
        if ncols < MU_VMIN              %% opf NOT SOLVED, save without lambda's & mu's
            fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g;\n', bus(:, 1:VMIN).');
        else                            %% opf SOLVED, save with lambda's & mu's
            fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.4f\t%.4f\t%.4f\t%.4f;\n', bus(:, 1:MU_VMIN).');
        end
    end
    fprintf(fd, '];\n');

    %% generator data
    ncols = size(gen, 2);
    fprintf(fd, '\n%%%% generator data\n');
    fprintf(fd, '%%\tbus\tPg\tQg\tQmax\tQmin\tVg\tmBase\tstatus\tPmax\tPmin');
    if ~strcmp(mpc_ver, '1')
        fprintf(fd, '\tPc1\tPc2\tQc1min\tQc1max\tQc2min\tQc2max\tramp_agc\tramp_10\tramp_30\tramp_q\tapf');
    end
    if ncols >= MU_QMIN             %% opf SOLVED, save with mu's
        fprintf(fd, '\tmu_Pmax\tmu_Pmin\tmu_Qmax\tmu_Qmin');
    end
    fprintf(fd, '\n%sgen = [', prefix);
    if ~isempty(gen)
        fprintf(fd, '\n');
        if ncols < MU_QMIN              %% opf NOT SOLVED, save without mu's
            if strcmp(mpc_ver, '1')
                fprintf(fd, '\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g;\n', gen(:, 1:PMIN).');
            else
                fprintf(fd, '\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', gen(:, 1:APF).');
            end
        else
            if strcmp(mpc_ver, '1')
                fprintf(fd, '\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.4f\t%.4f\t%.4f\t%.4f;\n', gen(:, 1:MU_QMIN).');
            else
                fprintf(fd, '\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.4f\t%.4f\t%.4f\t%.4f;\n', gen(:, 1:MU_QMIN).');
            end
        end
    end
    fprintf(fd, '];\n');

    %% branch data
    ncols = size(branch, 2);
    fprintf(fd, '\n%%%% branch data\n');
    fprintf(fd, '%%\tfbus\ttbus\tr\tx\tb\trateA\trateB\trateC\tratio\tangle\tstatus');
    if ~strcmp(mpc_ver, '1')
        fprintf(fd, '\tangmin\tangmax');
    end
    if ncols >= QT                  %% power flow SOLVED, save with line flows
        fprintf(fd, '\tPf\tQf\tPt\tQt');
    end
    if ncols >= MU_ST               %% opf SOLVED, save with mu's
        fprintf(fd, '\tmu_Sf\tmu_St');
        if ~strcmp(mpc_ver, '1')
            fprintf(fd, '\tmu_angmin\tmu_angmax');
        end
    end
    fprintf(fd, '\n%sbranch = [', prefix);
    if ~isempty(branch)
        fprintf(fd, '\n');
        if ncols < QT                   %% power flow NOT SOLVED, save without line flows or mu's
            if strcmp(mpc_ver, '1')
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d;\n', branch(:, 1:BR_STATUS).');
            else
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g;\n', branch(:, 1:ANGMAX).');
            end
        elseif ncols < MU_ST            %% power flow SOLVED, save with line flows but without mu's
            if strcmp(mpc_ver, '1')
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.4f\t%.4f\t%.4f\t%.4f;\n', branch(:, 1:QT).');
            else
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.4f\t%.4f\t%.4f\t%.4f;\n', branch(:, 1:QT).');
           end
        else                            %% opf SOLVED, save with lineflows & mu's
            if strcmp(mpc_ver, '1')
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f;\n', branch(:, 1:MU_ST).');
            else
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%d\t%.9g\t%.9g\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f;\n', branch(:, 1:MU_ANGMAX).');
            end
        end
    end
    fprintf(fd, '];\n');

    %% OPF data
    if (exist('areas', 'var') && ~isempty(areas)) || ...
        (exist('gencost', 'var') && ~isempty(gencost))
        fprintf(fd, '\n%%%%-----  OPF Data  -----%%%%');
    end
    if exist('areas', 'var') && ~isempty(areas)
        %% area data
        fprintf(fd, '\n%%%% area data\n');
        fprintf(fd, '%%\tarea\trefbus\n');
        fprintf(fd, '%sareas = [\n', prefix);
        if ~isempty(areas)
            fprintf(fd, '\t%d\t%d;\n', areas(:, 1:2).');
        end
        fprintf(fd, '];\n');
    end
    if exist('gencost', 'var') && ~isempty(gencost)
        %% generator cost data
        fprintf(fd, '\n%%%% generator cost data\n');
        fprintf(fd, '%%\t1\tstartup\tshutdown\tn\tx1\ty1\t...\txn\tyn\n');
        fprintf(fd, '%%\t2\tstartup\tshutdown\tn\tc(n-1)\t...\tc0\n');
        fprintf(fd, '%sgencost = [\n', prefix);
        if ~isempty(gencost)
            n1 = 2 * max(gencost(gencost(:, MODEL) == PW_LINEAR,  NCOST));
            n2 =     max(gencost(gencost(:, MODEL) == POLYNOMIAL, NCOST));
            n = max([n1; n2]);
            if size(gencost, 2) < n + 4
                error('savecase: gencost data claims it has more columns than it does');
            end
            template = '\t%d\t%.9g\t%.9g\t%d';
            for i = 1:n
                template = [template, '\t%.9g'];
            end
            template = [template, ';\n'];
            fprintf(fd, template, gencost(:, 1:n+4).');
        end
        fprintf(fd, '];\n');
    end

    if ~strcmp(mpc_ver, '1')
        %% generalized OPF user data
        if (isfield(mpc, 'A') && ~isempty(mpc.A)) || ...
                (isfield(mpc, 'N') && ~isempty(mpc.N))
            fprintf(fd, '\n%%%%-----  Generalized OPF User Data  -----%%%%');
        end

        %% user constraints
        if isfield(mpc, 'A') && ~isempty(mpc.A)
            %% A
            fprintf(fd, '\n%%%% user constraints\n');
            print_sparse(fd, sprintf('%sA', prefix), mpc.A);
            if isfield(mpc, 'l') && ~isempty(mpc.l) && ...
                    isfield(mpc, 'u') && ~isempty(mpc.u)
                fprintf(fd, 'lbub = [\n');
                fprintf(fd, '\t%.9g\t%.9g;\n', [mpc.l mpc.u].');
                fprintf(fd, '];\n');
                fprintf(fd, '%sl = lbub(:, 1);\n', prefix);
                fprintf(fd, '%su = lbub(:, 2);\n\n', prefix);
            elseif isfield(mpc, 'l') && ~isempty(mpc.l)
                fprintf(fd, '%sl = [\n', prefix);
                fprintf(fd, '\t%.9g;\n', mpc.l);
                fprintf(fd, '];\n\n');
            elseif isfield(mpc, 'u') && ~isempty(mpc.u)
                fprintf(fd, '%su = [\n', prefix);
                fprintf(fd, '\t%.9g;\n', mpc.u);
                fprintf(fd, '];\n');
            end
        end

        %% user costs
        if isfield(mpc, 'N') && ~isempty(mpc.N)
            fprintf(fd, '\n%%%% user costs\n');
            print_sparse(fd, sprintf('%sN', prefix), mpc.N);
            if isfield(mpc, 'H') && ~isempty(mpc.H)
                print_sparse(fd, sprintf('%sH', prefix), mpc.H);
            end
            if isfield(mpc, 'fparm') && ~isempty(mpc.fparm)
                fprintf(fd, 'Cw_fparm = [\n');
                fprintf(fd, '\t%.9g\t%d\t%.9g\t%.9g\t%.9g;\n', [mpc.Cw mpc.fparm].');
                fprintf(fd, '];\n');
                fprintf(fd, '%sCw    = Cw_fparm(:, 1);\n', prefix);
                fprintf(fd, '%sfparm = Cw_fparm(:, 2:5);\n', prefix);
            else
                fprintf(fd, '%sCw = [\n', prefix);
                fprintf(fd, '\t%.9g;\n', mpc.Cw);
                fprintf(fd, '];\n');
            end
        end

        %% user vars
        if isfield(mpc, 'z0') || isfield(mpc, 'zl') || isfield(mpc, 'zu')
            fprintf(fd, '\n%%%% user vars\n');
        end
        if isfield(mpc, 'z0') && ~isempty(mpc.z0)
            fprintf(fd, '%sz0 = [\n', prefix);
            fprintf(fd, '\t%.9g;\n', mpc.z0);
            fprintf(fd, '];\n');
        end
        if isfield(mpc, 'zl') && ~isempty(mpc.zl)
            fprintf(fd, '%szl = [\n', prefix);
            fprintf(fd, '\t%.9g;\n', mpc.zl);
            fprintf(fd, '];\n');
        end
        if isfield(mpc, 'zu') && ~isempty(mpc.zu)
            fprintf(fd, '%szu = [\n', prefix);
            fprintf(fd, '\t%.9g;\n', mpc.zu);
            fprintf(fd, '];\n');
        end

        %% (optional) generator unit types
        if isfield(mpc, 'gentype') && iscell(mpc.gentype)
            ng = length(mpc.gentype);
            if size(mpc.gen, 1) ~= ng
                warning('savecase: gentype field does not have the expected dimensions (length = %d, expected %d)', ng, size(mpc.gen, 1));
            end

            fprintf(fd, '\n%%%% generator unit type (see GENTYPES)\n');
            fprintf(fd, '%sgentype = {\n', prefix);
            for k = 1:ng
                fprintf(fd, '\t''%s'';\n', mpc.gentype{k});
            end
            fprintf(fd, '};\n');
        end

        %% (optional) generator fuel types
        if isfield(mpc, 'genfuel') && iscell(mpc.genfuel)
            ng = length(mpc.genfuel);
            if size(mpc.gen, 1) ~= ng
                warning('savecase: genfuel field does not have the expected dimensions (length = %d, expected %d)', ng, size(mpc.gen, 1));
            end

            fprintf(fd, '\n%%%% generator fuel type (see GENFUELS)\n');
            fprintf(fd, '%sgenfuel = {\n', prefix);
            for k = 1:ng
                fprintf(fd, '\t''%s'';\n', mpc.genfuel{k});
            end
            fprintf(fd, '};\n');
        end

        %% (optional) bus names
        if isfield(mpc, 'bus_name') && iscell(mpc.bus_name)
            nb = length(mpc.bus_name);
            if size(mpc.bus, 1) ~= nb
                warning('savecase: bus_name field does not have the expected dimensions (length = %d, expected %d)', nb, size(mpc.bus, 1));
            end

            fprintf(fd, '\n%%%% bus names\n');
            fprintf(fd, '%sbus_name = {\n', prefix);
            for k = 1:nb
                fprintf(fd, '\t''%s'';\n', strrep(mpc.bus_name{k}, '''', ''''''));
            end
            fprintf(fd, '};\n');
        end

        %%-----  prototype 3-phase data  -----
        %% freq, basekVA
        if isfield(mpc, 'basekVA') && ~isempty(mpc.basekVA)
            fprintf(fd, '\n%%%%-----  3 Phase Model Data  -----%%%%\n');
            fprintf(fd, '%%%% system data\n');
            fprintf(fd, '%sfreq = %.9g;      %%%% frequency, Hz\n', prefix, mpc.freq);
            fprintf(fd, '%sbasekVA = %.9g; %%%% system kVA base\n', prefix, mpc.basekVA);

            %% bus3p
            fprintf(fd, '\n%%%% 3-phase bus data\n');
            fprintf(fd, '%%\tbusid\ttype\tbasekV\tVm1\tVm2\tVm3\tVa1\tVa2\tVa3');
            fprintf(fd, '\n%sbus3p = [', prefix);
            if isfield(mpc, 'bus3p') && ~isempty(mpc.bus3p)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', mpc.bus3p.');
            end
            fprintf(fd, '];\n');

            %% buslink
            fprintf(fd, '\n%%%% buslink data\n');
            fprintf(fd, '%%\tlinkid\tbusid\tbus3pid\tstatus');
            fprintf(fd, '\n%sbuslink = [', prefix);
            if isfield(mpc, 'buslink') && ~isempty(mpc.buslink)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%d\t%d\t%d;\n', mpc.buslink.');
            end
            fprintf(fd, '];\n');

            %% line3p
            fprintf(fd, '\n%%%% 3-phase line data\n');
            fprintf(fd, '%%\tbrid\tfbus\ttbus\tstatus\tlcid\tlen');
            fprintf(fd, '\n%sline3p = [', prefix);
            if isfield(mpc, 'line3p') && ~isempty(mpc.line3p)
                fprintf(fd, '\n');
                line3p = mpc.line3p;
                line3p(:, end) = 5280 * line3p(:, end);
                fprintf(fd, '\t%d\t%d\t%d\t%d\t%d\t%.9g/5280;\n', line3p.');
            end
            fprintf(fd, '];\n');

            %% xfmr3p
            fprintf(fd, '\n%%%% 3-phase transformer data\n');
            fprintf(fd, '%%\txfid\tfbus\ttbus\tstatus\tR\tX\tbasekVA\tbasekV\tratio');
            fprintf(fd, '\n%sxfmr3p = [', prefix);
            if isfield(mpc, 'xfmr3p') && ~isempty(mpc.xfmr3p)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%d\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', mpc.xfmr3p.');
            end
            fprintf(fd, '];\n');

            %% shunt3p
            fprintf(fd, '\n%%%% 3-phase shunt data\n');
            fprintf(fd, '%%\tshid\tshbus\tstatus\tgs1\tgs2\tgs3\tbs1\tbs2\tbs3');
            fprintf(fd, '\n%sshunt3p = [', prefix);
            if isfield(mpc, 'shunt3p') && ~isempty(mpc.shunt3p)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', mpc.shunt3p.');
            end
            fprintf(fd, '];\n');

            %% load3p
            fprintf(fd, '\n%%%% 3-phase load data\n');
            fprintf(fd, '%%\tldid\tldbus\tstatus\tPd1\tPd2\tPd3\tldpf1\tldpf2\tldpf3');
            fprintf(fd, '\n%sload3p = [', prefix);
            if isfield(mpc, 'load3p') && ~isempty(mpc.load3p)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', mpc.load3p.');
            end
            fprintf(fd, '];\n');

            %% gen3p
            fprintf(fd, '\n%%%% 3-phase generator data\n');
            fprintf(fd, '%%\tgenid\tgbus\tstatus\tVg1\tVg2\tVg3\tPg1\tPg2\tPg3\tQg1\tQg2\tQg3');
            fprintf(fd, '\n%sgen3p = [', prefix);
            if isfield(mpc, 'gen3p') && ~isempty(mpc.gen3p)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%d\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', mpc.gen3p.');
            end
            fprintf(fd, '];\n');

            %% lc
            fprintf(fd, '\n%%%% line construction data\n');
            fprintf(fd, '%%\tlcid\tR11\tR21\tR31\tR22\tR32\tR33\tX11\tX21\tX31\tX22\tX32\tX33\tC11\tC21\tC31\tC22\tC32\tC33');
            fprintf(fd, '\n%slc = [', prefix);
            if isfield(mpc, 'lc') && ~isempty(mpc.lc)
                fprintf(fd, '\n');
                fprintf(fd, '\t%d\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g\t%.9g;\n', mpc.lc.');
            end
            fprintf(fd, '];\n');
        end

        %% VSC-MTDC data
        print_vsc_mtdc(fd, prefix, mpc);

        %% execute userfcn callbacks for 'savecase' stage
        if isfield(mpc, 'userfcn')
            run_userfcn(mpc.userfcn, 'savecase', mpc, fd, prefix);
        end
    end

    %% close file
    if fd ~= 1
        fclose(fd);
    end
end

if nargout > 0
    fname_out = fname;
end



function print_vsc_mtdc(fd, prefix, mpc)

if isfield(mpc, 'busdc') || isfield(mpc, 'branchdc') || isfield(mpc, 'vsc')
    fprintf(fd, '\n%%%%-----  VSC-MTDC Data  -----%%%%');
end

if isfield(mpc, 'busdc')
    ncols = size(mpc.busdc, 2);
    names = {'busdc_i', 'status', 'Vdc', 'baseKVdc', 'Pdc', 'Idc'};
    fprintf(fd, '\n%%%% DC bus data\n');
    print_header(fd, names, ncols);
    print_matrix(fd, sprintf('%sbusdc', prefix), mpc.busdc);
end

if isfield(mpc, 'branchdc')
    ncols = size(mpc.branchdc, 2);
    names = {'fbusdc', 'tbusdc', 'r', 'status', ...
        'Pfdc', 'Ptdc', 'Ifdc', 'Itdc'};
    fprintf(fd, '\n%%%% DC branch data\n');
    print_header(fd, names, ncols);
    print_matrix(fd, sprintf('%sbranchdc', prefix), mpc.branchdc);
end

if isfield(mpc, 'vsc')
    ncols = size(mpc.vsc, 2);
    names = {'acbus', 'busdc', 'status', 'ac_mode', 'dc_mode', ...
        'Pac_set', 'Qac_set', 'Vac_set', 'Pdc_set', 'Vdc_set', 'Kdroop', ...
        'lossA', 'lossB', 'lossC', ...
        'tr_r', 'tr_x', 'tr_b', 'tr_shift', ...
        'tr_rateA', 'tr_rateB', 'tr_rateC', ...
        'filter_g', 'filter_b', ...
        'reactor_r', 'reactor_x', 'reactor_b', ...
        'reactor_rateA', 'reactor_rateB', 'reactor_rateC', ...
        'Pac', 'Qac', 'Pdc', 'Vdc', 'VacPCC', 'VacFilter', ...
        'VacInternal', 'Ploss', 'PtrLoss', 'PreactorLoss', ...
        'is_dc_slack', 'filter_bus', 'internal_bus', ...
        'tr_branch', 'reactor_branch'};
    fprintf(fd, '\n%%%% VSC converter data\n');
    print_header(fd, names, ncols);
    print_matrix(fd, sprintf('%svsc', prefix), mpc.vsc);
end

if isfield(mpc, 'vsc_capability') && ...
        is_vsc_capability_case_data(mpc.vsc_capability)
    fprintf(fd, '\n%%%% VSC capability metadata\n');
    print_case_value(fd, sprintf('%svsc_capability', prefix), ...
        mpc.vsc_capability);
end

if isfield(mpc, 'vsc_hvdc_dispatch')
    fprintf(fd, '\n%%%% VSC/HVDC dispatch metadata\n');
    print_case_value(fd, sprintf('%svsc_hvdc_dispatch', prefix), ...
        mpc.vsc_hvdc_dispatch);
end


function print_header(fd, names, ncols)

fprintf(fd, '%%');
for k = 1:min(ncols, length(names))
    fprintf(fd, '\t%s', names{k});
end
for k = length(names)+1:ncols
    fprintf(fd, '\tcol%d', k);
end
fprintf(fd, '\n');


function print_matrix(fd, varname, A)

ncols = size(A, 2);
fprintf(fd, '%s = [', varname);
if ~isempty(A)
    fprintf(fd, '\n');
    template = repmat('\t%.9g', 1, ncols);
    fprintf(fd, [template, ';\n'], A.');
end
fprintf(fd, '];\n');


function TorF = is_vsc_capability_case_data(v)

TorF = ~(isstruct(v) && isfield(v, 'elements') && ...
    isfield(v, 'violations'));


function ok = print_case_value(fd, varname, val)

if isstruct(val)
    ok = print_case_struct(fd, varname, val);
    return;
end

[ok, code] = case_value_code(val);
if ok
    fprintf(fd, '%s = %s;\n', varname, code);
end


function ok = print_case_struct(fd, varname, s)

if ~isscalar(s)
    ok = 0;
    warning('savecase: skipping non-scalar struct field ''%s''', varname);
    return;
end

ok = 1;
fprintf(fd, '%s = struct();\n', varname);
fields = fieldnames(s);
for k = 1:length(fields)
    fname = fields{k};
    ok = print_case_value(fd, sprintf('%s.%s', varname, fname), s.(fname)) && ok;
end


function [ok, code] = case_value_code(val)

ok = 1;
if isnumeric(val) || islogical(val)
    code = mat2str(val, 15);
elseif ischar(val)
    code = sprintf('''%s''', strrep(val, '''', ''''''));
elseif iscell(val)
    [ok, code] = cell_value_code(val);
else
    ok = 0;
    code = '';
end


function [ok, code] = cell_value_code(val)

ok = 1;
if isempty(val)
    sz = size(val);
    if length(sz) == 2
        code = sprintf('cell(%d, %d)', sz(1), sz(2));
    else
        code = '{}';
    end
    return;
end
if ndims(val) > 2
    ok = 0;
    code = '';
    return;
end

rows = cell(size(val, 1), 1);
for i = 1:size(val, 1)
    cols = cell(1, size(val, 2));
    for j = 1:size(val, 2)
        [ok1, cols{j}] = case_value_code(val{i, j});
        ok = ok && ok1;
    end
    rows{i} = strjoin(cols, ', ');
end
code = ['{' strjoin(rows, '; ') '}'];


function print_sparse(fd, varname, A)

[i, j, s] = find(A);
[m, n] = size(A);

if isempty(s)
    fprintf(fd, '%s = sparse(%d, %d);\n', varname, m, n);
else
    fprintf(fd, 'ijs = [\n');
    if m == 1           %% i, j, s are row vectors
        fprintf(fd, '\t%d\t%d\t%.9g;\n', [i; j; s]);
    else                %% i, j, s are column vectors
        fprintf(fd, '\t%d\t%d\t%.9g;\n', [i j s].');
    end
    fprintf(fd, '];\n');
    fprintf(fd, '%s = sparse(ijs(:, 1), ijs(:, 2), ijs(:, 3), %d, %d);\n', varname, m, n);
end
