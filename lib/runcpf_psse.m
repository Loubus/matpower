function [res, suc] = ...
    runcpf_psse(basecasedata, targetcasedata, mpopt, fname, solvedcase)
% runcpf_psse - Runs a CPF with opt-in PSS/E controls.
% ::
%
%   [RESULTS, SUCCESS] = RUNCPF_PSSE(BASECASEDATA, TARGETCASEDATA, ...
%                                   MPOPT, FNAME, SOLVEDCASE)
%
% Runs the standard MATPOWER continuation power flow with the ``mp.xt_psse``
% extension enabled for both the initial power flow and the MP-Core CPF task.
% This preserves the CPF formulation ``F(x, lambda) = 0`` with the continuation
% parameterization equation, while routing PSS/E-specific data model
% iterations through ``mp.task_cpf_psse``.
% Explicit VSC-MTDC cases with BUSDC, BRANCHDC and VSC data are routed through
% the VSC-MTDC CPF solver from this PSS/E-aware entry point. The VSC equations
% are MATPOWER AC/DC/VSC equations, not a full PSS/E VSC HVDC device replica.
%
% See also runcpf, runpf_psse, mp.xt_psse, mp.task_cpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%% default arguments
if nargin < 5
    solvedcase = '';                %% don't save solved case
    if nargin < 4
        fname = '';                 %% don't print results to a file
        if nargin < 3
            mpopt = mpoption;       %% use default options
            if nargin < 2
                if nargin < 1
                    basecasedata = 'case9';
                    targetcasedata = 'case9target';
                else
                    error('runcpf_psse: Two input cases, base and target, are required.');
                end
            end
        end
    end
end

%% activate PSS/E extension for the base PF and CPF task
mpopt = mp.psse_mpx_options(mpopt);
if strcmpi(mpopt.model, 'DC')
    error('runcpf_psse: PSS/E continuation power flow requires an AC model.');
end
if ~have_feature('mp_core') || mpopt.exp.use_legacy_core
    error('runcpf_psse: PSS/E continuation power flow requires MP-Core.');
end

%% read and prepare base/target cases
mpcb = loadcase(basecasedata);
[mpcb, prep_base, mpopt] = mp.psse_prepare_case(mpcb, mpopt, 'cpf_base');
mpct = loadcase(targetcasedata);
[mpct, prep_target] = mp.psse_prepare_case(mpct, mpopt, 'cpf_target');

%% explicit VSC-MTDC cases use the selected VSC-MTDC CPF
if has_vsc_mtdc(mpcb) || has_vsc_mtdc(mpct)
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
        formulation = 'PSS/E-aware unified VSC-MTDC CPF with MATPOWER AC/DC/VSC equations';
    else
        mpopt.vsc_mtdc.ac_solver = 'runpf_psse';
        task_class = 'sequential_vsc_mtdc';
        formulation = 'Sequential VSC-MTDC CPF with runpf_psse AC subproblem';
    end
    [results, success] = runcpf_vsc_mtdc(mpcb, mpct, mpopt, '', '');
    if ~isfield(results, 'psse') || isempty(results.psse)
        results.psse = struct();
    end
    if isfield(mpcb, 'psse') && isfield(mpcb.psse, 'solver_options')
        results.psse.solver_options = mpcb.psse.solver_options;
    end
    results.psse.cpf = struct( ...
        'entrypoint', 'runcpf_psse', ...
        'task_class', task_class, ...
        'base_prepare', prep_base, ...
        'target_prepare', prep_target, ...
        'formulation', formulation);
    if ~isempty(prep_base.branch_collapse) && ...
            isfield(prep_base.branch_collapse, 'active') && ...
            prep_base.branch_collapse.active && ...
            ~isempty(which('mp.psse_branch_expand'))
        results = mp.psse_branch_expand(results, prep_base.branch_collapse);
        results.psse.cpf.output_topology = 'original_branch_expanded';
    end
    if ~isempty(prep_base.swdev_collapse) && ...
            isfield(prep_base.swdev_collapse, 'active') && ...
            prep_base.swdev_collapse.active && ...
            ~isempty(which('mp.psse_swdev_expand'))
        results = mp.psse_swdev_expand(results, prep_base.swdev_collapse);
        results.psse.cpf.output_topology = 'original_swdev_expanded';
    end
    if isfield(results, 'cpf') && isfield(results.cpf, 'lam') && ...
            ~isempty(which('mp.psse_cpf_compact_trace'))
        results.cpf_psse_compact = mp.psse_cpf_compact_trace(results.cpf);
        if isfield(results.cpf_psse_compact, 'compaction')
            results.psse.cpf.compact_trace = ...
                results.cpf_psse_compact.compaction;
        end
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
    if ~isempty(solvedcase)
        savecase(solvedcase, results);
    end
    if nargout
        res = results;
        if nargout > 1
            suc = success;
        end
    end
    return;
