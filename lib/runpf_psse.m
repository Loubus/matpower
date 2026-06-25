function [MVAbase, bus, gen, branch, success, et] = ...
                runpf_psse(casedata, mpopt, fname, solvedcase)
% runpf_psse - Runs a power flow with opt-in PSS/E controls.
% ::
%
%   [RESULTS, SUCCESS] = RUNPF_PSSE(CASEDATA, MPOPT, FNAME, SOLVEDCASE)
%
%   Runs a power flow using the standard MATPOWER power flow implementation
%   with the mp.xt_psse extension enabled. This provides PSS/E-specific
%   control behavior through MP-Core, while leaving RUNPF unchanged.
%   Explicit VSC-MTDC cases with BUSDC, BRANCHDC and VSC data are routed
%   through the VSC-MTDC PF solver from this PSS/E-aware entry point; the
%   VSC equations are MATPOWER AC/DC/VSC equations, not a full PSS/E VSC
%   HVDC device replica.
%
%   Currently, the PSS/E-specific behavior implemented for RUNPF_PSSE is
%   voltage control for generator Q limits/remote regulation, PSS/E
%   low-voltage constant MVA load behavior, transformer taps, FACTS STATCON
%   devices, switched shunts, and opt-in two-terminal DC LCC equivalents
%   preserved from PSS/E RAW data in MPC.PSSE.
%   Difficult mixed-control cases can additionally opt in to the coordinated
%   active-set fallback with MPOPT.EXP.PSSE_COORDINATED_ACTIVE_SET = 1. This
%   fallback is disabled by default and records its diagnostics under
%   RESULTS.PSSE.COORDINATED_ACTIVE_SET when it is attempted.
%
%   Inputs (all are optional):
%       CASEDATA : either a MATPOWER case struct or a string containing
%           the name of the file with the case data (default is 'case9')
%           (see CASEFORMAT and LOADCASE)
%       MPOPT : MATPOWER options struct to override default options
%           can be used to specify the solution algorithm, output options
%           termination tolerances, and more (see MPOPTION).
%       FNAME : name of a file to which the pretty-printed output will
%           be appended
%       SOLVEDCASE : name of file to which the solved case will be saved
%           in MATPOWER case format (M-file will be assumed unless the
%           specified name ends with '.mat')
%
%   Outputs (all are optional):
%       RESULTS : results struct, with the following fields:
%           (all fields from the input MATPOWER case, i.e. bus, branch,
%               gen, etc., but with solved voltages, power flows, etc.)
%           order - info used in external <-> internal data conversion
%           et - elapsed time in seconds
%           success - success flag, 1 = succeeded, 0 = failed
%       SUCCESS : the success flag can additionally be returned as
%           a second output argument
%
%   Calling syntax options:
%       results = runpf_psse;
%       results = runpf_psse(casedata);
%       results = runpf_psse(casedata, mpopt);
%       results = runpf_psse(casedata, mpopt, fname);
%       results = runpf_psse(casedata, mpopt, fname, solvedcase);
%       [results, success] = runpf_psse(...);
%
%       Alternatively, for compatibility with previous versions of MATPOWER,
%       some of the results can be returned as individual output arguments:
%
%       [baseMVA, bus, gen, branch, success, et] = runpf_psse(...);
%
%   If the pf.enforce_q_lims option is set to true (default is false) then, if
%   any generator reactive power limit is violated after running the AC power
%   flow, the corresponding bus is converted to a PQ bus, with Qg at the
%   limit, and the case is re-run. The voltage magnitude at the bus will
%   deviate from the specified value in order to satisfy the reactive power
%   limit. If the reference bus is converted to PQ, the first remaining PV
%   bus will be used as the slack bus for the next iteration. This may
%   result in the real power output at this generator being slightly off
%   from the specified values.
%
%   Examples:
%       results = runpf_psse('case30');
%       results = runpf_psse('case30', mpoption('pf.enforce_q_lims', 1));
%
% See also runpf, mp.xt_psse, mp.task_pf_psse.

%   MATPOWER
%   Copyright (c) 1996-2024, Power Systems Engineering Research Center (PSERC)
%   by Ray Zimmerman, PSERC Cornell
%   Enforcing of generator Q limits inspired by contributions
%   from Mu Lin, Lincoln University, New Zealand (1/14/05).
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%%-----  initialize  -----
%% define named indices into bus, gen, branch matrices
[PQ, PV, REF, ~, ~, BUS_TYPE, ~, ~, GS, ~, ~, VM, VA] = idx_bus;
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, PF, QF, PT, QT] = idx_brch;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;
dci = idx_dcline;

