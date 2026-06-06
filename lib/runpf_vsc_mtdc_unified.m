function varargout = runpf_vsc_mtdc_unified(casedata, mpopt, fname, solvedcase)
% runpf_vsc_mtdc_unified - Runs a unified AC/DC VSC-MTDC power flow.
% ::
%
%   RESULTS = RUNPF_VSC_MTDC_UNIFIED(CASEDATA, MPOPT)
%   [RESULTS, SUCCESS] = RUNPF_VSC_MTDC_UNIFIED(CASEDATA, MPOPT)
%
%   Lower-level implementation entry point for the unified VSC-MTDC solver.
%   Solves the AC network, DC network and VSC converter balance equations in
%   one Newton iteration using analytic derivatives. The formulation follows
%   the unified AC/DC idea of Baradar and Ghandhari, while keeping the explicit
%   station topology used by RUNPF_VSC_MTDC.
%
%   Internal operation names beginning with "__" are reserved for solver
%   composition and derivative tests. They are not public API.
%
% See also runpf_psse, runcpf_psse, runpf_vsc_mtdc, idx_vsc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 4
    solvedcase = '';
    if nargin < 3
        fname = '';
        if nargin < 2 || isempty(mpopt)
            mpopt = mpoption;
            if nargin < 1
                casedata = 'case3_vsc_mtdc_2term';
            end
        end
    end
end

if nargin >= 1 && ischar(casedata) && strncmp(casedata, '__', 2)
    [varargout{1:nargout}] = unified_dispatch(casedata, mpopt, fname, solvedcase);
    return;
end

t0 = tic;
mpc = loadcase(casedata);
if isfield(mpopt, 'vsc_mtdc') && isfield(mpopt.vsc_mtdc, 'ac_solver') && ...
        strcmpi(mpopt.vsc_mtdc.ac_solver, 'runpf_psse')
    error('runpf_vsc_mtdc_unified: unified method uses MATPOWER equations and does not support runpf_psse as AC subsolver');
end

ctx = unified_setup(mpc, mpopt);
[~, eval, normF, success, iterations, history] = ...
    solve_unified_pf(ctx, mpopt, []);
[mpc, ctx, eval, normF, success, iterations, history, psse_ctrl] = ...
    settle_unified_pf_psse_controls(mpc, mpopt, ctx, eval, normF, ...
    success, iterations, history);

results = unified_build_results(ctx, mpc, eval);
results.success = success;
results.iterations = iterations;
results.convergence = struct( ...
    'converged',       success, ...
    'method',          'unified', ...
    'jacobian',        'analytic', ...
    'psse_aware',      ctx.opt.psse_aware, ...
    'psse_controls',   psse_ctrl, ...
    'tol',             ctx.opt.tol, ...
    'max_mismatch',    normF, ...
    'history',         history );
results.et = toc(t0);

if ~isempty(fname)
    fd = fopen(fname, 'a');
    if fd ~= -1
        fprintf(fd, 'Unified VSC-MTDC power flow success = %d, iterations = %d, elapsed = %.4g s\n', ...
            results.success, results.iterations, results.et);
        fclose(fd);
    end
end
if ~isempty(solvedcase)
    savecase(solvedcase, results);
end

if nargout > 0
    varargout{1} = results;
    if nargout > 1
        varargout{2} = results.success;
    end
end


function varargout = unified_dispatch(op, arg1, arg2, arg3)
switch op
    case '__setup'
        varargout{1} = unified_setup(arg1, arg2);
    case '__mismatch'
        ctx = arg1;
        x = arg2;
        Sbase = arg3;
        if isempty(Sbase)
            Sbase = ctx.Sbase;
        end
        [F, eval] = unified_mismatch(x, ctx.model, Sbase, ...
            ctx.Ybus, ctx.Gdc, ctx.mpc, ctx.idx);
        varargout{1} = F;
        if nargout > 1
            varargout{2} = eval;
        end
    case '__jacobian'
        ctx = arg1;
        eval = arg2;
        varargout{1} = unified_jacobian(eval, ctx.model, ctx.Ybus, ...
            ctx.Gdc, ctx.mpc, ctx.idx);
    case '__results'
        ctx = arg1;
        eval = arg2;
        mpc = arg3;
        if isempty(mpc)
            mpc = ctx.mpc;
        end
        ctx_out = unified_setup(mpc, ctx.mpopt);
        varargout{1} = unified_build_results(ctx_out, mpc, eval);
    otherwise
        error('runpf_vsc_mtdc_unified: unknown internal operation ''%s''', op);
end


function idx = unified_indices()
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, VA] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, APF] = idx_gen;
[F_BUS, T_BUS, ~, ~, ~, ~, ~, ~, ~, ~, BR_STATUS, PF, QF, PT, QT, ~, ~, ...
    ~, ANGMAX] = idx_brch;
idx = struct('PQ', PQ, 'PV', PV, 'REF', REF, 'NONE', NONE, ...
    'BUS_I', BUS_I, 'BUS_TYPE', BUS_TYPE, 'PD', PD, 'QD', QD, ...
    'GS', GS, 'BS', BS, 'BUS_AREA', BUS_AREA, 'VM', VM, 'VA', VA, ...
    'GEN_BUS', GEN_BUS, 'PG', PG, 'QG', QG, 'QMAX', QMAX, ...
    'QMIN', QMIN, 'VG', VG, 'MBASE', MBASE, 'GEN_STATUS', GEN_STATUS, ...
    'PMAX', PMAX, 'PMIN', PMIN, 'APF', APF, ...
    'F_BUS', F_BUS, 'T_BUS', T_BUS, 'BR_STATUS', BR_STATUS, ...
    'PF', PF, 'QF', QF, 'PT', PT, 'QT', QT, 'ANGMAX', ANGMAX, ...
    'c', idx_vsc, 'bdc', idx_busdc, 'brdc', idx_branchdc);


function opt = unified_options(mpopt)
opt = struct('max_it', mpopt.pf.nr.max_it, 'tol', mpopt.pf.tol, ...
    'psse_aware', 0, 'psse_control_max_it', 20);
if isfield(mpopt, 'vsc_mtdc')
    if isfield(mpopt.vsc_mtdc, 'max_it') && ~isempty(mpopt.vsc_mtdc.max_it)
        opt.max_it = mpopt.vsc_mtdc.max_it;
    end
    if isfield(mpopt.vsc_mtdc, 'tol') && ~isempty(mpopt.vsc_mtdc.tol)
        opt.tol = mpopt.vsc_mtdc.tol;
    end
    if isfield(mpopt.vsc_mtdc, 'psse_aware') && ~isempty(mpopt.vsc_mtdc.psse_aware)
        opt.psse_aware = mpopt.vsc_mtdc.psse_aware;
    end
    if isfield(mpopt.vsc_mtdc, 'psse_control_max_it') && ...
            ~isempty(mpopt.vsc_mtdc.psse_control_max_it)
        opt.psse_control_max_it = mpopt.vsc_mtdc.psse_control_max_it;
    end
end


function [x, eval, normF, success, iterations, history] = ...
        solve_unified_pf(ctx, mpopt, x0)