end

%% solve the base with PSS/E controls, then carry that active-set into target
mpcb_ref = mpcb;
if mpopt.verbose > 4
    mpopt_pf = mpoption(mpopt, 'verbose', 2);
else
    mpopt_pf = mpoption(mpopt, 'verbose', 0);
end
mpopt_pf = mpoption(mpopt_pf, 'pf.enforce_q_lims', ...
    mpopt.cpf.enforce_q_lims);
mpopt_pf.exp.psse_keep_swdev_collapsed = 1;
mpopt_pf.exp.psse_keep_branch_collapsed = 1;
[mpcb, base_success] = runpf_psse(mpcb, mpopt_pf);
if ~base_success
    results = mpcb;
    results.cpf = struct();
    results.success = 0;
    success = 0;
else
    mpct = mp.psse_sync_cpf_target(mpcb, mpct, mpcb_ref);

    %% run the standard CPF machinery with the PSS/E task extension enabled
    mpopt.exp.psse_sync_cpf_bus_types = 1;
    save_after = solvedcase;
    [results, success] = runcpf(mpcb, mpct, mpopt, fname, '');
end

%% attach traceability metadata after RUNCPF packages the standard CPF results
if ~isfield(results, 'psse') || isempty(results.psse)
    results.psse = struct();
end
if isfield(mpcb, 'psse') && isfield(mpcb.psse, 'solver_options')
    results.psse.solver_options = mpcb.psse.solver_options;
end
results.psse.cpf = struct( ...
    'entrypoint', 'runcpf_psse', ...
    'task_class', 'mp.task_cpf_psse', ...
    'base_prepare', prep_base, ...
    'target_prepare', prep_target, ...
    'formulation', 'MATPOWER CPF F(x,lambda) plus parameterization');
if ~isempty(prep_base.branch_collapse) && ...
        isfield(prep_base.branch_collapse, 'active') && ...
        prep_base.branch_collapse.active && ...
        ~isempty(which('mp.psse_branch_expand'))
    results = mp.psse_branch_expand(results, prep_base.branch_collapse);
    results.psse.cpf.output_topology = 'original_branch_expanded';
end
if ~isempty(prep_base.swdev_collapse) && ...
        isfield(prep_base.swdev_collapse, 'active') && ...
        prep_base.swdev_collapse.active && ...
        ~isempty(which('mp.psse_swdev_expand'))
    results = mp.psse_swdev_expand(results, prep_base.swdev_collapse);
    results.psse.cpf.output_topology = 'original_swdev_expanded';
end
if isfield(results, 'cpf') && isfield(results.cpf, 'lam') && ...
        ~isempty(which('mp.psse_cpf_compact_trace'))
    results.cpf_psse_compact = mp.psse_cpf_compact_trace(results.cpf);
    if isfield(results.cpf_psse_compact, 'compaction')
        results.psse.cpf.compact_trace = results.cpf_psse_compact.compaction;
    end
end

if exist('save_after', 'var') && ~isempty(save_after)
    savecase(save_after, results);
end

if nargout
    res = results;
    if nargout > 1
        suc = success;
    end
end