%% default arguments
if nargin < 4
    solvedcase = '';                %% don't save solved case
    if nargin < 3
        fname = '';                 %% don't print results to a file
        if nargin < 2
            mpopt = mpoption;       %% use default options
            if nargin < 1
                casedata = 'case9'; %% default data file is 'case9.m'
            end
        end
    end
end

%% activate PSS/E power flow extension
mpopt = mp.psse_mpx_options(mpopt);

%% options
qlim = mpopt.pf.enforce_q_lims;         %% enforce Q limits on gens?
dc = strcmpi(mpopt.model, 'DC');        %% use DC formulation?

%% read data and apply common PSS/E solver/control preparation
mpc = loadcase(casedata);
[mpc, psse_prep, mpopt, mpc_psse_source] = ...
    mp.psse_prepare_case(mpc, mpopt, 'pf');
psse_solver_policy = psse_prep.solver_policy;
swdev_collapse = psse_prep.swdev_collapse;
branch_collapse = psse_prep.branch_collapse;

%% explicit VSC-MTDC cases use the selected VSC-MTDC PF
if has_vsc_mtdc(mpc)
    if ~isfield(mpopt, 'vsc_mtdc') || isempty(mpopt.vsc_mtdc)
        mpopt.vsc_mtdc = struct();
    end
    vsc_method = 'unified';
    if isfield(mpopt.vsc_mtdc, 'method') && ~isempty(mpopt.vsc_mtdc.method)
        vsc_method = lower(mpopt.vsc_mtdc.method);
    end
    if strcmp(vsc_method, 'unified')
        if isfield(mpopt.vsc_mtdc, 'ac_solver')
            mpopt.vsc_mtdc = rmfield(mpopt.vsc_mtdc, 'ac_solver');
        end
        mpopt.vsc_mtdc.psse_aware = 1;
        task_class = 'unified_vsc_mtdc';
        formulation = 'PSS/E-aware unified VSC-MTDC PF with MATPOWER AC/DC/VSC equations';
    else
        mpopt.vsc_mtdc.ac_solver = 'runpf_psse';
        task_class = 'sequential_vsc_mtdc';
        formulation = 'Sequential VSC-MTDC PF with runpf_psse AC subproblem';
    end
    [results, success] = runpf_vsc_mtdc(mpc, mpopt, '', '');
    if ~isfield(results, 'psse') || isempty(results.psse)
        results.psse = struct();
    end
    if isfield(mpc, 'psse') && isfield(mpc.psse, 'solver_options')
        results.psse.solver_options = mpc.psse.solver_options;
    end
    results.psse.pf = struct( ...
        'entrypoint', 'runpf_psse', ...
        'task_class', task_class, ...
        'prepare', psse_prep, ...
        'formulation', formulation);
    if ~isempty(branch_collapse) && isfield(branch_collapse, 'active') && ...
            branch_collapse.active && ~psse_keep_branch_collapsed(mpopt) && ...
            ~isempty(which('mp.psse_branch_expand'))
        results = mp.psse_branch_expand(results, branch_collapse);
        results.psse.pf.output_topology = 'original_branch_expanded';
    end
    if ~isempty(swdev_collapse) && isfield(swdev_collapse, 'active') && ...
            swdev_collapse.active && ~psse_keep_swdev_collapsed(mpopt) && ...
            ~isempty(which('mp.psse_swdev_expand'))
        results = mp.psse_swdev_expand(results, swdev_collapse);
        results.psse.pf.output_topology = 'original_swdev_expanded';
    end
    if fname
        [fd, msg] = fopen(fname, 'at');
        if fd == -1
            error(msg);
        else
            if mpopt.out.all == 0
                printpf(results, fd, mpoption(mpopt, 'out.all', -1));
            else
                printpf(results, fd, mpopt);
            end
            fclose(fd);
        end
    end
    printpf(results, 1, mpopt);
    if ~isempty(solvedcase)
        savecase(solvedcase, results);
    end
    if nargout == 1 || nargout == 2
        MVAbase = results;
        bus = success;
    elseif nargout > 2
        [MVAbase, bus, gen, branch, et] = ...
            deal(results.baseMVA, results.bus, results.gen, results.branch, results.et);
    end
    return;
end