if nargin < 3 || isempty(x0)
    x = ctx.x0;
else
    x = x0;
end

resfun = @(xx) unified_mismatch(xx, ctx.model, ctx.Sbase, ...
    ctx.Ybus, ctx.Gdc, ctx.mpc, ctx.idx);

[F, eval] = resfun(x);
normF = norm(F, Inf);
success = normF < ctx.opt.tol;
iterations = 0;
history = zeros(ctx.opt.max_it + 1, 1);
history(1) = normF;
last_eval = eval;

if mpopt.verbose > 1
    fprintf('\n it    max unified AC/DC mismatch');
    fprintf('\n----  --------------------------');
    fprintf('\n%3d        %10.3e', iterations, normF);
end

while ~success && iterations < ctx.opt.max_it
    if isempty(eval) || ~isfinite(normF)
        break;
    end
    iterations = iterations + 1;
    J = unified_jacobian(eval, ctx.model, ctx.Ybus, ctx.Gdc, ...
        ctx.mpc, ctx.idx);
    dx = -J \ F;
    [x, F, eval, normF] = accept_step(resfun, x, dx, normF);
    if ~isempty(eval)
        last_eval = eval;
    end
    history(iterations + 1) = normF;
    if mpopt.verbose > 1
        fprintf('\n%3d        %10.3e', iterations, normF);
    end
    success = normF < ctx.opt.tol;
end

if isempty(eval)
    eval = last_eval;
end

if mpopt.verbose
    if success
        fprintf('\nUnified VSC-MTDC power flow converged in %d iterations.\n', iterations);
    else
        fprintf('\nUnified VSC-MTDC power flow did not converge in %d iterations.\n', iterations);
    end
end

history = history(1:iterations + 1);


function [mpc, ctx, eval, normF, success, iterations, history, report] = ...
        settle_unified_pf_psse_controls(mpc, mpopt, ctx, eval, normF, ...
        success, iterations, history)
report = struct( ...
    'enabled',         unified_pf_psse_controls_enabled(mpc, ctx.opt), ...
    'converged',       1, ...
    'iterations',      0, ...
    'changed',         0, ...
    'failed',          0, ...
    'changed_buses',   0, ...
    'changed_gens',    0, ...
    'changed_branches', 0 );
if ~success || ~report.enabled
    return;
end

visited = cell(ctx.opt.psse_control_max_it + 1, 1);
visited{1} = psse_active_set_signature(mpc);
nvisited = 1;
nhistory = length(history);
history(nhistory + ctx.opt.psse_control_max_it * ctx.opt.max_it, 1) = 0;
for ctrl_it = 1:ctx.opt.psse_control_max_it
    r = unified_build_results(ctx, mpc, eval);
    r.success = success;
    r.iterations = iterations;
    [changed, mpc_next, ac_controlled, delta, ok] = ...
        unified_pf_psse_control_update(mpc, mpopt, r);
    if ~ok
        report.converged = 0;
        report.failed = 1;
        success = 0;
        history = history(1:nhistory);
        return;
    end

    report.iterations = ctrl_it;
    report.changed_buses = report.changed_buses + delta.changed_buses;
    report.changed_gens = report.changed_gens + delta.changed_gens;
    report.changed_branches = report.changed_branches + delta.changed_branches;
    if ~changed
        if psse_report_has_unsatisfied_controls(delta)
            report.converged = 0;
            report.failed = 1;
            success = 0;
        end
        mpc = copy_psse_control_fields(mpc, ac_controlled);
        history = history(1:nhistory);
        return;
    end

    report.changed = 1;
    sig = psse_active_set_signature(mpc_next);
    if any(strcmp(visited(1:nvisited), sig))
        [direct, direct_report] = mp.psse_unified_control_update(mpc, r.bus);
        if direct_report.supported && ~direct_report.changed && ...
                psse_control_violations(direct) == 0
            mpc = copy_psse_control_fields(mpc, direct);
            history = history(1:nhistory);
            return;
        end
        report.converged = 0;
        report.failed = 1;
        success = 0;
        history = history(1:nhistory);
        return;
    end
    nvisited = nvisited + 1;
    visited{nvisited} = sig;     %% schedule this active set as seen
    mpc = mpc_next;
    ctx = unified_setup(mpc, mpopt);
    x0 = unified_pf_x_from_controlled_ac(ctx, ac_controlled, r);
    [~, eval, normF, ok, it, h2] = solve_unified_pf(ctx, mpopt, x0);
    if length(h2) > 1
        nh2 = length(h2) - 1;
        history(nhistory + (1:nh2)) = h2(2:end);
        nhistory = nhistory + nh2;
    end
    iterations = iterations + it;
    if ~ok
        report.converged = 0;
        success = 0;
        history = history(1:nhistory);
        return;
    end
    success = ok;
end

report.converged = 0;
success = 0;
history = history(1:nhistory);


