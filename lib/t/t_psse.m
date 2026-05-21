function t_psse(quiet)
% t_psse - Tests for psse2mpc and related functions.

%   MATPOWER
%   Copyright (c) 2014-2024, Power Systems Engineering Research Center (PSERC)
%   by Ray Zimmerman, PSERC Cornell
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 1
    quiet = 0;
end

num_tests = 206;

t_begin(num_tests, quiet);

raw = 't_psse_case.raw';
case_n = 't_psse_case%d';
casefile = 't_case9_save2psse';
if quiet
    verbose = 0;
else
    verbose = 0;
end
if have_feature('octave')
    if have_feature('octave', 'vnum') >= 4
        file_in_path_warn_id = 'Octave:data-file-in-path';
    else
        file_in_path_warn_id = 'Octave:fopen-file-in-path';
    end
    s1 = warning('query', file_in_path_warn_id);
    warning('off', file_in_path_warn_id);
end

if ~have_feature('regexp_split')
    t_skip(num_tests, 'PSSE2MPC requires newer MATLAB/Octave with regexp split support');
else
    t = '[records, sections] = psse_read() : length(records)';
    [records, sections] = psse_read(raw, verbose);
    t_is(length(records), 11, 12, t);
    t = '[records, sections] = psse_read() : length(sections)';
    t_is(length(sections), 3, 12, t);

    expected = { ...
        {1, 'Line 1   ', 1.1, -0.1, 0.011, 1, 1.1, 'A', '', 'A'}, ...
        {2, 'Line, "2"', 2.2, -0.2, 0.022, 2, 2.2, 'B', '', 'B'}, ...
        {3, 'Line, ''3''', 3.3, -0.3, 0.033, 3, 3.3, 'C', '', 'C'}, ...
        {4, sprintf('Line\t4'), 4.4, -0.4, 0.044, 4, 4.4, 'D', '', 'D'}, ...
    };
    ec = { ...
        ', "comment 1"', ...
        'comment, ''2''', ...
        sprintf('''comment\t3'''), ...
        '//comment,4', ...
    };

    for i = 1:sections(2).last - sections(2).first + 1
        t = sprintf('psse_parse_line(str%d, template) : ', i);
        [d, c] = psse_parse_line(records{i+sections(2).first-1}, 'dsffgDFcsc');
        t_is(length(d), length(expected{i}), 12, [t 'length']);
        for k = 1:length(d)
            if isnumeric(expected{i}{k})
                t_is(d{k}, expected{i}{k}, 12, sprintf('%s col %d', t, k));
            elseif isempty(expected{i}{k})
                t_ok(isempty(d{k}), sprintf('%s col %d', t, k));
            else
                t_str_match(d{k}, expected{i}{k}, sprintf('%s col %d', t, k));
            end
        end
        t_str_match(c, ec{i}, sprintf('%s comment', t));
    end

    t = 'psse_parse_line : missing optional columns : ';
    [d, c] = psse_parse_line(records{1}, 'dsffgDFcscdfgcs');
    t_is(length(d), 15, 12, [t 'length']);
    t_ok(all(cellfun(@isempty, d(11:15))), [t 'all empty']);

    t = 'psse_parse_section : ';
    [d, w] = psse_parse_section({}, records, sections, 2, 0, 'test1', 'dsFfgDF.sc');
    t_ok(isstruct(d) && isfield(d, 'num') && isfield(d, 'txt'), [t 'struct']);
    t_is(size(d.num), [4 11], 12, [t 'size(num)']);
    t_is(size(d.txt), [4 11], 12, [t 'size(txt)']);
    for i = 1:size(d.num, 1)
        for k = 1:size(d.num, 2)-1
            if isnumeric(expected{i}{k})
                t_is(d.num(i,k), expected{i}{k}, 12, sprintf('%s num(%d,%d)', t, i, k));
                t_ok(isempty(d.txt{i,k}), sprintf('%s txt{%d,%d}', t, i, k));
            elseif isempty(expected{i}{k})
                t_ok(isnan(d.num(i,k)), sprintf('%s num(%d,%d)', t, i, k));
                t_ok(isempty(d.txt{i,k}), sprintf('%s txt{%d,%d}', t, i, k));
            else
                t_ok(isnan(d.num(i,k)), sprintf('%s num(%d,%d)', t, i, k));
                t_str_match(d.txt{i,k}, expected{i}{k}, sprintf('%s txt{%d,%d}', t, i, k));
            end
        end
    end

    t = 'psse2mpc : rev 34 headers and switching devices : ';
    raw34 = 't_psse_case4.raw';
    [records34, sections34] = psse_read(raw34, verbose);
    t_is(sections34(1).last, 4, 12, [t 'case ID header']);
    t_ok(strcmp(sections34(2).name, 'SYSTEM-WIDE'), [t 'system-wide section']);
    [data34, w34] = psse_parse(records34, sections34, verbose, 34);
    t_is(data34.id.SBASE, 100, 12, [t 'SBASE']);
    t_ok(isfield(data34, 'system'), [t 'system-wide parsed']);
    t_is(numel(data34.system.records), 3, 12, [t 'system-wide records']);
    t_is(data34.system.solver.SWSHNT, 2, 12, [t 'system-wide SWSHNT']);
    t_is(size(data34.branch.num, 1), 1, 12, [t 'branch rows']);
    t_is(data34.branch.num(1, [8 9 10 24]), [100 90 80 1], 12, [t 'rev 34 branch columns']);
    t_is(size(data34.swdev.num), [3 21], 12, [t 'switching device rows and columns']);
    t_is(data34.swdev.num(:, [1 2 4 17 18 19 20]), ...
        [1 2 1e-4 1 1 1 2; 2 1 1e-4 0 1 2 3; 1 2 1e-4 2 0 2 1], 12, ...
        [t 'switching device core columns']);
    t_is(data34.swdev.num(2, 5:16), [40 30 20 19 18 17 16 15 14 13 12 11], 12, ...
        [t 'switching device RATE1-12']);
    t_is(data34.swdev.num(3, 5:16), [17 16 15 14 13 12 11 10 9 8 7 6], 12, ...
        [t 'switching device stuck-closed RATE1-12']);
    t_is(size(data34.facts.num, 1), 1, 12, [t 'FACTS device rows']);
    t_is(size(data34.facts.num, 2), 22, 12, [t 'FACTS device rev 34 columns']);
    t_str_match(data34.facts.txt{1, 1}, 'FACTS 1     ', [t 'FACTS device name']);
    t_is(data34.facts.num(1, [2 3 4 8 20 22]), [2 0 1 100 2 0], 12, ...
        [t 'FACTS device columns']);
    t_is(size(data34.twodc.num), [2 48], 12, [t 'two-terminal DC rows and columns']);
    t_is(data34.twodc.num(:, [2 3 4 5 6 7 10 11]), ...
        [0 10 100 500 400 10 0 20; 1 10 100 500 400 10 0 20], 12, ...
        [t 'two-terminal DC line control columns']);
    t_is(data34.twodc.num(:, [13 29 30 31 47 48]), ...
        [1 0 0 2 0 0; 1 0 0 2 0 0], 12, ...
        [t 'two-terminal DC terminal columns']);
    t_str_match(data34.twodc.txt{1, 1}, 'DC BLOCK    ', [t 'two-terminal DC blocked name']);
    t_str_match(data34.twodc.txt{2, 9}, 'R', [t 'two-terminal DC meter']);
    t_is(size(data34.trans2.num), [2 52], 12, [t 'transformer rev 34 columns']);
    t_is(data34.trans2.num(:, [7 8 9]), [1 0.01 -0.02; 2 1e6 0.1], 12, ...
        [t 'transformer magnetizing columns']);
    t_is(data34.trans2.num(1, [25 39 40 41 42 43 44 45 46 47 48 49 50 51 52]), ...
        [0 0 0 1.1 0.9 1.1 0.9 33 0 0 0 0 0 1 0], 12, ...
        [t 'transformer control columns']);
    t_is(size(data34.swshunt.num, 1), 2, 12, [t 'switched shunt rows']);
    t_is(size(data34.swshunt.num, 2), 27, 12, [t 'switched shunt rev 34 columns']);
    t_is(data34.swshunt.num(1, [1 2 4 10 11 12]), [2 1 1 12.5 1 12.5], 12, [t 'switched shunt in-service columns']);
    t_is(data34.swshunt.num(2, [1 2 4 10 11 12]), [1 0 0 -99 1 -99], 12, [t 'switched shunt out-of-service columns']);
    t_is(size(data34.impcor.num), [1 4], 12, [t 'impedance correction rows']);
    t_is(data34.impcor.num(1, :), [9 1 1 0], 12, [t 'impedance correction table point']);
    [mpc34, w34] = psse2mpc(raw34, 0, 34);
    t_is(size(mpc34.bus, 1), 2, 12, [t 'bus rows']);
    t_is(size(mpc34.branch, 1), 6, 12, [t 'branch rows with switching devices and transformer']);
    t_is(mpc34.branch(1, [6 7 8 11]), [100 90 80 1], 12, [t 'branch conversion']);
    t_is(mpc34.branch(2:4, [1 2 4 6 7 8 11]), ...
        [1 2 1e-4 70 60 50 1; 2 1 1e-4 40 30 20 0; 1 2 1e-4 17 16 15 1], 12, ...
        [t 'switching device conversion']);
    t_is(mpc34.branch(5:6, [3 4 9 11]), [0 0.1 1 1; 0 0.1 1 1], 12, [t 'NOMV zero transformer conversion']);
    t_is(mpc34.bus(:, [1 5 6]), [1 2 -11.9498743710662; 2 0 12.5], 10, ...
        [t 'switched shunt and transformer magnetizing conversion']);
    t_ok(isfield(mpc34, 'psse') && isfield(mpc34.psse, 'swshunt'), [t 'switched shunt preserved']);
    t_ok(isfield(mpc34.psse, 'swdev'), [t 'switching device preserved']);
    t_is([mpc34.psse.swdev.col.ckt mpc34.psse.swdev.col.rate12 mpc34.psse.swdev.col.name], ...
        [3 16 21], 12, [t 'switching device metadata columns']);
    t_is(size(mpc34.psse.swdev.num), [3 21], 12, [t 'switching device metadata size']);
    t_is(mpc34.psse.swdev.branch_idx, [2; 3; 4], 12, [t 'switching device branch mapping']);
    t_is([mpc34.psse.swdev.f_bus_idx mpc34.psse.swdev.t_bus_idx], ...
        [1 2; 2 1; 1 2], 12, [t 'switching device bus mapping']);
    t_is(mpc34.psse.swdev.rates(2, 4:12), [19 18 17 16 15 14 13 12 11], 12, ...
        [t 'switching device metadata RATE4-12']);
    t_is(mpc34.psse.swdev.status, [1; 0; 2], 12, [t 'switching device raw status']);
    t_is(mpc34.psse.swdev.normal_status, [1; 1; 0], 12, [t 'switching device normal status']);
    t_is(mpc34.psse.swdev.metered_end, [1; 2; 2], 12, [t 'switching device metered end']);
    t_is(mpc34.psse.swdev.stype, [2; 3; 1], 12, [t 'switching device type']);
    t_str_match(mpc34.psse.swdev.ckt{3}, '@3', [t 'switching device CKT']);
    t_str_match(mpc34.psse.swdev.name{2}, 'SW OPEN', [t 'switching device NAME']);
    t_ok(isfield(mpc34.psse, 'twodc'), [t 'two-terminal DC preserved']);
    t_is([mpc34.psse.twodc.col.rdc mpc34.psse.twodc.col.ipi mpc34.psse.twodc.col.xcapi], ...
        [3 31 47], 12, [t 'two-terminal DC metadata columns']);
    t_is([mpc34.psse.twodc.rect_bus_idx mpc34.psse.twodc.inv_bus_idx], ...
        [1 2; 1 2], 12, [t 'two-terminal DC metadata bus mapping']);
    t_is(mpc34.psse.twodc.loss_mw, [0; 0.4], 12, [t 'two-terminal DC metadata loss']);
    t_is(mpc34.dcline(:, [1 2 3 4 5 16 17]), ...
        [1 2 0 0 0 0 0; 1 2 1 100 99.6 0.4 0], 12, ...
        [t 'two-terminal DC dcline conversion']);
    t_ok(isfield(mpc34.psse, 'facts'), [t 'FACTS device preserved']);
    t_is([mpc34.psse.facts.bus_idx mpc34.psse.facts.reg_bus_idx], ...
        [2 2], 12, [t 'FACTS device metadata mapping']);
    t_ok(isfield(mpc34.psse, 'xfmr'), [t 'transformer metadata preserved']);
    t_ok(isfield(mpc34.psse, 'impcor'), [t 'impedance correction preserved']);
    t_is(mpc34.psse.impcor.num(1, :), [9 1 1 0], 12, [t 'impedance correction metadata values']);
    t_is(mpc34.psse.xfmr.two.branch_idx, [5; 6], 12, [t 'transformer branch mapping']);
    t_is(mpc34.psse.xfmr.two.num(1, [39 41 42 43 44 45 46]), ...
        [0 1.1 0.9 1.1 0.9 33 0], 12, [t 'transformer metadata values']);
    t_is(mpc34.psse.system.solver.SWSHNT, 2, 12, [t 'system-wide preserved']);
    t_ok(any(~cellfun(@isempty, strfind(w34, 'system switching devices'))), [t 'switching device warning']);

    t = 'psse2mpc(rawfile, casefile)';
    txt = 'MATPOWER 5.0 using PSSE2MPC on 11-Aug-2014';
    for k = 2:3
        fname = sprintf(case_n, k);
        rawname = sprintf('%s.raw', fname);
        casename = sprintf('%s.m', fname);
        tmpfname = sprintf('%s_%d', fname, fix(1e9*rand));
        tmpcasename = sprintf('%s.m', tmpfname);
        mpc = psse2mpc(rawname, tmpfname, 0);
        reps = {{'e-005', 'e-05', 0}, ...   %% needed on Windoze, who knows why?
                {tmpfname, fname, 0}, ...
                {upper(tmpfname), upper(fname), 0}, ...
                {'MATPOWER (.*) using PSSE2MPC on \d\d-...-\d\d\d\d', txt, 1}};
        t_file_match(tmpcasename, casename, sprintf('%s : %s', t, fname), reps, 1);
    end

    t = 'save2psse -> psse2mpc : ';
    mpc0 = loadcase(casefile);
    tmpfname = sprintf('t_save2psse_%d', fix(1e9*rand));
    tmpfname = save2psse(tmpfname, mpc0);
    mpc = psse2mpc(tmpfname, 0);
    t_is(mpc.bus, mpc0.bus, 12, [t 'bus']);
    t_is(mpc.branch, mpc0.branch, 12, [t 'branch']);
    t_is(mpc.gen, mpc0.gen, 12, [t 'gen']);
    t_is(mpc.dcline, mpc0.dcline, 4, [t 'dcline']);
    t_ok(isequal(mpc.bus_name, mpc0.bus_name), [t 'bus_name']);

    reps = { {'/ ..-...-.... ..:..:.. - MATPOWER ([^\n]*)', ...
              '/ 17-Jan-2019 15:30:41 - MATPOWER 7.0', 1} };
    t_file_match(tmpfname, [casefile '.raw'], 'save2psse: RAW file match', reps, 1);
end

if have_feature('octave')
    warning(s1.state, file_in_path_warn_id);
end

t_end;