%% use MP-Core?
have_mp_core = have_feature('mp_core');
use_mp_core = 0;
if have_mp_core && ~mpopt.exp.use_legacy_core
    alg = upper(mpopt.pf.alg);
    if dc || (strcmp(alg, 'DEFAULT') || strcmp(alg, 'NR') || ...
              strcmp(alg, 'NR-SP') || strcmp(alg, 'NR-SC') || ...
              strcmp(alg, 'NR-IP') || strcmp(alg, 'NR-IC') || ...
              strcmp(alg, 'FDXB') || strcmp(alg, 'FDBX') || ...
              strcmp(alg, 'FSOLVE') || strcmp(alg, 'GS') || ...
              strcmp(alg, 'ZG')) && ...
              mpopt.pf.v_cartesian ~= 2
        use_mp_core = 1;
    end
end
if ~use_mp_core
    error('runpf_psse: PSS/E power flow requires MP-Core-compatible power flow options.');
end

%% shortcut formulation options via Newton solver name
if ~dc
    alg = upper(mpopt.pf.alg);
    switch alg
        case 'NR-SP'
            mpopt = mpoption(mpopt, 'pf.current_balance', 0, 'pf.v_cartesian', 0);
        case 'NR-SC'
            mpopt = mpoption(mpopt, 'pf.current_balance', 0, 'pf.v_cartesian', 1);
        case 'NR-SH'
            mpopt = mpoption(mpopt, 'pf.current_balance', 0, 'pf.v_cartesian', 2);
        case 'NR-IP'
            mpopt = mpoption(mpopt, 'pf.current_balance', 1, 'pf.v_cartesian', 0);
        case 'NR-IC'
            mpopt = mpoption(mpopt, 'pf.current_balance', 1, 'pf.v_cartesian', 1);
        case 'NR-IH'
            mpopt = mpoption(mpopt, 'pf.current_balance', 1, 'pf.v_cartesian', 2);
    end
end

%% add zero columns to branch for flows if needed
if size(mpc.branch,2) < QT
  mpc.branch = [ mpc.branch zeros(size(mpc.branch, 1), QT-size(mpc.branch,2)) ];
end

%% convert to internal indexing
mpc = ext2int(mpc, mpopt);
t0 = tic;
if use_mp_core
    task_class = @mp.task_pf_legacy;    %% set default task class

    %% get and apply extensions
    if isfield(mpopt.exp, 'mpx') && ~isempty(mpopt.exp.mpx)
        mpx = mpopt.exp.mpx;
        if ~iscell(mpx)
            mpx = { mpx };
        end
    else
        mpx = {};
    end
    for k = 1:length(mpx)
        task_class = mpx{k}.task_class(task_class, mpopt);
    end

    %% create and run task
    pf = task_class();
    pf.run(mpc, mpopt, mpx);
    [mpc, success] = pf.legacy_post_run(mpopt);
    mpc = psse_sync_task_reports(mpc, pf);
    if dc
        its = 1;
    elseif pf.nm.np ~= 0
        its = pf.mm.soln.output.iterations;
    else
        its = 0;
    end
else

[baseMVA, bus, gen, branch] = deal(mpc.baseMVA, mpc.bus, mpc.gen, mpc.branch);