function sig = psse_active_set_signature(mpc)
[~, ~, ~, ~, ~, BUS_TYPE, PD, QD, GS, BS] = idx_bus;
[~, ~, ~, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;
[~, ~, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS] = idx_brch;
bus_cols = existing_cols([BUS_TYPE PD QD GS BS], mpc.bus, mpc.bus);
gen_cols = existing_cols([QMAX QMIN VG GEN_STATUS], mpc.gen, mpc.gen);
branch_cols = existing_cols([BR_R BR_X BR_B RATE_A RATE_B RATE_C ...
    TAP SHIFT BR_STATUS], mpc.branch, mpc.branch);
vals = [
    reshape(mpc.bus(:, bus_cols), [], 1);
    reshape(mpc.gen(:, gen_cols), [], 1);
    reshape(mpc.branch(:, branch_cols), [], 1)
];
sig = sprintf('%.9g,', round(vals(:)' * 1e9) / 1e9);


function TorF = unified_pf_psse_controls_enabled(mpc, opt)
TorF = isfield(opt, 'psse_aware') && any(opt.psse_aware) && ...
    has_psse_control_data(mpc);


function TorF = has_psse_control_data(mpc)
TorF = 0;
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    return;
end
families = {'pqbrak', 'xfmr', 'genq', 'twodc', 'swshunt', 'facts'};
for ff = 1:length(families)
    if psse_family_present(mpc, families{ff})
        TorF = 1;
        return;
    end
end


function TorF = psse_family_present(mpc, name)
TorF = isfield(mpc, 'psse') && isfield(mpc.psse, name) && ...
    ~isempty(mpc.psse.(name));
if TorF && isstruct(mpc.psse.(name)) && ...
        isfield(mpc.psse.(name), 'num') && isempty(mpc.psse.(name).num)
    TorF = 0;
end


function [changed, mpc_next, ac_controlled, report, ok] = ...
        unified_pf_psse_control_update(mpc, mpopt, r)
changed = 0;
mpc_next = mpc;
ac_controlled = [];
report = struct('changed_buses', 0, 'changed_gens', 0, ...
    'changed_branches', 0);
ok = 1;

[direct, direct_report] = mp.psse_unified_control_update(mpc, r.bus);
if direct_report.supported
    ac_controlled = psse_control_case_from_unified_result(r);
    ac_controlled = copy_original_active_set_to_ac(ac_controlled, direct);
    [changed, report] = psse_active_set_changed(mpc, ac_controlled);
    if changed || (~has_auxiliary_psse_control_data(mpc) && ...
            ~psse_report_has_unsatisfied_controls(report))
        if changed
            mpc_next = apply_psse_active_set_update(mpc, ac_controlled);
        else
            mpc_next = copy_psse_control_fields(mpc_next, ac_controlled);
        end
        return;
    end
end

ac_case = psse_control_case_from_unified_result(r);
if ~isfield(ac_case, 'psse') || isempty(ac_case.psse)
    return;
end

control_opt = mpoption(mpopt, 'verbose', 0, 'out.all', 0, ...
    'pf.enforce_q_lims', 0);
if isfield(control_opt, 'vsc_mtdc')
    control_opt = rmfield(control_opt, 'vsc_mtdc');
end

try
    [ac_controlled, ok] = runpf_psse(ac_case, control_opt);
catch
    ok = 0;
    return;
end
if ~ok || ~isstruct(ac_controlled) || ~isfield(ac_controlled, 'bus')
    ok = 0;
    return;
end

[changed, report] = psse_active_set_changed(mpc, ac_controlled);
if changed
    mpc_next = apply_psse_active_set_update(mpc, ac_controlled);
else
    mpc_next = copy_psse_control_fields(mpc, ac_controlled);
end


function TorF = has_auxiliary_psse_control_data(mpc)
TorF = 0;
families = {'pqbrak', 'genq', 'twodc', 'facts'};
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    return;
end
for kk = 1:length(families)
    if psse_family_present(mpc, families{kk})
        TorF = 1;
        return;
    end
end


function ac = psse_control_case_from_unified_result(r)
ac = r.ac;
drop = {'busdc', 'branchdc', 'vsc', 'vsc_state', 'cpf', ...
    'om', 'order', 'et', 'success', 'iterations', 'convergence'};
for dd = 1:length(drop)
    if isfield(ac, drop{dd})
        ac = rmfield(ac, drop{dd});
    end
end


function ac = copy_original_active_set_to_ac(ac, mpc)
[~, ~, ~, ~, BUS_I2, BUS_TYPE2, PD2, QD2, GS2, BS2] = idx_bus;
[~, ~, QG2, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
[~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
    TAP2, SHIFT2, BR_STATUS2] = idx_brch;

for kk = 1:size(mpc.bus, 1)
    row = find(ac.bus(:, BUS_I2) == mpc.bus(kk, BUS_I2), 1);
    if ~isempty(row)
        bus_cols = existing_cols([BUS_TYPE2 PD2 QD2 GS2 BS2], ...
            ac.bus, mpc.bus);
        ac.bus(row, bus_cols) = mpc.bus(kk, bus_cols);
    end
end
ng = min(size(mpc.gen, 1), size(ac.gen, 1));
gen_cols = existing_cols([QG2 QMAX2 QMIN2 VG2 GEN_STATUS2], ...
    ac.gen, mpc.gen);
ac.gen(1:ng, gen_cols) = mpc.gen(1:ng, gen_cols);
nb = min(size(mpc.branch, 1), size(ac.branch, 1));
branch_cols = existing_cols([BR_R2 BR_X2 BR_B2 RATE_A2 RATE_B2 ...
    RATE_C2 TAP2 SHIFT2 BR_STATUS2], ac.branch, mpc.branch);
ac.branch(1:nb, branch_cols) = mpc.branch(1:nb, branch_cols);
ac = copy_psse_control_fields(ac, mpc);


function [changed, report] = psse_active_set_changed(mpc, ac)
[~, ~, ~, ~, BUS_I2, BUS_TYPE2, PD2, QD2, GS2, BS2] = idx_bus;
[~, ~, ~, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
[~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
    TAP2, SHIFT2, BR_STATUS2] = idx_brch;
tol = 1e-8;

ac_bus = original_rows(ac.bus, mpc.bus(:, BUS_I2));
bus_cols0 = [GS2 BS2];
if has_psse_genq_control(mpc)
    bus_cols0 = [BUS_TYPE2 bus_cols0];
end
if psse_load_equiv_changed(ac)
    bus_cols0 = [bus_cols0 PD2 QD2];
end
bus_cols = existing_cols(bus_cols0, mpc.bus, ac_bus);
bus_delta = matrix_delta(mpc.bus(:, bus_cols), ac_bus(:, bus_cols), tol);

ng = size(mpc.gen, 1);
gen_cols = existing_cols([QMAX2 QMIN2 VG2 GEN_STATUS2], ...
    mpc.gen, ac.gen(1:ng, :));
gen_delta = matrix_delta(mpc.gen(:, gen_cols), ...
    ac.gen(1:ng, gen_cols), tol);

branch_cols = existing_cols([BR_R2 BR_X2 BR_B2 RATE_A2 RATE_B2 ...
    RATE_C2 TAP2 SHIFT2 BR_STATUS2], mpc.branch, ...
    ac.branch(1:size(mpc.branch, 1), :));
branch_delta = matrix_delta(mpc.branch(:, branch_cols), ...
    ac.branch(1:size(mpc.branch, 1), branch_cols), tol);

report = struct( ...
    'changed_buses',    nnz(bus_delta), ...
    'changed_gens',     nnz(gen_delta), ...
    'changed_branches', nnz(branch_delta), ...
    'control_violations', psse_control_violations(ac), ...
    'control_cycles', psse_control_cycles(ac) );
changed = report.changed_buses || report.changed_gens || ...
    report.changed_branches;


function TorF = psse_report_has_unsatisfied_controls(report)
TorF = isfield(report, 'control_violations') && ...
    report.control_violations > 0;


function n = psse_control_violations(mpc)
n = psse_control_report_count(mpc, 'xfmr', 'below_band') + ...
    psse_control_report_count(mpc, 'xfmr', 'above_band') + ...
    psse_control_report_count(mpc, 'swshunt', 'below_band') + ...
    psse_control_report_count(mpc, 'swshunt', 'above_band');


function n = psse_control_cycles(mpc)
n = psse_control_report_count(mpc, 'xfmr', 'cycle_detected') + ...
    psse_control_report_count(mpc, 'swshunt', 'cycle_detected');


function n = psse_control_report_count(mpc, family, field)
n = 0;
if isfield(mpc, 'psse') && isfield(mpc.psse, family) && ...
        isfield(mpc.psse.(family), 'control') && ...
        isfield(mpc.psse.(family).control, field)
    val = mpc.psse.(family).control.(field);
    n = nnz(val);
end


function mpc_next = apply_psse_active_set_update(mpc, ac)
[~, ~, ~, ~, BUS_I2, BUS_TYPE2, PD2, QD2, GS2, BS2, ~, VM2, VA2] = idx_bus;
[~, ~, QG2, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
[~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
    TAP2, SHIFT2, BR_STATUS2] = idx_brch;
tol = 1e-8;

mpc_next = mpc;
ac_bus = original_rows(ac.bus, mpc.bus(:, BUS_I2));
if psse_load_equiv_changed(ac)
    load_delta = ac_bus(:, [PD2 QD2]) - mpc.bus(:, [PD2 QD2]);
else
    load_delta = zeros(size(mpc_next.bus, 1), 2);
end

shared_bus_cols0 = [GS2 BS2 VM2 VA2];
if has_psse_genq_control(mpc)
    shared_bus_cols0 = [BUS_TYPE2 shared_bus_cols0];
end
shared_bus_cols = existing_cols(shared_bus_cols0, mpc_next.bus, ac_bus);
mpc_next.bus(:, shared_bus_cols) = ac_bus(:, shared_bus_cols);
mpc_next.bus(:, [PD2 QD2]) = mpc_next.bus(:, [PD2 QD2]) + load_delta;

ng = size(mpc.gen, 1);
ac_gen = ac.gen(1:ng, :);
gen_active_cols = existing_cols([QMAX2 QMIN2 VG2 GEN_STATUS2], ...
    mpc.gen, ac_gen);
gen_rows = any(abs(mpc.gen(:, gen_active_cols) - ...
    ac_gen(:, gen_active_cols)) > tol, 2);
gen_copy_cols = existing_cols([QG2 QMAX2 QMIN2 VG2 GEN_STATUS2], ...
    mpc_next.gen, ac_gen);
mpc_next.gen(gen_rows, gen_copy_cols) = ac_gen(gen_rows, gen_copy_cols);

nb = size(mpc.branch, 1);
ac_branch = ac.branch(1:nb, :);
branch_cols = existing_cols([BR_R2 BR_X2 BR_B2 RATE_A2 RATE_B2 ...
    RATE_C2 TAP2 SHIFT2 BR_STATUS2], mpc_next.branch, ac_branch);
mpc_next.branch(:, branch_cols) = ac_branch(:, branch_cols);

mpc_next = copy_psse_control_fields(mpc_next, ac);


function TorF = psse_load_equiv_changed(ac)
TorF = 0;
if ~isfield(ac, 'psse') || isempty(ac.psse)
    return;
end
if isfield(ac.psse, 'pqbrak') && isfield(ac.psse.pqbrak, 'scale') && ...
        any(abs(ac.psse.pqbrak.scale(:) - 1) > 1e-10)
    TorF = 1;
    return;
end
if isfield(ac.psse, 'pqbrak') && ...
        isfield(ac.psse.pqbrak, 'changed_last') && ...
        any(ac.psse.pqbrak.changed_last(:))
    TorF = 1;
    return;
end
if isfield(ac.psse, 'facts')
    if isfield(ac.psse.facts, 'qinj') && ...
            any(abs(ac.psse.facts.qinj(:)) > 1e-10)
        TorF = 1;
        return;
    elseif isfield(ac.psse.facts, 'control') && ...
            isfield(ac.psse.facts.control, 'qinj') && ...
            any(abs(ac.psse.facts.control.qinj(:)) > 1e-10)
        TorF = 1;
        return;
    end
end
if isfield(ac.psse, 'twodc') && isfield(ac.psse.twodc, 'control')
    ctrl = ac.psse.twodc.control;
    if (isfield(ctrl, 'apply_model') && any(ctrl.apply_model(:))) || ...
            (isfield(ctrl, 'apply_q') && any(ctrl.apply_q(:)))
        TorF = 1;
    end
end


function TorF = has_psse_genq_control(mpc)
TorF = isfield(mpc, 'psse') && psse_family_present(mpc, 'genq');


function mpc = copy_psse_control_fields(mpc, ac)
if ~isfield(ac, 'psse') || isempty(ac.psse)
    return;
end
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    mpc.psse = struct();
end
families = {'xfmr', 'genq', 'twodc', 'swshunt', 'facts', ...
    'pqbrak', 'solver_options', 'control_failure', ...
    'coordinated_active_set'};
for ff = 1:length(families)
    name = families{ff};
    if isfield(ac.psse, name)
        mpc.psse.(name) = ac.psse.(name);
    end
end


function cols = existing_cols(cols, a, b)
cols = cols(cols <= size(a, 2) & cols <= size(b, 2));


function mask = matrix_delta(a, b, tol)
if isempty(a) || isempty(b)
    mask = false(size(a, 1), 1);
else
    mask = any(abs(a - b) > tol, 2);
end


function x0 = unified_pf_x_from_controlled_ac(ctx, ac, r)
idx = ctx.idx;
c = idx.c;
bdc = idx.bdc;
x0 = ctx.x0;
ext = ctx.ac.order.bus.i2e;
Va = ctx.ac.bus(:, idx.VA) * pi / 180;
Vm = ctx.ac.bus(:, idx.VM);
for ii = 1:length(ext)
    row = find(ac.bus(:, idx.BUS_I) == ext(ii), 1);
    if ~isempty(row)
        Va(ii) = ac.bus(row, idx.VA) * pi / 180;
        Vm(ii) = ac.bus(row, idx.VM);
    end
end
nva = length(ctx.model.nonref);
nvm = length(ctx.model.vm_vars);
npac = length(ctx.model.pac_vars);
x0(1:nva) = Va(ctx.model.nonref);
x0(nva + (1:nvm)) = Vm(ctx.model.vm_vars);
if npac
    x0(nva + nvm + (1:npac)) = r.vsc(ctx.model.pac_vars, c.PAC);
end
if ~isempty(ctx.model.dc_var)
    x0(nva + nvm + npac + (1:length(ctx.model.dc_var))) = ...
        r.busdc(ctx.model.dc_var, bdc.VDC);
end


function rows = original_rows(bus, bus_ids)
[~, ~, ~, ~, BUS_I] = idx_bus;
rows = zeros(length(bus_ids), size(bus, 2));
for kk = 1:length(bus_ids)
    row = find(bus(:, BUS_I) == bus_ids(kk), 1);
    rows(kk, :) = bus(row, :);
end


function ctx = unified_setup(mpc, mpopt)
idx = unified_indices();
opt = unified_options(mpopt);
state0 = initialize_unified_state(mpc);
[ac0, map_ext] = build_unified_ac_base(mpc, state0, idx);
[ac, map] = internal_ac_case(ac0, map_ext, mpc, idx);
[Ybus, Yf, Yt] = makeYbus(ac.baseMVA, ac.bus, ac.branch);
Sbase = makeSbus(ac.baseMVA, ac.bus, ac.gen, mpopt);
Gdc = makeGdc(mpc.busdc, mpc.branchdc);
model = build_unified_model(mpc, ac, map, Gdc, idx);
x0 = initial_x(ac, model, state0, mpc, idx);
ctx = struct('mpc', mpc, 'mpopt', mpopt, 'idx', idx, 'opt', opt, ...
    'state0', state0, 'ac0', ac0, 'ac', ac, 'map_ext', map_ext, ...
    'map', map, 'Ybus', Ybus, 'Yf', Yf, 'Yt', Yt, ...
    'Sbase', Sbase, 'Gdc', Gdc, 'model', model, 'x0', x0);


function state = initialize_unified_state(mpc)
c = idx_vsc;
bdc = idx_busdc;
vsc = mpc.vsc;
nv = size(vsc, 1);
state = struct( ...
    'pac', zeros(nv, 1), ...
    'qac', zeros(nv, 1), ...
    'pdc', zeros(nv, 1), ...
    'vdc', zeros(nv, 1), ...
    'vac_internal_set', ones(nv, 1), ...
    'vac_internal', ones(nv, 1), ...
    'ploss', zeros(nv, 1), ...
    'iac', zeros(nv, 1) );
active = find(vsc(:, c.VSC_STATUS) > 0);
state.qac(active) = vsc(active, c.QAC_SET);
state.pdc(active) = vsc(active, c.PDC_SET);
state.vac_internal_set(active) = vsc(active, c.VAC_SET);
state.vac_internal(active) = vsc(active, c.VAC_SET);
for k = active'
    b = find(mpc.busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1);
    state.vdc(k) = mpc.busdc(b, bdc.VDC);
    if vsc(k, c.DC_MODE) == c.VSC_DC_VDC
        state.vdc(k) = vsc(k, c.VDC_SET);
    end
end

state.pac(active) = -state.pdc(active);
fixed_pac = vsc(:, c.AC_MODE) == c.VSC_AC_PQ | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
state.pac(fixed_pac & vsc(:, c.VSC_STATUS) > 0) = ...
    vsc(fixed_pac & vsc(:, c.VSC_STATUS) > 0, c.PAC_SET);
[state.ploss, state.iac] = calc_vsc_losses(mpc.baseMVA, state.pac, ...
    state.qac, state.vac_internal, vsc);
kk = active(~fixed_pac(active));
state.pac(kk) = -state.pdc(kk) - state.ploss(kk);


function results = unified_build_results(ctx, mpc, eval)
results = mpc;
results.ac = build_ac_results(ctx.ac, ctx.map, eval, ctx.Ybus, ...
    ctx.Yf, ctx.Yt, mpc, ctx.idx, ctx.mpopt);
[results.busdc, results.branchdc] = build_dc_results(mpc, eval, ctx.idx);
results.vsc = build_vsc_results(mpc, ctx.map_ext, ctx.map, eval, ctx.idx);
results.vsc_state = eval_to_state(mpc, ctx.map_ext, ctx.map, eval, ctx.idx);


function [ac, map] = build_unified_ac_base(mpc, state, idx)
c = idx.c;
[ac, map] = apply_vsc_ac_model(mpc, state);
remove_gen = map.gen(map.gen > 0);
if ~isempty(remove_gen)
    ac.gen(remove_gen, :) = [];
end
map.gen(:) = 0;
map.uses_gen(:) = 0;

active = find(mpc.vsc(:, c.VSC_STATUS) > 0);
for k = active'
    row = find(ac.bus(:, idx.BUS_I) == map.internal_bus(k), 1);
    ac.bus(row, idx.BUS_TYPE) = idx.PQ;
    ac.bus(row, [idx.PD idx.QD]) = 0;
end


function [ac, map] = internal_ac_case(ac0, map_ext, mpc, idx)
c = idx.c;
ac = ext2int(ac0);
ext = ac.order.bus.i2e;
map = map_ext;
map.pcc = zeros(size(mpc.vsc, 1), 1);
map.filter = zeros(size(mpc.vsc, 1), 1);
map.internal = zeros(size(mpc.vsc, 1), 1);
active = find(mpc.vsc(:, c.VSC_STATUS) > 0);
for k = active'
    map.pcc(k) = find(ext == mpc.vsc(k, c.VSC_BUS), 1);
    map.filter(k) = find(ext == map_ext.filter_bus(k), 1);
    map.internal(k) = find(ext == map_ext.internal_bus(k), 1);
end


function model = build_unified_model(mpc, ac, map, Gdc, idx)
c = idx.c;
bdc = idx.bdc;
vsc = mpc.vsc;
nb = size(ac.bus, 1);
nv = size(vsc, 1);
active = find(vsc(:, c.VSC_STATUS) > 0);
ref = find(ac.bus(:, idx.BUS_TYPE) == idx.REF);
if isempty(ref)
    error('runpf_vsc_mtdc_unified: AC case must have a reference bus');
end
nonref = setdiff((1:nb)', ref(:));
vctrl = active(vsc(active, c.AC_MODE) == c.VSC_AC_V | ...
    vsc(active, c.AC_MODE) == c.VSC_AC_PV);
vctrl_internal = map.internal(vctrl);
pq = find(ac.bus(:, idx.BUS_TYPE) == idx.PQ);
qeq = setdiff(pq, vctrl_internal);
vm_vars = unique([pq; map.pcc(vctrl)]);

fixed_pac = vsc(:, c.AC_MODE) == c.VSC_AC_PQ | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
pac_vars = active(~fixed_pac(active));

busdc_on = find(mpc.busdc(:, bdc.BUSDC_STATUS) > 0);
dc_lookup = zeros(nv, 1);
for k = active'
    dc_lookup(k) = find(mpc.busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1);
end
slack_vsc = active(vsc(active, c.DC_MODE) == c.VSC_DC_VDC);
fixed_dc = unique(dc_lookup(slack_vsc));
dc_var = setdiff(busdc_on, fixed_dc);

model = struct('nb', nb, 'active', active, 'ref', ref(:), ...
    'nonref', nonref, 'pq', pq, 'qeq', qeq, 'vm_vars', vm_vars, ...
    'vctrl', vctrl, 'pac_vars', pac_vars, 'dc_var', dc_var, ...
    'fixed_pac', fixed_pac, 'dc_lookup', dc_lookup, ...
    'slack_vsc', slack_vsc, 'fixed_dc', fixed_dc, ...
    'map', map, 'Gdc', Gdc, 'fixed_vm', ac.bus(:, idx.VM));

neq = length(nonref) + length(qeq) + length(vctrl) + ...
    length(pac_vars) + length(dc_var);
nx = length(nonref) + length(vm_vars) + length(pac_vars) + length(dc_var);
if neq ~= nx
    error('runpf_vsc_mtdc_unified: internal equation/variable count mismatch (%d equations, %d variables)', neq, nx);
end


function x = initial_x(ac, model, state, mpc, idx)
vsc = mpc.vsc;
c = idx.c;
Va = ac.bus(:, idx.VA) * pi / 180;
Vm = ac.bus(:, idx.VM);
pac0 = state.pac(model.pac_vars);

Vdc = mpc.busdc(:, idx.bdc.VDC);
for k = model.slack_vsc'
    Vdc(model.dc_lookup(k)) = vsc(k, c.VDC_SET);
end
for k = model.active'
    b = model.dc_lookup(k);
    if Vdc(b) <= 0
        Vdc(b) = max(vsc(k, c.VDC_SET), 1);
    end
end

x = [Va(model.nonref); Vm(model.vm_vars); pac0; Vdc(model.dc_var)];


function [F, eval] = unified_mismatch(x, model, Sbase, Ybus, Gdc, mpc, idx)
[V, Va, Vm, pac, Vdc] = unpack_x(x, model, mpc, idx);
if any(Vm <= 0) || any(Vdc <= 0)
    F = ones(length(x), 1) * 1e6;
    eval = [];
    return;
end

baseMVA = mpc.baseMVA;
c = idx.c;
vsc = mpc.vsc;
Sspec = Sbase;
for k = model.active'
    internal = model.map.internal(k);
    if model.fixed_pac(k)
        pk = vsc(k, c.PAC_SET);
    else
        pk = pac(k);
    end
    if vsc(k, c.AC_MODE) == c.VSC_AC_Q || vsc(k, c.AC_MODE) == c.VSC_AC_PQ
        qk = vsc(k, c.QAC_SET);
    else
        qk = 0;
    end
    Sspec(internal) = Sspec(internal) + (pk + 1j * qk) / baseMVA;
end

Scalc = V .* conj(Ybus * V);
mis = Scalc - Sspec;
qac = zeros(size(vsc, 1), 1);
for k = model.active'
    if vsc(k, c.AC_MODE) == c.VSC_AC_Q || vsc(k, c.AC_MODE) == c.VSC_AC_PQ
        qac(k) = vsc(k, c.QAC_SET);
    else
        qac(k) = baseMVA * imag(Scalc(model.map.internal(k)) - Sbase(model.map.internal(k)));
    end
end

vac_internal = ones(size(vsc, 1), 1);
vac_internal(model.active) = Vm(model.map.internal(model.active));
[ploss, iac] = calc_vsc_losses(baseMVA, pac, qac, vac_internal, vsc);
ploss(vsc(:, c.VSC_STATUS) <= 0) = 0;
iac(vsc(:, c.VSC_STATUS) <= 0) = 0;
pdc = converter_dc_powers(mpc, model, Vdc, pac, ploss, Gdc, idx);
I = Gdc * Vdc;
Pnet = Vdc .* I * baseMVA;
Pspec = dc_power_spec(mpc, model, pdc);

F = [
    real(mis(model.nonref));
    imag(mis(model.qeq));
    Vm(model.map.pcc(model.vctrl)) - vsc(model.vctrl, c.VAC_SET);
    (pac(model.pac_vars) + pdc(model.pac_vars) + ploss(model.pac_vars)) / baseMVA;
    (Pnet(model.dc_var) - Pspec(model.dc_var)) / baseMVA
];

eval = struct('V', V, 'Va', Va, 'Vm', Vm, 'pac', pac, 'qac', qac, ...
    'pdc', pdc, 'vdc_bus', Vdc, 'ploss', ploss, 'iac', iac, ...
    'Scalc', Scalc, 'Pnet', Pnet, 'Idc', I);


function [V, Va, Vm, pac, Vdc] = unpack_x(x, model, mpc, idx)
c = idx.c;
vsc = mpc.vsc;
nb = model.nb;
nv = size(vsc, 1);
nva = length(model.nonref);
nvm = length(model.vm_vars);
npac = length(model.pac_vars);
Va = zeros(nb, 1);
Vm = ones(nb, 1);
Va(model.ref) = 0;
Va(model.nonref) = x(1:nva);
Vm(:) = 1;
Vm(model.vm_vars) = x(nva + (1:nvm));

fixed_vm = setdiff((1:nb)', model.vm_vars);
Vm(fixed_vm) = mpc_ac_fixed_vm(model, fixed_vm);
V = Vm .* exp(1j * Va);

pac = zeros(nv, 1);
pac(model.active) = vsc(model.active, c.PAC_SET);
pac(model.pac_vars) = x(nva + nvm + (1:npac));

Vdc = mpc.busdc(:, idx.bdc.VDC);
for k = model.slack_vsc'
    Vdc(model.dc_lookup(k)) = vsc(k, c.VDC_SET);
end
Vdc(model.dc_var) = x(nva + nvm + npac + (1:length(model.dc_var)));


function Vm = mpc_ac_fixed_vm(model, rows)
Vm = ones(length(rows), 1);
for kk = 1:length(rows)
    r = rows(kk);
    Vm(kk) = model.fixed_vm(r);
end


function pdc = converter_dc_powers(mpc, model, Vdc, pac, ploss, Gdc, idx)
c = idx.c;
vsc = mpc.vsc;
nv = size(vsc, 1);
pdc = zeros(nv, 1);
for k = model.active'
    b = model.dc_lookup(k);
    if model.fixed_pac(k)
        pdc(k) = -pac(k) - ploss(k);
    elseif vsc(k, c.DC_MODE) == c.VSC_DC_PDC
        pdc(k) = vsc(k, c.PDC_SET);
    elseif vsc(k, c.DC_MODE) == c.VSC_DC_DROOP
        pdc(k) = vsc(k, c.PDC_SET) + vsc(k, c.KDROOP) * ...
            (Vdc(b) - vsc(k, c.VDC_SET));
    end
end

I = Gdc * Vdc;
Pnet = Vdc .* I * mpc.baseMVA;
for bb = model.fixed_dc(:)'
    ks = model.slack_vsc(model.dc_lookup(model.slack_vsc) == bb);
    other = model.active(model.dc_lookup(model.active) == bb & ...
        mpc.vsc(model.active, c.DC_MODE) ~= c.VSC_DC_VDC);
    p = Pnet(bb) - sum(pdc(other));
    pdc(ks) = p / length(ks);
end


function Pspec = dc_power_spec(mpc, model, pdc)
nbdc = size(mpc.busdc, 1);
Pspec = zeros(nbdc, 1);
for k = model.active'
    b = model.dc_lookup(k);
    Pspec(b) = Pspec(b) + pdc(k);
end


function J = unified_jacobian(eval, model, Ybus, Gdc, mpc, idx)
baseMVA = mpc.baseMVA;
c = idx.c;
vsc = mpc.vsc;
nv = size(vsc, 1);

nva = length(model.nonref);
nvm = length(model.vm_vars);
npac = length(model.pac_vars);
ndc = length(model.dc_var);
nx = nva + nvm + npac + ndc;

col_va = 1:nva;
col_vm = nva + (1:nvm);
col_pac = nva + nvm + (1:npac);
col_vdc = nva + nvm + npac + (1:ndc);

row_p = 1:length(model.nonref);
row_q = length(row_p) + (1:length(model.qeq));
row_v = length(row_p) + length(row_q) + (1:length(model.vctrl));
row_bal = length(row_p) + length(row_q) + length(row_v) + ...
    (1:length(model.pac_vars));
row_dc = length(row_p) + length(row_q) + length(row_v) + ...
    length(row_bal) + (1:length(model.dc_var));

J = zeros(length(row_p) + length(row_q) + length(row_v) + ...
    length(row_bal) + length(row_dc), nx);

[dS_dVa, dS_dVm] = dSbus_dV(Ybus, eval.V);
J(row_p, col_va) = real(dS_dVa(model.nonref, model.nonref));
J(row_p, col_vm) = real(dS_dVm(model.nonref, model.vm_vars));
J(row_q, col_va) = imag(dS_dVa(model.qeq, model.nonref));
J(row_q, col_vm) = imag(dS_dVm(model.qeq, model.vm_vars));

for kk = 1:npac
    k = model.pac_vars(kk);
    r = find(model.nonref == model.map.internal(k), 1);
    if ~isempty(r)
        J(row_p(r), col_pac(kk)) = J(row_p(r), col_pac(kk)) - 1 / baseMVA;
    end
end

for kk = 1:length(model.vctrl)
    pcc = model.map.pcc(model.vctrl(kk));
    c_vm = find(model.vm_vars == pcc, 1);
    J(row_v(kk), col_vm(c_vm)) = 1;
end

dPac = zeros(nv, nx);
for kk = 1:npac
    dPac(model.pac_vars(kk), col_pac(kk)) = 1;
end

dQac = zeros(nv, nx);
v_modes = model.active(vsc(model.active, c.AC_MODE) == c.VSC_AC_V | ...
    vsc(model.active, c.AC_MODE) == c.VSC_AC_PV);
for k = v_modes'
    internal = model.map.internal(k);
    dQac(k, col_va) = baseMVA * imag(dS_dVa(internal, model.nonref));
    dQac(k, col_vm) = baseMVA * imag(dS_dVm(internal, model.vm_vars));
end

dUc = zeros(nv, nx);
for k = model.active'
    c_vm = find(model.vm_vars == model.map.internal(k), 1);
    if ~isempty(c_vm)
        dUc(k, col_vm(c_vm)) = 1;
    end
end

dPloss = converter_loss_derivatives(mpc, model, eval, dPac, dQac, dUc, idx);
dpdc = dc_converter_derivatives(mpc, model, eval, Gdc, dPac, dPloss, idx);

for kk = 1:length(model.pac_vars)
    k = model.pac_vars(kk);
    J(row_bal(kk), :) = (dPac(k, :) + dpdc(k, :) + dPloss(k, :)) / baseMVA;
end

dPnet = dc_network_derivatives(eval, Gdc, baseMVA, model, nx, col_vdc);
for kk = 1:length(model.dc_var)
    b = model.dc_var(kk);
    on_bus = model.active(model.dc_lookup(model.active) == b);
    J(row_dc(kk), :) = (dPnet(b, :) - sum(dpdc(on_bus, :), 1)) / baseMVA;
end


function dPloss = converter_loss_derivatives(mpc, model, eval, dPac, dQac, dUc, idx)
c = idx.c;
vsc = mpc.vsc;
nv = size(vsc, 1);
nx = size(dPac, 2);
dPloss = zeros(nv, nx);

for k = model.active'
    P = eval.pac(k);
    Q = eval.qac(k);
    U = max(abs(eval.V(model.map.internal(k))), eps);
    R = sqrt(P^2 + Q^2);
    if R < eps
        continue;
    end
    I = R / (mpc.baseMVA * U);
    dL_dI = vsc(k, c.LOSS_B) + 2 * vsc(k, c.LOSS_C) * I;
    dI_dP = P / (mpc.baseMVA * U * R);
    dI_dQ = Q / (mpc.baseMVA * U * R);
    dI_dU = -I / U;
    dPloss(k, :) = dL_dI * (dI_dP * dPac(k, :) + ...
        dI_dQ * dQac(k, :) + dI_dU * dUc(k, :));
end


function dpdc = dc_converter_derivatives(mpc, model, eval, Gdc, dPac, dPloss, idx)
c = idx.c;
vsc = mpc.vsc;
nv = size(vsc, 1);
nx = size(dPac, 2);
dpdc = zeros(nv, nx);

for k = model.active'
    b = model.dc_lookup(k);
    if model.fixed_pac(k)
        dpdc(k, :) = -dPac(k, :) - dPloss(k, :);
    elseif vsc(k, c.DC_MODE) == c.VSC_DC_DROOP
        c_vdc = dc_var_col(model, b);
        if c_vdc > 0
            dpdc(k, c_vdc) = vsc(k, c.KDROOP);
        end
    end
end

dPnet = dc_network_derivatives(eval, Gdc, mpc.baseMVA, model, nx, []);
for bb = model.fixed_dc(:)'
    ks = model.slack_vsc(model.dc_lookup(model.slack_vsc) == bb);
    other = model.active(model.dc_lookup(model.active) == bb & ...
        vsc(model.active, c.DC_MODE) ~= c.VSC_DC_VDC);
    dp = dPnet(bb, :) - sum(dpdc(other, :), 1);
    for k = ks'
        dpdc(k, :) = dp / length(ks);
    end
end


function dPnet = dc_network_derivatives(eval, Gdc, baseMVA, model, nx, col_vdc)
if nargin < 6 || isempty(col_vdc)
    nva = length(model.nonref);
    nvm = length(model.vm_vars);
    npac = length(model.pac_vars);
    col_vdc = nva + nvm + npac + (1:length(model.dc_var));
end
nbdc = length(eval.vdc_bus);
dPnet = zeros(nbdc, nx);
for rr = 1:length(model.dc_var)
    j = model.dc_var(rr);
    dPnet(:, col_vdc(rr)) = baseMVA * ( ...
        (1:nbdc)' == j) * eval.Idc(j) + ...
        baseMVA * eval.vdc_bus .* full(Gdc(:, j));
end


function col = dc_var_col(model, dc_bus)
nva = length(model.nonref);
nvm = length(model.vm_vars);
npac = length(model.pac_vars);
rr = find(model.dc_var == dc_bus, 1);
if isempty(rr)
    col = 0;
else
    col = nva + nvm + npac + rr;
end


function [x, F, eval, normF] = accept_step(fun, x0, dx, normF0)
alpha = 1;
while alpha >= 1/64
    xt = x0 + alpha * dx;
    [Ft, evalt] = fun(xt);
    normFt = norm(Ft, Inf);
    if isfinite(normFt) && normFt < normF0
        x = xt;
        F = Ft;
        eval = evalt;
        normF = normFt;
        return;
    end
    alpha = alpha / 2;
end
x = x0 + dx;
[F, eval] = fun(x);
normF = norm(F, Inf);


function ac = build_ac_results(ac, map, eval, Ybus, Yf, Yt, mpc, idx, mpopt)
c = idx.c;
vsc = mpc.vsc;
active = find(vsc(:, c.VSC_STATUS) > 0);
ac.bus(:, idx.VM) = abs(eval.V);
ac.bus(:, idx.VA) = angle(eval.V) * 180 / pi;
for k = active'
    internal = map.internal(k);
    row = find(ac.bus(:, idx.BUS_I) == internal, 1);
    ac.bus(row, [idx.PD idx.QD]) = 0;
    if vsc(k, c.AC_MODE) == c.VSC_AC_Q || vsc(k, c.AC_MODE) == c.VSC_AC_PQ
        ac.bus(row, idx.PD) = -eval.pac(k);
        ac.bus(row, idx.QD) = -eval.qac(k);
    else
        gen = zeros(1, size(ac.gen, 2));
        gen(idx.GEN_BUS) = internal;
        gen(idx.PG) = eval.pac(k);
        gen(idx.QG) = eval.qac(k);
        gen(idx.QMAX) = 1e9;
        gen(idx.QMIN) = -1e9;
        gen(idx.VG) = abs(eval.V(internal));
        gen(idx.MBASE) = mpc.baseMVA;
        gen(idx.GEN_STATUS) = 1;
        gen(idx.PMAX) = 1e9;
        gen(idx.PMIN) = -1e9;
        ac.gen = [ac.gen; gen];
        ac.bus(row, idx.BUS_TYPE) = idx.PV;
        map.gen(k) = size(ac.gen, 1);
        map.uses_gen(k) = 1;
    end
end

if size(ac.branch, 2) < idx.QT
    ac.branch = [ac.branch zeros(size(ac.branch, 1), idx.QT - size(ac.branch, 2))];
end
on = find(ac.branch(:, idx.BR_STATUS) > 0);
Sf = eval.V(ac.branch(on, idx.F_BUS)) .* conj(Yf(on, :) * eval.V) * mpc.baseMVA;
St = eval.V(ac.branch(on, idx.T_BUS)) .* conj(Yt(on, :) * eval.V) * mpc.baseMVA;
ac.branch(:, [idx.PF idx.QF idx.PT idx.QT]) = 0;
ac.branch(on, [idx.PF idx.QF idx.PT idx.QT]) = ...
    [real(Sf) imag(Sf) real(St) imag(St)];
[ref, pv, pq] = bustypes(ac.bus, ac.gen);
[ac.bus, ac.gen, ac.branch] = pfsoln(ac.baseMVA, ac.bus, ac.gen, ...
    ac.branch, Ybus, Yf, Yt, eval.V, ref, pv, pq, mpopt);
ac = int2ext(ac);


function [busdc, branchdc] = build_dc_results(mpc, eval, idx)
bdc = idx.bdc;
brdc = idx.brdc;
c = idx.c;
busdc = mpc.busdc;
branchdc = mpc.branchdc;
if size(busdc, 2) < bdc.IDC
    busdc = [busdc zeros(size(busdc, 1), bdc.IDC - size(busdc, 2))];
end
if size(branchdc, 2) < brdc.ITDC
    branchdc = [branchdc zeros(size(branchdc, 1), brdc.ITDC - size(branchdc, 2))];
end
busdc(:, bdc.VDC) = eval.vdc_bus;
busdc(:, bdc.IDC) = eval.Idc;
busdc(:, bdc.PDC) = 0;
for k = find(mpc.vsc(:, c.VSC_STATUS) > 0)'
    b = find(busdc(:, bdc.BUSDC_I) == mpc.vsc(k, c.BUSDC), 1);
    busdc(b, bdc.PDC) = busdc(b, bdc.PDC) + eval.pdc(k);
end

branchdc(:, brdc.PFDC:brdc.ITDC) = 0;
for k = 1:size(branchdc, 1)
    if branchdc(k, brdc.BRDC_STATUS) <= 0
        continue;
    end
    f = find(busdc(:, bdc.BUSDC_I) == branchdc(k, brdc.F_BUSDC), 1);
    t = find(busdc(:, bdc.BUSDC_I) == branchdc(k, brdc.T_BUSDC), 1);
    if busdc(f, bdc.BUSDC_STATUS) <= 0 || busdc(t, bdc.BUSDC_STATUS) <= 0
        continue;
    end
    g = 1 / branchdc(k, brdc.BRDC_R);
    If = g * (eval.vdc_bus(f) - eval.vdc_bus(t));
    It = -If;
    branchdc(k, brdc.IFDC) = If;
    branchdc(k, brdc.ITDC) = It;
    branchdc(k, brdc.PFDC) = eval.vdc_bus(f) * If * mpc.baseMVA;
    branchdc(k, brdc.PTDC) = eval.vdc_bus(t) * It * mpc.baseMVA;
end


function vsc_out = build_vsc_results(mpc, map_ext, map, eval, idx)
c = idx.c;
bdc = idx.bdc;
vsc = mpc.vsc;
nv = size(vsc, 1);
if size(vsc, 2) < c.REACTOR_BRANCH
    vsc_out = [vsc zeros(nv, c.REACTOR_BRANCH - size(vsc, 2))];
else
    vsc_out = vsc;
end
active = find(vsc(:, c.VSC_STATUS) > 0);
vsc_out(:, c.PAC:c.REACTOR_BRANCH) = 0;
vsc_out(active, c.PAC) = eval.pac(active);
vsc_out(active, c.QAC) = eval.qac(active);
vsc_out(active, c.PDC) = eval.pdc(active);
for kk = 1:length(active)
    k = active(kk);
    b = find(mpc.busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1);
    vsc_out(k, c.VDC) = eval.vdc_bus(b);
end
vsc_out(active, c.VAC_PCC) = abs(eval.V(map.pcc(active)));
vsc_out(active, c.VAC_FILTER) = abs(eval.V(map.filter(active)));
vsc_out(active, c.VAC_INTERNAL) = abs(eval.V(map.internal(active)));
vsc_out(active, c.PLOSS) = eval.ploss(active);
vsc_out(active, c.IS_DC_SLACK) = vsc(active, c.DC_MODE) == c.VSC_DC_VDC;
vsc_out(active, c.FILTER_BUS) = map_ext.filter_bus(active);
vsc_out(active, c.INTERNAL_BUS) = map_ext.internal_bus(active);
vsc_out(active, c.TR_BRANCH) = map_ext.tr_branch(active);
vsc_out(active, c.REACTOR_BRANCH) = map_ext.reactor_branch(active);

function state = eval_to_state(mpc, map_ext, map, eval, idx)
c = idx.c;
nv = size(mpc.vsc, 1);
state = struct( ...
    'pac', eval.pac, ...
    'qac', eval.qac, ...
    'pdc', eval.pdc, ...
    'vdc', zeros(nv, 1), ...
    'vac_pcc', zeros(nv, 1), ...
    'vac_filter', zeros(nv, 1), ...
    'vac_internal_set', zeros(nv, 1), ...
    'vac_internal', zeros(nv, 1), ...
    'ploss', eval.ploss, ...
    'iac', eval.iac, ...
    'ptr_loss', zeros(nv, 1), ...
    'preactor_loss', zeros(nv, 1), ...
    'is_dc_slack', zeros(nv, 1), ...
    'filter_bus', map_ext.filter_bus, ...
    'internal_bus', map_ext.internal_bus, ...
    'tr_branch', map_ext.tr_branch, ...
    'reactor_branch', map_ext.reactor_branch );
active = find(mpc.vsc(:, c.VSC_STATUS) > 0);
for k = active'
    b = find(mpc.busdc(:, idx.bdc.BUSDC_I) == mpc.vsc(k, c.BUSDC), 1);
    state.vdc(k) = eval.vdc_bus(b);
    state.vac_pcc(k) = abs(eval.V(map.pcc(k)));
    state.vac_filter(k) = abs(eval.V(map.filter(k)));
    state.vac_internal(k) = abs(eval.V(map.internal(k)));
    state.vac_internal_set(k) = state.vac_internal(k);
    state.is_dc_slack(k) = mpc.vsc(k, c.DC_MODE) == c.VSC_DC_VDC;
end