if ~isempty(mpc.bus)
    %% get bus index lists of each type of bus
    [ref, pv, pq] = bustypes(bus, gen);

    %% generator info
    on = find(gen(:, GEN_STATUS) > 0);      %% which generators are on?
    gbus = gen(on, GEN_BUS);                %% what buses are they at?

    %%-----  run the power flow  -----
    its = 0;            %% total iterations
    if mpopt.verbose > 0
        v = mpver('all');
        fprintf('\nMATPOWER Version %s, %s', v.Version, v.Date);
    end

    if dc                               %% DC formulation
        if mpopt.verbose > 0
          fprintf(' -- DC Power Flow\n');
        end
        its = 1;

        %% initial state
        Va0 = bus(:, VA) * (pi/180);

        %% build B matrices and phase shift injections
        [B, Bf, Pbusinj, Pfinj] = makeBdc(baseMVA, bus, branch);

        %% compute complex bus power injections (generation - load)
        %% adjusted for phase shifters and real shunts
        Pbus = real(makeSbus(baseMVA, bus, gen)) - Pbusinj - bus(:, GS) / baseMVA;

        %% "run" the power flow
        [Va, success] = dcpf(B, Pbus, Va0, ref, pv, pq);

        %% update data matrices with solution
        branch(:, [QF, QT]) = zeros(size(branch, 1), 2);
        branch(:, PF) = (Bf * Va + Pfinj) * baseMVA;
        branch(:, PT) = -branch(:, PF);
        bus(:, VM) = ones(size(bus, 1), 1);
        bus(:, VA) = Va * (180/pi);

        %% update Pg for slack generator (1st gen at ref bus)
        %% (note: other gens at ref bus are accounted for in Pbus)
        %%      Pg = Pinj + Pload + Gs
        %%      newPg = oldPg + newPinj - oldPinj
        refgen = zeros(size(ref));
        for k = 1:length(ref)
            temp = find(gbus == ref(k));
            refgen(k) = on(temp(1));
        end
        gen(refgen, PG) = gen(refgen, PG) + (B(ref, :) * Va - Pbus(ref)) * baseMVA;
    else                                %% AC formulation
        if mpopt.verbose > 0
            switch alg
                case {'NR', 'NR-SP'}
                    solver = 'Newton';
                case 'NR-SC'
                    solver = 'Newton-SC';
                case 'NR-SH'
                    solver = 'Newton-SH';
                case 'NR-IP'
                    solver = 'Newton-IP';
                case 'NR-IC'
                    solver = 'Newton-IC';
                case 'NR-IH'
                    solver = 'Newton-IH';
                case 'FDXB'
                    solver = 'fast-decoupled, XB';
                case 'FDBX'
                    solver = 'fast-decoupled, BX';
                case 'FSOLVE'
                    solver = 'fsolve';
                case 'GS'
                    solver = 'Gauss-Seidel';
                case 'ZG'
                    solver = 'Implicit Z-bus Gauss';
                case 'PQSUM'
                    solver = 'Power Summation';
                case 'ISUM'
                    solver = 'Current Summation';
                case 'YSUM'
                    solver = 'Admittance Summation';
                otherwise
                    solver = 'unknown';
            end
            fprintf(' -- AC Power Flow (%s)\n', solver);
        end
        switch alg
            case {'NR', 'NR-SP', 'NR-SC', 'NR-SH', 'NR-IP', 'NR-IC', 'NR-IH', 'FSOLVE'}  %% all 6 variants supported
            otherwise                   %% only power balance, polar is valid
                if mpopt.pf.current_balance || mpopt.pf.v_cartesian
                    error('runpf: power flow algorithm ''%s'' only supports power balance, polar version\nI.e. both ''pf.current_balance'' and ''pf.v_cartesian'' must be set to 0.', alg);
                end
        end
        if have_zip_loads(mpopt)
            if mpopt.pf.current_balance || mpopt.pf.v_cartesian
                warnstr = 'Newton algorithm (current or cartesian/hybrid versions) do';
            elseif strcmp(alg, 'GS')
                warnstr = 'Gauss-Seidel algorithm does';
            elseif strcmp(alg, 'ZG')
                warnstr = 'Implicit Z-bus Gauss algorithm does';
            else
                warnstr = '';
            end
            if warnstr
                warning('runpf: %s not support ZIP load model. Converting to constant power loads.', warnstr);
                mpopt = mpoption(mpopt, 'exp.sys_wide_zip_loads', ...
                                struct('pw', [], 'qw', []));
            end
        end

        %% initial state
        % V0    = ones(size(bus, 1), 1);            %% flat start
        V0  = bus(:, VM) .* exp(1j * pi/180 * bus(:, VA));
        vcb = ones(size(V0));           %% create mask of voltage-controlled buses
        vcb(pq) = 0;                    %% exclude PQ buses
        k = find(vcb(gbus));            %% in-service gens at v-c buses
        V0(gbus(k)) = gen(on(k), VG) ./ abs(V0(gbus(k))).* V0(gbus(k));

        if qlim
            ref0 = ref;                         %% save index and angle of
            Varef0 = bus(ref0, VA);             %%   original reference bus(es)
            limited = false(size(gen, 1), 1);   %% mask of gens @ Q lims
            fixedQg = zeros(size(gen, 1), 1);   %% Qg of gens at Q limits
        end

        %% build admittance matrices
        [Ybus, Yf, Yt] = makeYbus(baseMVA, bus, branch);

        repeat = 1;
        while (repeat)
            %% run the power flow
            %% function for computing V dependent complex bus power injections
            %% (generation - load)
            Sbus = @(Vm)makeSbus(baseMVA, bus, gen, mpopt, Vm);

            switch alg
                case {'NR', 'NR-SP', 'NR-SC', 'NR-SH', 'NR-IP', 'NR-IC', 'NR-IH'}
                    if mpopt.pf.current_balance
                        switch mpopt.pf.v_cartesian
                            case 0                  %% current, polar
                                newtonpf_fcn = @newtonpf_I_polar;
                            case 1                  %% current, cartesian
                                newtonpf_fcn = @newtonpf_I_cart;
                            case 2                  %% current, hybrid
                                newtonpf_fcn = @newtonpf_I_hybrid;
                        end
                    else
                        switch mpopt.pf.v_cartesian
                            case 0                  %% default - power, polar
                                newtonpf_fcn = @newtonpf;
                            case 1                  %% power, cartesian
                                newtonpf_fcn = @newtonpf_S_cart;
                            case 2                  %% power, hybrid
                                newtonpf_fcn = @newtonpf_S_hybrid;
                        end
                    end
                    [V, success, iterations] = newtonpf_fcn(Ybus, Sbus, V0, ref, pv, pq, mpopt);
                case {'FDXB', 'FDBX'}
                    [Bp, Bpp] = makeB(baseMVA, bus, branch, alg);
                    [V, success, iterations] = fdpf(Ybus, Sbus, V0, Bp, Bpp, ref, pv, pq, mpopt);
                case 'GS'
                    [V, success, iterations] = gausspf(Ybus, Sbus([]), V0, ref, pv, pq, mpopt);
                case 'ZG'
                    %% get B matrix for updating Q at PV buses
                    if isempty(pv)
                        Bpp = [];
                    else
                        [~, Bpp] = makeB(baseMVA, bus, branch, 'FDBX');
                    end
                    [V, success, iterations] = zgausspf(Ybus, Sbus([]), V0, ref, pv, pq, Bpp, mpopt);
                case {'PQSUM', 'ISUM', 'YSUM'}
                    [mpc, success, iterations] = radial_pf(mpc, mpopt);
                otherwise
                    error('runpf: ''%s'' is not a valid power flow algorithm. See ''pf.alg'' details in MPOPTION help.', alg);
            end

            %% update data matrices with solution
            switch alg
                case {'NR', 'NR-SP', 'NR-SC', 'NR-SH', 'NR-IP', 'NR-IC', 'NR-IH', 'FDXB', 'FDBX', 'FSOLVE', 'GS', 'ZG'}
                    [bus, gen, branch] = pfsoln(baseMVA, bus, gen, branch, Ybus, Yf, Yt, V, ref, pv, pq, mpopt);
                case {'PQSUM', 'ISUM', 'YSUM'}
                    [bus, gen, branch] = deal(mpc.bus, mpc.gen, mpc.branch);
            end
            its = its + iterations;

            if success && qlim      %% enforce generator Q limits
                %% find gens with violated Q constraints
                mx = find( gen(:, GEN_STATUS) > 0 ...
                        & gen(:, QG) > gen(:, QMAX) + mpopt.opf.violation );
                mn = find( gen(:, GEN_STATUS) > 0 ...
                        & gen(:, QG) < gen(:, QMIN) - mpopt.opf.violation );

                if ~isempty(mx) || ~isempty(mn)  %% we have some Q limit violations
                    %% first check for INFEASIBILITY
                    infeas = union(mx', mn')';  %% transposes handle fact that
                        %% union of scalars is a row vector
                    remaining = find( gen(:, GEN_STATUS) > 0 & ...
                                    ( bus(gen(:, GEN_BUS), BUS_TYPE) == PV | ...
                                      bus(gen(:, GEN_BUS), BUS_TYPE) == REF ));
                    if length(infeas) == length(remaining) && all(infeas == remaining) && ...
                            (isempty(mx) || isempty(mn))
                        %% all remaining PV/REF gens are violating AND all are
                        %% violating same limit (all violating Qmin or all Qmax)
                        if mpopt.verbose
                            fprintf('All %d remaining gens exceed their Q limits : INFEASIBLE PROBLEM\n', length(infeas));
                        end
                        success = 0;
                        break;
                    end

                    %% one at a time?
                    if qlim == 2    %% fix largest violation, ignore the rest
                        [~, k] = max([gen(mx, QG) - gen(mx, QMAX);
                                         gen(mn, QMIN) - gen(mn, QG)]);
                        if k > length(mx)
                            mn = mn(k-length(mx));
                            mx = [];
                        else
                            mx = mx(k);
                            mn = [];
                        end
                    end

                    if mpopt.verbose && ~isempty(mx)
                        fprintf('Gen %d at upper Q limit, converting to PQ bus\n', mx);
                    end
                    if mpopt.verbose && ~isempty(mn)
                        fprintf('Gen %d at lower Q limit, converting to PQ bus\n', mn);
                    end

                    %% save corresponding limit values
                    fixedQg(mx) = gen(mx, QMAX);
                    fixedQg(mn) = gen(mn, QMIN);
                    limited_gens = [mx; mn];

                    %% convert to PQ bus
                    gen(limited_gens, QG) = fixedQg(limited_gens);  %% set Qg to binding limit
                    if length(ref) > 1 && any(bus(gen(limited_gens, GEN_BUS), BUS_TYPE) == REF)
                        error('runpf: Sorry, MATPOWER cannot enforce Q limits for slack buses in systems with multiple slacks.');
                    end
                    bus(gen(limited_gens, GEN_BUS), BUS_TYPE) = PQ; %% & set bus type to PQ

                    %% update bus index lists of each type of bus
                    ref_temp = ref;
                    [ref, pv, pq] = bustypes(bus, gen);
                    %% previous line can modify lists to select new REF bus
                    %% if there was none, so we should update bus with these
                    %% just to keep them consistent
                    if ref ~= ref_temp
                        bus(ref, BUS_TYPE) = REF;
                        bus( pv, BUS_TYPE) = PV;
                        if mpopt.verbose
                            fprintf('Bus %d is new slack bus\n', ...
                                mpc.order.bus.i2e(ref));
                        end
                    end
                    limited(limited_gens) = true;
                    V0 = V;     %% start next solve with current solution
                else
                    repeat = 0; %% no more generator Q limits violated
                end
            else
                repeat = 0;     %% don't enforce generator Q limits, once is enough
            end
        end
        if qlim && any(limited)
            if ref ~= ref0
                %% adjust voltage angles to make original ref bus correct
                bus(:, VA) = bus(:, VA) - bus(ref0, VA) + Varef0;
            end
        end
    end
else
    success = 0;
    its = 0;
    if mpopt.verbose
        fprintf('Power flow not valid : MATPOWER case contains no connected buses\n');
    end
end
[mpc.bus, mpc.gen, mpc.branch] = deal(bus, gen, branch);

end %% if use_mp_core

mpc.et = toc(t0);
mpc.success = success;
mpc.iterations = its;

%%-----  output results  -----
%% convert back to original bus numbering & print results
results = int2ext(mpc);
if ~isempty(branch_collapse) && isfield(branch_collapse, 'active') && ...
        branch_collapse.active && ~psse_keep_branch_collapsed(mpopt) && ...
        ~isempty(which('mp.psse_branch_expand'))
    results = mp.psse_branch_expand(results, branch_collapse);
end
if ~isempty(swdev_collapse) && isfield(swdev_collapse, 'active') && ...
        swdev_collapse.active && ~psse_keep_swdev_collapsed(mpopt) && ...
        ~isempty(which('mp.psse_swdev_expand'))
    results = mp.psse_swdev_expand(results, swdev_collapse);
end
if isfield(results, 'psse')
    results.psse.solver_options = psse_solver_policy;
end
if ~success && use_mp_core && psse_swdev_retry_needed(swdev_collapse)
    mpc_retry = mpc_psse_source;
    if isfield(mpc_retry, 'psse') && isfield(mpc_retry.psse, 'swdev')
        mpc_retry.psse = rmfield(mpc_retry.psse, 'swdev');
    end
    retry_results = runpf_psse(mpc_retry, mpopt);
    if isstruct(retry_results) && isfield(retry_results, 'success') && ...
            retry_results.success
        results = retry_results;
        success = 1;
        if isfield(results, 'psse')
            results.psse.swdev_collapse_fallback = struct( ...
                'attempted', 1, ...
                'accepted', 1, ...
                'collapsed_branches', length(swdev_collapse.collapsed_branch_idx));
        end
    end
end
if ~success && use_mp_core && ...
        psse_twodc_aux_voltage_retry_needed(results, mpopt)
    retry_mpopt = mpopt;
    retry_mpopt.exp.psse_twodc_coupled_voltage = 0;
    retry_results = runpf_psse(mpc_psse_source, retry_mpopt);
    if isstruct(retry_results) && isfield(retry_results, 'success') && ...
            retry_results.success
        results = retry_results;
        success = 1;
        if ~isfield(results, 'psse') || isempty(results.psse)
            results.psse = struct();
        end
        results.psse.twodc_coupled_voltage_fallback = struct( ...
            'attempted', 1, ...
            'accepted', 1, ...
            'reason', 'mixed_control_nonsettlement');
    elseif isfield(results, 'psse')
        results.psse.twodc_coupled_voltage_fallback = struct( ...
            'attempted', 1, ...
            'accepted', 0, ...
            'reason', 'mixed_control_nonsettlement');
    end
end
cas_needed = 0;
cas_trigger = '';
if ~success && use_mp_core
    [cas_needed, cas_trigger] = ...
        psse_coordinated_active_set_needed(results, mpc_psse_source);
end
if cas_needed && psse_coordinated_active_set_enabled(mpopt) && ...
        ~isempty(which('mp.psse_coordinated_active_set'))
    cas_failure = results.psse.control_failure;
    [cas_results, cas_success, cas_report] = ...
        mp.psse_coordinated_active_set(mpc_psse_source, mpopt);
    cas_report.trigger = cas_trigger;
    cas_report.original_control_failure = cas_failure;
    if cas_success
        results = cas_results;
        success = 1;
        results.success = 1;
        if ~isfield(results, 'psse') || isempty(results.psse)
            results.psse = struct();
        end
        if ~isfield(results.psse, 'coordinated_active_set') || ...
                isempty(results.psse.coordinated_active_set)
            results.psse.coordinated_active_set = cas_report;
        else
            results.psse.coordinated_active_set.trigger = cas_trigger;
            results.psse.coordinated_active_set.original_control_failure = ...
                cas_failure;
        end
    elseif isfield(results, 'psse')
        results.psse.coordinated_active_set = cas_report;
    end
end
if success && use_mp_core && isfield(results, 'dcline') && ...
        isfield(results, 'psse') && isfield(results.psse, 'twodc') && ...
        isfield(results.psse.twodc, 'control')
    ctrl = results.psse.twodc.control;
    if isfield(results.psse.twodc, 'dcline_idx')
        k = results.psse.twodc.dcline_idx(:);
    else
        k = (1:length(ctrl.pf))';
    end
    src = (1:length(k))';
    ok = k > 0 & k <= size(results.dcline, 1) & src <= length(ctrl.pf);
    if any(ok)
        dst = k(ok);
        src = src(ok);
        results.dcline(dst, dci.PF) = ctrl.pf(src);
        results.dcline(dst, dci.PT) = ctrl.pt(src);
        if isfield(ctrl, 'qacr_mvar') && isfield(ctrl, 'qaci_mvar')
            results.dcline(dst, dci.QF) = -ctrl.qacr_mvar(src);
            results.dcline(dst, dci.QT) = -ctrl.qaci_mvar(src);
        end
        results.dcline(dst, dci.LOSS0) = ctrl.loss_mw(src);
        results.dcline(dst, dci.LOSS1) = 0;
        if isfield(results, 'order') && isfield(results.order, 'ext') && ...
                isfield(results.order.ext, 'dcline')
            results.order.ext.dcline(dst, dci.PF) = ctrl.pf(src);
            results.order.ext.dcline(dst, dci.PT) = ctrl.pt(src);
            if isfield(ctrl, 'qacr_mvar') && isfield(ctrl, 'qaci_mvar')
                results.order.ext.dcline(dst, dci.QF) = -ctrl.qacr_mvar(src);
                results.order.ext.dcline(dst, dci.QT) = -ctrl.qaci_mvar(src);
            end
            results.order.ext.dcline(dst, dci.LOSS0) = ctrl.loss_mw(src);
            results.order.ext.dcline(dst, dci.LOSS1) = 0;
        end
    end
end

if success && use_mp_core && isfield(results, 'psse') && ...
        isfield(results.psse, 'genq') && isfield(results.psse.genq, 'control')
    ctrl = results.psse.genq.control;
    if isfield(ctrl, 'gen_idx') && isfield(ctrl, 'qmax') && isfield(ctrl, 'qmin')
        for k = 1:length(ctrl.gen_idx)
            gi = ctrl.gen_idx(k);
            if gi > 0 && gi <= size(results.gen, 1)
                results.gen(gi, QMAX) = ctrl.qmax(k);
                results.gen(gi, QMIN) = ctrl.qmin(k);
            end
        end
    end
end

if success && use_mp_core && ...
        ~(isfield(results, 'psse') && ...
        isfield(results.psse, 'coordinated_active_set')) && ...
        ~(isfield(results, 'psse') && ...
        isfield(results.psse, 'swdev_collapse_fallback'))
    results.om = pf.mm;
end

%% zero out result fields of out-of-service gens & branches
if ~isempty(results.order.gen.status.off)
  results.gen(results.order.gen.status.off, [PG QG]) = 0;
end
if ~isempty(results.order.branch.status.off)
  results.branch(results.order.branch.status.off, [PF QF PT QT]) = 0;
end

if fname
    [fd, msg] = fopen(fname, 'at');
    if fd == -1
        error(msg);
    else
        if mpopt.out.all == 0
            printpf(results, fd, mpoption(mpopt, 'out.all', -1));
        else
            printpf(results, fd, mpopt);
        end
        fclose(fd);
    end
end
printpf(results, 1, mpopt);

%% save solved case
if solvedcase
    savecase(solvedcase, results);
end

if nargout == 1 || nargout == 2
    MVAbase = results;
    bus = success;
elseif nargout > 2
    [MVAbase, bus, gen, branch, et] = ...
        deal(results.baseMVA, results.bus, results.gen, results.branch, results.et);
% else  %% don't define MVAbase, so it doesn't print anything
end

function TorF = have_zip_loads(mpopt)
if (~isempty(mpopt.exp.sys_wide_zip_loads.pw) && ...
        any(mpopt.exp.sys_wide_zip_loads.pw(2:3))) || ...
        (~isempty(mpopt.exp.sys_wide_zip_loads.qw) && ...
        any(mpopt.exp.sys_wide_zip_loads.qw(2:3)))
    TorF = 1;
else
    TorF = 0;
end

function TorF = psse_swdev_retry_needed(swdev_collapse)
TorF = ~isempty(swdev_collapse) && isfield(swdev_collapse, 'active') && ...
    swdev_collapse.active;

function TorF = psse_twodc_aux_voltage_retry_needed(results, mpopt)
TorF = 0;
if isfield(mpopt, 'exp') && isfield(mpopt.exp, 'psse_twodc_coupled_voltage') && ...
        ~isempty(mpopt.exp.psse_twodc_coupled_voltage) && ...
        ~any(mpopt.exp.psse_twodc_coupled_voltage(:))
    return;
end
if ~isfield(results, 'psse') || ~isfield(results.psse, 'twodc') || ...
        ~isfield(results.psse.twodc, 'control') || ...
        ~isfield(results.psse.twodc.control, 'ac_pf_status') || ...
        ~strcmp(results.psse.twodc.control.ac_pf_status, 'coupled_solution')
    return;
end
if ~isfield(results.psse, 'control_failure') || ...
        ~isfield(results.psse.control_failure, 'stage') || ...
        ~strcmp(results.psse.control_failure.stage, 'control_settlement')
    return;
end
TorF = 1;

function TorF = psse_keep_swdev_collapsed(mpopt)
TorF = isfield(mpopt, 'exp') && ...
    isfield(mpopt.exp, 'psse_keep_swdev_collapsed') && ...
    ~isempty(mpopt.exp.psse_keep_swdev_collapsed) && ...
    any(mpopt.exp.psse_keep_swdev_collapsed(:));

function TorF = psse_keep_branch_collapsed(mpopt)
TorF = isfield(mpopt, 'exp') && ...
    isfield(mpopt.exp, 'psse_keep_branch_collapsed') && ...
    ~isempty(mpopt.exp.psse_keep_branch_collapsed) && ...
    any(mpopt.exp.psse_keep_branch_collapsed(:));

function mpc = psse_sync_task_reports(mpc, pf)
if isprop(pf, 'psse_xfmr') && ~isempty(pf.psse_xfmr) && ...
        isstruct(pf.psse_xfmr) && isfield(mpc, 'psse') && ...
        isfield(mpc.psse, 'xfmr')
    mpc.psse.xfmr.control = mp.psse_xfmr_report(pf.psse_xfmr);
end

function TorF = psse_coordinated_active_set_enabled(mpopt)
TorF = isfield(mpopt, 'exp') && ...
    isfield(mpopt.exp, 'psse_coordinated_active_set') && ...
    ~isempty(mpopt.exp.psse_coordinated_active_set) && ...
    any(mpopt.exp.psse_coordinated_active_set(:));

function [TorF, trigger] = psse_coordinated_active_set_needed(results, mpc)
TorF = 0;
trigger = '';
if ~isfield(results, 'psse') || ...
        ~isfield(results.psse, 'control_failure') || ...
        ~isfield(results.psse.control_failure, 'control') || ...
        ~strcmp(results.psse.control_failure.control, 'genq')
    return;
end
if ~isfield(results.psse.control_failure, 'stage') || ...
        ~strcmp(results.psse.control_failure.stage, 'post_control_power_flow')
    return;
end
if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'genq') || ...
        ~isfield(mpc.psse, 'twodc') || ~isfield(mpc.psse, 'facts') || ...
        ~isfield(mpc.psse, 'swshunt')
    return;
end
varlim = mp.psse_system_value(mpc, 'solver', 'VARLIM', NaN, 0);
if ~isnan(varlim) && varlim == 0
    trigger = 'genq_post_control_power_flow_varlim0';
else
    trigger = 'genq_post_control_power_flow';
end
TorF = 1;
