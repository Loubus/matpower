function [results, success] = ...
    runcpf_vsc_mtdc(basecasedata, targetcasedata, mpopt, fname, solvedcase)
% runcpf_vsc_mtdc - Runs an AC/DC VSC-MTDC continuation PF.
% ::
%
%   RESULTS = RUNCPF_VSC_MTDC(BASECASEDATA, TARGETCASEDATA, MPOPT)
%   [RESULTS, SUCCESS] = RUNCPF_VSC_MTDC(...)
%
% Runs a continuation power flow for cases with explicit VSC-MTDC data in
% MPC.BUSDC, MPC.BRANCHDC and MPC.VSC. With the default unified method, the
% AC network, DC network and VSC equations are included directly in the CPF
% corrector/tangent system. Set MPOPT.VSC_MTDC.METHOD to 'sequential' to use
% the older continuation around RUNPF_VSC_MTDC at each continuation point.
%
% This routine is automatically selected by RUNCPF when both base and target
% cases contain VSC-MTDC data. It preserves the common CPF result fields
% CPF.LAM, CPF.V, CPF.MAX_LAM and CPF.DONE_MSG, and additionally stores the
% VSC-MTDC traces in CPF.BUSDC, CPF.BRANCHDC and CPF.VSC.
%
% The VSC-MTDC continuation supports numeric CPF.STOP_AT targets directly.
% For CPF.STOP_AT = 'NOSE' or 'FULL', the unified method follows the
% predictor/corrector continuation until the nose tangent is detected, the
% corrector can no longer converge, or the optional
% MPOPT.VSC_MTDC.CPF_MAX_LAM limit is reached. The sequential method keeps
% its historical PF-at-each-lambda behavior.
%
% Registered MPOPT.VSC_MTDC fields used by PF/CPF:
%   METHOD          'unified' (default) or 'sequential'
%   AC_SOLVER       AC PF solver for the sequential method, '' or 'runpf'
%                   by default, or 'runpf_psse'
%   MAX_IT          VSC-MTDC PF iteration override, default empty
%   TOL             unified PF mismatch tolerance override, default empty
%   DC_MAX_IT       sequential DC PF iteration limit, default 20
%   TOL_P           sequential active-power tolerance, default 1e-6
%   DC_TOL_P        DC PF active-power tolerance, default 1e-8
%   TOL_V           DC/AC voltage tolerance, default 1e-8
%   TOL_Q           reactive-power tolerance, default 1e-6
%   CPF_MAX_IT      maximum continuation points for 'NOSE'/'FULL', default 200
%   CPF_MAX_LAM     maximum lambda for 'NOSE'/'FULL' without failure, default 5
%   DISPATCH_POLICY VSC/HVDC dispatch policy passed to
%                   MAKE_VSC_HVDC_DISPATCH_TARGET before the CPF target is
%                   validated and interpolated.
%   HVDC_DISPATCH   alias for DISPATCH_POLICY
%   PSSE_AWARE      enable PSS/E-aware active-set updates, default 0
%   PSSE_CONTROL_LIMIT  'stop' (default) or 'freeze'. With 'freeze', CPF
%                   continues past a PSS/E discrete-control limit using the
%                   last feasible active set and records a freeze event.
%   PSSE_CONTROL_MAX_IT maximum PSS/E active-set iterations, default 20
%   CAPABILITY_ENFORCE  enable TESIS-style PF/CPF active-set enforcement,
%                   default 0
%   CAPABILITY_MAX_IT   max capability active-set iterations, default 10
%   CAPABILITY_PF_ENFORCE PF-specific capability override, default empty
%   CAPABILITY_PF_MAX_IT PF-specific max iteration override, default empty
%   CAPABILITY_VSC_SMAX VSC capability Smax override, default empty
%   CAPABILITY_VSC_VMAX VSC internal-voltage limit, default 1.15
%   CAPABILITY_VSC_MODE VSC projection mode override, default empty
%   CAPABILITY_GEN_ENFORCE generator capability override, default empty
%   CAPABILITY_GEN_MAX_IT generator capability max iteration override,
%                   default empty
%   CAPABILITY_GEN_SMAX generator capability Smax override, default empty
%   CAPABILITY_GEN_TYPE generator capability curve type, default 2
%
% Capability enforcement is TESIS-style solve-saturate-continue active-set
% logic. It is not OPF constraint enforcement and does not optimize
% redispatch. Capability audits can be run separately with
% CHECK_CAPABILITY_LIMITS.
%
% The base and target cases may also differ in VSC control set points
% PAC_SET, QAC_SET, VAC_SET, PDC_SET, VDC_SET and KDROOP. The continuation
% interpolates these values with lambda, allowing an HVDC transfer schedule
% to share active/reactive loading changes with conventional AC branches.
%
% See also runcpf, runcpf_psse, runpf_vsc_mtdc,
% make_vsc_hvdc_dispatch_target, check_capability_limits.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

%%-----  initialize  -----%%
if nargin < 5
    solvedcase = '';
    if nargin < 4
        fname = '';
        if nargin < 3 || isempty(mpopt)
            mpopt = mpoption;
            if nargin < 2
                basecasedata = 'case5_vsc_mtdc_beerten';
                targetcasedata = 'case5_vsc_mtdc_beerten';
            end
        end
    end
end

[PQ, ~, REF, ~, BUS_I, BUS_TYPE, PD, QD, GS, BS, ~, VM, VA] = idx_bus;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, ~, ~, ~, TAP, SHIFT, BR_STATUS] = idx_brch;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS] = idx_gen;
c = idx_vsc;
bdc = idx_busdc;
brdc = idx_branchdc;
vsc_hvdc_dispatch = [];

if nargin >= 1 && ischar(basecasedata) && strncmp(basecasedata, '__', 2)
    results = internal_dispatch(basecasedata, targetcasedata, mpopt);
    if nargout > 1
        success = [];
    end
    return;
end

mpcb = loadcase(basecasedata);
mpct = loadcase(targetcasedata);
[mpct, vsc_hvdc_dispatch] = apply_vsc_hvdc_dispatch_policy(mpcb, mpct, mpopt);
validate_vsc_cpf_cases(mpcb, mpct);

step = mpopt.cpf.step;
step_min = mpopt.cpf.step_min;
step_max = mpopt.cpf.step_max;
adapt_step = mpopt.cpf.adapt_step;
stop_at = mpopt.cpf.stop_at;
target_lam = [];
if isnumeric(stop_at)
    target_lam = stop_at;
end
opt = vsc_cpf_options(mpopt);
psse_controls_frozen = 0;

if mpopt.verbose > 4
    mpopt_pf = mpoption(mpopt, 'verbose', 2, 'out.all', 0);
else
    mpopt_pf = mpoption(mpopt, 'verbose', 0, 'out.all', 0);
end
mpopt_pf = mpoption(mpopt_pf, 'pf.enforce_q_lims', mpopt.cpf.enforce_q_lims);
method = vsc_pf_method(mpopt_pf);

if mpopt.verbose
    v = mpver('all');
    fprintf('\nMATPOWER Version %s, %s', v.Version, v.Date);
    fprintf(' -- %s VSC-MTDC Continuation Power Flow\n', method_title(method));
end

t0 = tic;
if strcmp(method, 'unified')
    [results, success] = run_unified_monolithic_cpf();
    results = attach_vsc_hvdc_dispatch(results);
    finish_outputs();
    if nargout > 1
        success = results.success;
    end
    return;
end

lam = 0;
mpc0 = vsc_cpf_current_mpc(mpcb, mpct, lam);
[base, success] = runpf_vsc_mtdc(mpc0, mpopt_pf);
if ~success
    results = base;
    results.success = 0;
    results.cpf = empty_cpf_results('Base case power flow did not converge.');
    results = attach_vsc_hvdc_dispatch(results);
    finish_outputs();
    return;
end

base_bus_ids = mpcb.bus(:, BUS_I);
base_branch_count = size(mpcb.branch, 1);
base_gen_count = size(mpcb.gen, 1);
[base, V] = stamp_original_ac_solution(base, base_bus_ids, ...
    base_branch_count, base_gen_count);

transfer = vsc_cpf_transfer_norm(mpcb, mpct);
cpf = initialize_trace(base, V, step, lam);
done_msg = '';
if transfer == 0
    done_msg = 'Base case and target case have identical load and generation';
end

last = base;
last_lam = lam;
events = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
cont_steps = 0;
failure = [];

while isempty(done_msg)
    if isempty(target_lam)
        if lam >= opt.cpf_max_lam
            done_msg = sprintf('Reached VSC-MTDC continuation lambda limit %.6g in %d continuation steps.', ...
                opt.cpf_max_lam, cont_steps);
            break;
        end
        if cont_steps >= opt.cpf_max_it
            done_msg = sprintf('Reached VSC-MTDC continuation step limit %d, lambda = %.6g.', ...
                opt.cpf_max_it, lam);
            break;
        end
        trial_step = min(step, opt.cpf_max_lam - lam);
    else
        if lam >= target_lam - mpopt.cpf.target_lam_tol
            done_msg = sprintf('Reached desired lambda %.6g in %d continuation steps.', ...
                target_lam, cont_steps);
            break;
        end
        trial_step = min(step, target_lam - lam);
    end

    if trial_step <= 0
        done_msg = sprintf('Reached desired lambda %.6g in %d continuation steps.', ...
            lam, cont_steps);
        break;
    end

    lam_try = lam + trial_step;
    mpc_try = vsc_cpf_current_mpc(mpcb, mpct, lam_try);
    [trial, ok] = runpf_vsc_mtdc(mpc_try, mpopt_pf);
    if ok
        [trial, V] = stamp_original_ac_solution(trial, base_bus_ids, ...
            base_branch_count, base_gen_count);
        cont_steps = cont_steps + 1;
        accepted_step = lam_try - lam;
        lam = lam_try;
        last_lam = lam;
        last = trial;
        cpf = append_trace(cpf, trial, V, accepted_step, lam);
        if mpopt.verbose > 1
            fprintf('step %3d  : stepsize = %-9.3g lambda = %6.3f, VSC-MTDC iterations = %d\n', ...
                cont_steps, accepted_step, lam, trial.iterations);
        end
        if adapt_step
            step = min(step * 1.25, step_max);
        end
    elseif trial_step / 2 >= step_min
        step = trial_step / 2;
        if mpopt.verbose > 1
            fprintf('step %3d  : stepsize = %-9.3g lambda = %6.3f did not converge, retrying with %.3g\n', ...
                cont_steps + 1, trial_step, lam_try, step);
        end
    else
        failure = struct('lambda', lam_try, 'step', trial_step);
        if isempty(target_lam)
            done_msg = sprintf('Reached VSC-MTDC %s loading limit in %d continuation steps, lambda = %.6g.', ...
                method, cont_steps, last_lam);
            events = struct('k', cont_steps, 'name', 'VSC_MTDC_LIMIT', ...
                'idx', 1, 'msg', done_msg);
            success = 1;
        else
            done_msg = sprintf('VSC-MTDC %s power flow did not converge at lambda %.6g.', ...
                method, lam_try);
            events = struct('k', cont_steps + 1, 'name', 'VSC_MTDC_FAIL', ...
                'idx', 1, 'msg', done_msg);
            success = 0;
        end
    end
end

results = last;
results.et = toc(t0);
results.success = success;
results.cpf = finalize_trace(cpf, cont_steps, done_msg, events, failure);
results.cpf.method = [method '_vsc_mtdc'];
results.cpf.ac_solver = vsc_ac_solver_name(mpopt_pf);
results = attach_vsc_hvdc_dispatch(results);

finish_outputs();

if nargout > 1
    success = results.success;
end

    function [results, success] = run_unified_monolithic_cpf()
        validate_unified_cpf_transfer(mpcb, mpct);

        [ctx, ctxt, Sdelta] = build_unified_context_pair();

        [x, eval, normF, pf_it, success] = ...
            solve_unified_pf_at_lambda(ctx, ctx.x0, 0, Sdelta);
        if ~success
            base = build_unified_cpf_result(ctx, x, eval, 0, pf_it, normF);
            results = base;
            results.success = 0;
            results.cpf = empty_cpf_results('Base case unified power flow did not converge.');
            return;
        end

        lam = 0;
        base = build_unified_cpf_result(ctx, x, eval, lam, pf_it, normF);
        base_bus_ids = mpcb.bus(:, BUS_I);
        base_branch_count = size(mpcb.branch, 1);
        base_gen_count = size(mpcb.gen, 1);
        [base, V] = stamp_original_ac_solution(base, base_bus_ids, ...
            base_branch_count, base_gen_count);
        [ctx, ctxt, Sdelta, x, ~, ~, pf_it, base, V, ...
            base_events, control_ok] = settle_unified_psse_controls( ...
            ctx, ctxt, Sdelta, x, eval, lam, pf_it, normF, base, ...
            base_bus_ids, base_branch_count, base_gen_count, 0);
        if ~control_ok
            results = base;
            results.success = 0;
            results.cpf = empty_cpf_results( ...
                'Base case PSS/E control re-correction did not converge.');
            return;
        end
        [ctx, ctxt, Sdelta, x, ~, ~, pf_it, base, V, ...
            cap_events, cap_ok] = settle_unified_vsc_capability_controls( ...
            ctx, ctxt, Sdelta, x, eval, lam, pf_it, normF, base, ...
            base_bus_ids, base_branch_count, base_gen_count, 0);
        if ~cap_ok
            results = base;
            results.success = 0;
            results.cpf = empty_cpf_results( ...
                'Base case VSC capability re-correction did not converge.');
            return;
        end
        base_events = append_event(base_events, cap_events);
        [ctx, ctxt, Sdelta, x, ~, ~, pf_it, base, V, ...
            gen_cap_events, gen_cap_ok] = ...
            settle_unified_gen_capability_controls(ctx, ctxt, Sdelta, x, ...
            eval, lam, pf_it, normF, base, base_bus_ids, ...
            base_branch_count, base_gen_count, 0);
        if ~gen_cap_ok
            results = base;
            results.success = 0;
            results.cpf = empty_cpf_results( ...
                'Base case generator capability re-correction did not converge.');
            return;
        end
        base_events = append_event(base_events, gen_cap_events);

        transfer = vsc_cpf_transfer_norm(mpcb, mpct);
        cpf = initialize_trace(base, V, step, lam);
        cpf.formulation = 'monolithic';
        cpf.jacobian = 'analytic';
        cpf.x = x;
        cpf.x_hat = x;
        cpf.z = zeros(length(x) + 1, 1);
        cpf.corrector_iterations = pf_it;
        done_msg = '';
        if transfer == 0
            done_msg = 'Base case and target case have identical load and generation';
        end

        direction = 1;
        z = zeros(length(x) + 1, 1);
        z(end) = direction;
        z = unified_cpf_tangent(ctx, x, lam, Sdelta, z, x, lam, ...
            mpopt.cpf.parameterization, direction);
        cpf.z(:, end) = z;

        last = base;
        last_lam = lam;
        events = base_events;
        cont_steps = 0;
        failure = [];
        curr_step = step;
        nose_tol = mpopt.cpf.nose_tol;

        while isempty(done_msg)
            if isempty(target_lam)
                if lam >= opt.cpf_max_lam && z(end) > 0
                    done_msg = sprintf('Reached VSC-MTDC monolithic CPF lambda limit %.6g in %d continuation steps.', ...
                        opt.cpf_max_lam, cont_steps);
                    break;
                end
                if cont_steps >= opt.cpf_max_it
                    done_msg = sprintf('Reached VSC-MTDC monolithic CPF step limit %d, lambda = %.6g.', ...
                        opt.cpf_max_it, lam);
                    break;
                end
                trial_step = curr_step;
            else
                if lam >= target_lam - mpopt.cpf.target_lam_tol
                    done_msg = sprintf('Reached desired lambda %.6g in %d continuation steps.', ...
                        target_lam, cont_steps);
                    break;
                end
                if z(end) <= 0
                    trial_step = curr_step;
                else
                    trial_step = min(curr_step, (target_lam - lam) / max(z(end), eps));
                end
            end

            if trial_step <= 0
                done_msg = sprintf('Reached desired lambda %.6g in %d continuation steps.', ...
                    lam, cont_steps);
                break;
            end

            xhat = x + trial_step * z(1:end-1);
            lamhat = lam + trial_step * z(end);
            ctx_hat = ctx;
            Sdelta_hat = Sdelta;
            [xnew, lamnew, evalnew, normFnew, corr_it, ok] = ...
                unified_cpf_corrector(ctx, Sdelta, xhat, lamhat, x, lam, ...
                    z, trial_step, mpopt.cpf.parameterization);

            if ok
                accepted_step = trial_step;
                r = build_unified_cpf_result(ctx, xnew, evalnew, lamnew, ...
                    corr_it, normFnew);
                [r, V] = stamp_original_ac_solution(r, base_bus_ids, ...
                    base_branch_count, base_gen_count);
                ctx0 = ctx;
                ctxt0 = ctxt;
                Sdelta0 = Sdelta;
                mpcb0 = mpcb;
                mpct0 = mpct;
                [ctx, ctxt, Sdelta, xnew, ~, ~, corr_it, ...
                    r, V, control_events, control_ok, control_changed] = ...
                    settle_unified_psse_controls(ctx, ctxt, Sdelta, xnew, ...
                    evalnew, lamnew, corr_it, normFnew, r, base_bus_ids, ...
                    base_branch_count, base_gen_count, cont_steps + 1);
                if ~control_ok
                    ctx = ctx0;
                    ctxt = ctxt0;
                    Sdelta = Sdelta0;
                    mpcb = mpcb0;
                    mpct = mpct0;
                    if trial_step / 2 >= step_min
                        curr_step = trial_step / 2;
                        if mpopt.verbose > 1
                            fprintf(['step %3d  : stepsize = %-9.3g ' ...
                                'lambda = %6.3f PSS/E control ' ...
                                're-correction did not converge, ' ...
                                'retrying with %.3g\n'], ...
                                cont_steps + 1, trial_step, lamnew, ...
                                curr_step);
                        end
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        if isempty(target_lam) && ...
                                freeze_psse_controls_after_limit()
                            psse_controls_frozen = 1;
                            curr_step = max(trial_step, step_min);
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic PSS/E control loading limit ' ...
                                'in %d continuation steps, lambda = %.6g; ' ...
                                'freezing PSS/E discrete controls and ' ...
                                'continuing CPF.'], cont_steps, last_lam);
                            events = append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'PSSE_CONTROL_FREEZE', 'idx', 1, ...
                                'msg', done_msg));
                            done_msg = '';
                            if mpopt.verbose > 1
                                fprintf(['step %3d  : PSS/E control limit ' ...
                                    'at lambda = %6.3f; freezing controls ' ...
                                    'and retrying with %.3g\n'], ...
                                    cont_steps + 1, lamnew, curr_step);
                            end
                            continue;
                        elseif isempty(target_lam)
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic PSS/E control loading limit ' ...
                                'in %d continuation steps, lambda = %.6g.'], ...
                                cont_steps, last_lam);
                            events = append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'PSSE_CONTROL_LIMIT', 'idx', 1, ...
                                'msg', done_msg));
                            success = 1;
                        else
                            done_msg = sprintf(['VSC-MTDC monolithic ' ...
                                'PSS/E control re-correction did not ' ...
                                'converge at lambda %.6g.'], lamnew);
                            events = append_event(events, struct( ...
                                'k', cont_steps + 1, ...
                                'name', 'PSSE_CONTROL_FAIL', 'idx', 1, ...
                                'msg', done_msg));
                            success = 0;
                        end
                        break;
                    end
                end
                events = append_event(events, control_events);

                ctx0 = ctx;
                ctxt0 = ctxt;
                Sdelta0 = Sdelta;
                mpcb0 = mpcb;
                mpct0 = mpct;
                [ctx, ctxt, Sdelta, xnew, ~, ~, corr_it, ...
                    r, V, cap_events, cap_ok, cap_changed] = ...
                    settle_unified_vsc_capability_controls(ctx, ctxt, ...
                    Sdelta, xnew, evalnew, lamnew, corr_it, normFnew, r, ...
                    base_bus_ids, base_branch_count, base_gen_count, ...
                    cont_steps + 1);
                if ~cap_ok
                    ctx = ctx0;
                    ctxt = ctxt0;
                    Sdelta = Sdelta0;
                    mpcb = mpcb0;
                    mpct = mpct0;
                    if trial_step / 2 >= step_min
                        curr_step = trial_step / 2;
                        if mpopt.verbose > 1
                            fprintf(['step %3d  : stepsize = %-9.3g ' ...
                                'lambda = %6.3f VSC capability ' ...
                                're-correction did not converge, ' ...
                                'retrying with %.3g\n'], ...
                                cont_steps + 1, trial_step, lamnew, ...
                                curr_step);
                        end
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        if isempty(target_lam)
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic VSC capability loading limit ' ...
                                'in %d continuation steps, lambda = %.6g.'], ...
                                cont_steps, last_lam);
                            events = append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'VSC_CAPABILITY_LIMIT', ...
                                'idx', 1, 'msg', done_msg));
                            success = 1;
                        else
                            done_msg = sprintf(['VSC-MTDC monolithic ' ...
                                'VSC capability re-correction did not ' ...
                                'converge at lambda %.6g.'], lamnew);
                            events = append_event(events, struct( ...
                                'k', cont_steps + 1, ...
                                'name', 'VSC_CAPABILITY_FAIL', ...
                                'idx', 1, 'msg', done_msg));
                            success = 0;
                        end
                        break;
                    end
                end
                events = append_event(events, cap_events);

                ctx0 = ctx;
                ctxt0 = ctxt;
                Sdelta0 = Sdelta;
                mpcb0 = mpcb;
                mpct0 = mpct;
                [ctx, ctxt, Sdelta, xnew, ~, ~, corr_it, ...
                    r, V, gen_cap_events, gen_cap_ok, gen_cap_changed] = ...
                    settle_unified_gen_capability_controls(ctx, ctxt, ...
                    Sdelta, xnew, evalnew, lamnew, corr_it, normFnew, r, ...
                    base_bus_ids, base_branch_count, base_gen_count, ...
                    cont_steps + 1);
                if ~gen_cap_ok
                    ctx = ctx0;
                    ctxt = ctxt0;
                    Sdelta = Sdelta0;
                    mpcb = mpcb0;
                    mpct = mpct0;
                    if trial_step / 2 >= step_min
                        curr_step = trial_step / 2;
                        if mpopt.verbose > 1
                            fprintf(['step %3d  : stepsize = %-9.3g ' ...
                                'lambda = %6.3f generator capability ' ...
                                're-correction did not converge, ' ...
                                'retrying with %.3g\n'], ...
                                cont_steps + 1, trial_step, lamnew, ...
                                curr_step);
                        end
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        if isempty(target_lam)
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic generator capability loading ' ...
                                'limit in %d continuation steps, lambda = ' ...
                                '%.6g.'], cont_steps, last_lam);
                            events = append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'GEN_CAPABILITY_LIMIT', ...
                                'idx', 1, 'msg', done_msg));
                            success = 1;
                        else
                            done_msg = sprintf(['VSC-MTDC monolithic ' ...
                                'generator capability re-correction did ' ...
                                'not converge at lambda %.6g.'], lamnew);
                            events = append_event(events, struct( ...
                                'k', cont_steps + 1, ...
                                'name', 'GEN_CAPABILITY_FAIL', ...
                                'idx', 1, 'msg', done_msg));
                            success = 0;
                        end
                        break;
                    end
                end
                events = append_event(events, gen_cap_events);

                active_set_changed = control_changed || cap_changed || ...
                    gen_cap_changed;
                if active_set_changed || length(z) ~= length(xnew) + 1 || ...
                        length(x) ~= length(xnew)
                    zseed = zeros(length(xnew) + 1, 1);
                    zseed(end) = direction;
                    znew = unified_cpf_tangent(ctx, xnew, lamnew, Sdelta, ...
                        zseed, xnew, lamnew, 1, direction);
                else
                    znew = unified_cpf_tangent(ctx, xnew, lamnew, Sdelta, z, ...
                        x, lam, mpopt.cpf.parameterization, direction);
                end
                nose_event = ~active_set_changed && isempty(target_lam) && ...
                    strcmpi(stop_at, 'NOSE') && ...
                    unified_nose_event(z, znew, nose_tol);
                if nose_event
                    [xnew, lamnew, ~, ~, znew, loc_it] = ...
                        locate_unified_nose(ctx, Sdelta, x, lam, z, ...
                        xnew, lamnew, znew, mpopt.cpf.parameterization, ...
                        direction, nose_tol, accepted_step);
                    corr_it = corr_it + loc_it;
                end
                cont_steps = cont_steps + 1;
                cpf = append_trace(cpf, r, V, accepted_step, lamnew);
                cpf.V_hat(:, end) = original_ac_voltage_from_eval(ctx_hat, xhat, ...
                    lamhat, Sdelta_hat, base_bus_ids);
                cpf.lam_hat(end) = lamhat;
                cpf.x = append_col_pad(cpf.x, xnew);
                cpf.x_hat = append_col_pad(cpf.x_hat, xhat);
                cpf.corrector_iterations = [cpf.corrector_iterations corr_it];
                cpf.z = append_col_pad(cpf.z, znew);

                if mpopt.verbose > 1
                    fprintf('step %3d  : stepsize = %-9.3g lambda = %6.3f, monolithic Newton steps = %d\n', ...
                        cont_steps, accepted_step, lamnew, corr_it);
                end

                if nose_event
                    lam = lamnew;
                    last_lam = lam;
                    last = r;
                    done_msg = sprintf('Reached VSC-MTDC monolithic nose point in %d continuation steps, lambda = %.6g.', ...
                        cont_steps, lam);
                    events = append_event(events, struct('k', cont_steps, ...
                        'name', 'NOSE', 'idx', 1, 'msg', done_msg));
                    break;
                end

                x = xnew;
                lam = lamnew;
                last_lam = lam;
                last = r;
                z = znew;
                if adapt_step
                    curr_step = min(curr_step * 1.25, step_max);
                end
            elseif trial_step / 2 >= step_min
                curr_step = trial_step / 2;
                if mpopt.verbose > 1
                    fprintf('step %3d  : stepsize = %-9.3g lambda = %6.3f corrector did not converge, retrying with %.3g\n', ...
                        cont_steps + 1, trial_step, lamhat, curr_step);
                end
            else
                failure = struct('lambda', lamhat, 'step', trial_step);
                if isempty(target_lam)
                    done_msg = sprintf('Reached VSC-MTDC monolithic loading limit in %d continuation steps, lambda = %.6g.', ...
                        cont_steps, last_lam);
                    events = struct('k', cont_steps, 'name', 'VSC_MTDC_LIMIT', ...
                        'idx', 1, 'msg', done_msg);
                    success = 1;
                else
                    done_msg = sprintf('VSC-MTDC monolithic corrector did not converge at lambda %.6g.', ...
                        lamhat);
                    events = struct('k', cont_steps + 1, 'name', 'VSC_MTDC_FAIL', ...
                        'idx', 1, 'msg', done_msg);
                    success = 0;
                end
            end
        end

        results = last;
        results.et = toc(t0);
        results.success = success;
        results.cpf = finalize_trace(cpf, cont_steps, done_msg, events, failure);
        results.cpf.method = 'unified_vsc_mtdc';
        results.cpf.ac_solver = 'unified';
        results.cpf.formulation = 'monolithic';
        results.cpf.jacobian = 'analytic';
    end

    function [ctx, ctxt, Sdelta] = build_unified_context_pair()
        validate_unified_cpf_transfer(mpcb, mpct);
        ctx = runpf_vsc_mtdc_unified('__setup', mpcb, mpopt_pf);
        ctxt = runpf_vsc_mtdc_unified('__setup', mpct, mpopt_pf);
        validate_unified_contexts(ctx, ctxt);
        Sdelta = ctxt.Sbase - ctx.Sbase;
        ctx = attach_unified_cpf_transfer(ctx, mpcb, mpct, Sdelta);
        ctxt = attach_unified_cpf_transfer(ctxt, mpcb, mpct, Sdelta);
    end

    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...
            ev, success, changed_any] = settle_unified_psse_controls( ...
            ctx, ctxt, Sdelta, x, eval, lam, iterations, normF, r, ...
            bus_ids, nbranch, ngen, event_k)
        ev = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
        success = 1;
        changed_any = 0;
        if ~unified_psse_controls_enabled()
            V = original_ac_voltage_for_result(r, bus_ids);
            return;
        end

        max_it = unified_psse_control_max_it();
        visited = cell(max_it + 1, 1);
        visited{1} = psse_active_set_signature(mpcb);
        nvisited = 1;
        for ctrl_it = 1:max_it
            [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
                unified_psse_control_update(r, lam);
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            if ~changed
                if psse_report_has_unsatisfied_controls(report)
                    success = 0;
                end
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            changed_any = 1;
            sig = psse_active_set_signature(mpcb_next);
            if any(strcmp(visited(1:nvisited), sig))
                current = vsc_cpf_current_mpc(mpcb, mpct, lam);
                [direct, direct_report] = ...
                    mp.psse_unified_control_update(current, r.bus);
                if direct_report.supported && ~direct_report.changed && ...
                        psse_control_violations(direct) == 0
                    mpcb = copy_psse_control_fields(mpcb, direct);
                    mpct = copy_psse_control_fields(mpct, direct);
                    V = original_ac_voltage_for_result(r, bus_ids);
                    return;
                end
                [aux_changed, aux_b, aux_t, aux_ac, aux_report, aux_ok] = ...
                    auxiliary_psse_control_update(r, lam);
                if aux_ok
                    if ~aux_changed
                        if ~psse_report_has_unsatisfied_controls(aux_report)
                            mpcb = copy_psse_control_fields(mpcb, aux_ac);
                            mpct = copy_psse_control_fields(mpct, aux_ac);
                            V = original_ac_voltage_for_result(r, bus_ids);
                            return;
                        end
                    else
                        aux_sig = psse_active_set_signature(aux_b);
                        if ~any(strcmp(visited(1:nvisited), aux_sig))
                            mpcb_next = aux_b;
                            mpct_next = aux_t;
                            ac_controlled = aux_ac;
                            report = aux_report;
                            sig = aux_sig;
                        else
                            success = 0;
                            V = original_ac_voltage_for_result(r, bus_ids);
                            return;
                        end
                    end
                else
                    success = 0;
                    V = original_ac_voltage_for_result(r, bus_ids);
                    return;
                end
            end
            nvisited = nvisited + 1;
            visited{nvisited} = sig;     %% schedule this active set as seen
            mpcb = mpcb_next;
            mpct = mpct_next;
            [ctx, ctxt, Sdelta] = build_unified_context_pair();
            x0 = unified_x_from_controlled_ac(ctx, ac_controlled, r);
            [x, eval, normF, it, ok] = ...
                solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);
            iterations = iterations + it;
            msg = sprintf(['PSS/E active-set update at lambda = %.8g; ' ...
                're-corrected unified VSC-MTDC point at fixed lambda ' ...
                '(buses %d, generators %d, branches %d).'], ...
                lam, report.changed_buses, report.changed_gens, ...
                report.changed_branches);
            ev = append_event(ev, struct('k', event_k, ...
                'name', 'PSSE_CONTROL', 'idx', ctrl_it, 'msg', msg));
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            r = build_unified_cpf_result(ctx, x, eval, lam, it, normF);
            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);
        end
        V = original_ac_voltage_for_result(r, bus_ids);
        success = 0;
    end

    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...
            ev, success, changed_any] = ...
            settle_unified_vsc_capability_controls(ctx, ctxt, Sdelta, x, ...
            eval, lam, iterations, normF, r, bus_ids, nbranch, ngen, event_k)
        ev = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
        success = 1;
        changed_any = 0;
        if ~unified_vsc_capability_enabled()
            V = original_ac_voltage_for_result(r, bus_ids);
            return;
        end

        max_it = unified_vsc_capability_max_it();
        visited = cell(max_it + 1, 1);
        visited{1} = vsc_capability_active_set_signature(mpcb);
        nvisited = 1;
        for ctrl_it = 1:max_it
            [changed, mpcb_next, mpct_next, report] = ...
                unified_vsc_capability_update(r, lam);
            if ~changed
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            changed_any = 1;
            sig = vsc_capability_active_set_signature(mpcb_next);
            if any(strcmp(visited(1:nvisited), sig))
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end
            nvisited = nvisited + 1;
            visited{nvisited} = sig;

            mpcb = mpcb_next;
            mpct = mpct_next;
            [ctx, ctxt, Sdelta] = build_unified_context_pair();
            x0 = unified_x_from_controlled_ac(ctx, r.ac, r);
            [x, eval, normF, it, ok] = ...
                solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);
            iterations = iterations + it;
            msg = sprintf(['VSC capability active-set update at ' ...
                'lambda = %.8g; saturated converters %s; ' ...
                're-corrected unified VSC-MTDC point at fixed lambda.'], ...
                lam, mat2str(report.changed_idx(:)'));
            ev = append_event(ev, vsc_capability_event_record( ...
                event_k, ctrl_it, msg, report));
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            r = build_unified_cpf_result(ctx, x, eval, lam, it, normF);
            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);
            ev(end) = complete_vsc_capability_event(ev(end), report, r);
        end
        V = original_ac_voltage_for_result(r, bus_ids);
        success = 0;
    end

    function [changed, bnext, tnext, report] = ...
            unified_vsc_capability_update(r, lam)
        changed = 0;
        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        bnext = mpcb;
        tnext = mpct;
        report = struct('changed_idx', [], 'from_mode', [], ...
            'to_mode', [], 'active_limit', {{}}, 'projection_mode', {{}}, ...
            'policy_reason', {{}}, 'target_ac_mode_if_saturated', [], ...
            'P', [], 'Q', [], 'V', [], 'margin_candidate', [], ...
            'margin_previous', [], 'lambda_previous', [], ...
            'lambda_candidate', [], 'lambda_event', [], ...
            'margin_event', [], 'event_location_method', {{}}, ...
            'previous_margin_error', {{}}, ...
            'P_saturated', [], 'Q_saturated', [], 'S_saturated', [], ...
            'Vmax', [], 'Smax', [], 'Smax_source', {{}}, ...
            'Vmax_source', {{}}, 'mode_source', {{}});

        if ~isfield(current, 'vsc') || isempty(current.vsc)
            return;
        end

        active = find(current.vsc(:, c.VSC_STATUS) > 0);
        tol = 1e-8;
        for kk = 1:length(active)
            k = active(kk);
            if size(r.vsc, 2) < c.QAC || size(r.vsc, 1) < k
                continue;
            end
            P0 = r.vsc(k, c.PAC);
            Q0 = r.vsc(k, c.QAC);
            V0 = vsc_capability_voltage(r.vsc, k);
            params = vsc_capability_params(current, opt, k, kk);
            Smax = params.Smax;
            mode_override = params.mode;
            policy = vsc_capability_policy(current.vsc(k, :), ...
                struct('mode', mode_override), k, kk);
            mode = policy.projection_mode;
            Vmax = params.Vmax;

            try
                [sat, Psat, Qsat, ~, info] = vsc_capability_curve( ...
                    P0, Q0, Smax, V0, r.vsc(k, :), mode, Vmax, ...
                    mpcb.baseMVA);
            catch me
                error('runcpf_vsc_mtdc: VSC row %d capability evaluation failed: %s', ...
                    k, me.message);
            end
            if ~sat
                continue;
            end

            from_mode = current.vsc(k, c.AC_MODE);
            to_mode = saturated_vsc_ac_mode(policy, P0, Psat, tol);
            old_vals = current.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]);
            new_vals = [to_mode Psat Qsat];
            if all(abs(old_vals - new_vals) <= tol)
                continue;
            end

            bnext.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]) = new_vals;
            tnext.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]) = new_vals;
            changed = 1;
            report.changed_idx(end+1, 1) = k;
            report.from_mode(end+1, 1) = from_mode;
            report.to_mode(end+1, 1) = to_mode;
            report.active_limit{end+1, 1} = info.active_limit;
            report.projection_mode{end+1, 1} = info.mode;
            report.policy_reason{end+1, 1} = policy.reason;
            report.target_ac_mode_if_saturated(end+1, 1) = ...
                policy.target_ac_mode_if_saturated;
            report.P(end+1, 1) = P0;
            report.Q(end+1, 1) = Q0;
            report.V(end+1, 1) = V0;
            report.margin_candidate(end+1, 1) = info.margin;
            [prev_margin, prev_lam, prev_err] = previous_vsc_capability_margin( ...
                k, kk, Smax, mode, Vmax);
            report.margin_previous(end+1, 1) = prev_margin;
            report.lambda_previous(end+1, 1) = prev_lam;
            report.previous_margin_error{end+1, 1} = prev_err;
            [lam_event, margin_event, method] = vsc_capability_event_lambda( ...
                prev_lam, lam, prev_margin, info.margin);
            report.lambda_candidate(end+1, 1) = lam;
            report.lambda_event(end+1, 1) = lam_event;
            report.margin_event(end+1, 1) = margin_event;
            report.event_location_method{end+1, 1} = method;
            report.P_saturated(end+1, 1) = Psat;
            report.Q_saturated(end+1, 1) = Qsat;
            report.S_saturated(end+1, 1) = abs(Psat + 1j * Qsat);
            report.Vmax(end+1, 1) = info.Vmax;
            report.Smax(end+1, 1) = info.Smax;
            report.Smax_source{end+1, 1} = params.Smax_source;
            report.Vmax_source{end+1, 1} = params.Vmax_source;
            report.mode_source{end+1, 1} = params.mode_source;
        end
    end

    function ev = vsc_capability_event_record(event_k, event_idx, msg, report)
        ev = struct('k', event_k, 'name', 'VSC_CAPABILITY', ...
            'idx', event_idx, 'msg', msg, ...
            'vsc_idx', report.changed_idx, ...
            'lambda_event', report.lambda_event, ...
            'lambda_candidate', report.lambda_candidate, ...
            'lambda_previous', report.lambda_previous, ...
            'event_location_method', {report.event_location_method}, ...
            'P_candidate', report.P, 'Q_candidate', report.Q, ...
            'V_candidate', report.V, ...
            'margin_candidate', report.margin_candidate, ...
            'margin_previous', report.margin_previous, ...
            'previous_margin_error', {report.previous_margin_error}, ...
            'margin_event', report.margin_event, ...
            'active_limit', {report.active_limit}, ...
            'projection_mode', {report.projection_mode}, ...
            'policy_reason', {report.policy_reason}, ...
            'target_ac_mode_if_saturated', ...
                report.target_ac_mode_if_saturated, ...
            'P_projected', report.P_saturated, ...
            'Q_projected', report.Q_saturated, ...
            'S_projected', report.S_saturated, ...
            'from_ac_mode', report.from_mode, ...
            'to_ac_mode', report.to_mode, ...
            'Smax', report.Smax, 'Vmax', report.Vmax, ...
            'Smax_source', {report.Smax_source}, ...
            'Vmax_source', {report.Vmax_source}, ...
            'mode_source', {report.mode_source}, ...
            'P_final', [], 'Q_final', [], 'V_final', [], ...
            'margin_final', [], 'inside_final', [], 'final_error', {{}});
    end

    function ev = complete_vsc_capability_event(ev, report, r)
        n = length(report.changed_idx);
        P_final = NaN(n, 1);
        Q_final = NaN(n, 1);
        V_final = NaN(n, 1);
        margin_final = NaN(n, 1);
        inside_final = false(n, 1);
        final_error = repmat({''}, n, 1);
        for ii = 1:n
            k = report.changed_idx(ii);
            if size(r.vsc, 1) < k || size(r.vsc, 2) < c.QAC
                continue;
            end
            P_final(ii) = r.vsc(k, c.PAC);
            Q_final(ii) = r.vsc(k, c.QAC);
            V_final(ii) = vsc_capability_voltage(r.vsc, k);
            try
                [sat_final, ~, ~, ~, info_final] = vsc_capability_curve( ...
                    P_final(ii), Q_final(ii), report.Smax(ii), ...
                    V_final(ii), r.vsc(k, :), ...
                    report.projection_mode{ii}, report.Vmax(ii), ...
                    mpcb.baseMVA);
                margin_final(ii) = info_final.margin;
                inside_final(ii) = ~sat_final;
            catch me
                final_error{ii} = me.message;
            end
        end
        ev.P_final = P_final;
        ev.Q_final = Q_final;
        ev.V_final = V_final;
        ev.margin_final = margin_final;
        ev.inside_final = inside_final;
        ev.final_error = final_error;
    end

    function [margin, lam_prev, err] = previous_vsc_capability_margin( ...
            k, ~, Smax, mode, Vmax)
        margin = NaN;
        lam_prev = NaN;
        err = '';
        if ~(exist('last', 'var') && isstruct(last) && ...
                isfield(last, 'vsc') && size(last.vsc, 1) >= k && ...
                size(last.vsc, 2) >= c.QAC && exist('last_lam', 'var') && ...
                isfinite(last_lam))
            return;
        end
        try
            Pprev = last.vsc(k, c.PAC);
            Qprev = last.vsc(k, c.QAC);
            Vprev = vsc_capability_voltage(last.vsc, k);
            [~, ~, ~, ~, info_prev] = vsc_capability_curve( ...
                Pprev, Qprev, Smax, Vprev, last.vsc(k, :), ...
                mode, Vmax, mpcb.baseMVA);
            margin = info_prev.margin;
            lam_prev = last_lam;
        catch me
            err = me.message;
        end
    end

    function [lam_event, margin_event, method] = ...
            vsc_capability_event_lambda(lam_prev, lam_candidate, ...
            margin_prev, margin_candidate)
        lam_event = lam_candidate;
        margin_event = margin_candidate;
        method = 'candidate';
        if isfinite(lam_prev) && isfinite(lam_candidate) && ...
                isfinite(margin_prev) && isfinite(margin_candidate) && ...
                lam_candidate ~= lam_prev && margin_prev >= 0 && ...
                margin_candidate < 0
            den = margin_prev - margin_candidate;
            if den > 0
                alpha = margin_prev / den;
                lam_event = lam_prev + alpha * (lam_candidate - lam_prev);
                margin_event = 0;
                method = 'linear_margin';
            end
        end
    end

    function mode = saturated_vsc_ac_mode(policy, P0, Psat, tol)
        if abs(Psat - P0) > tol
            mode = policy.target_ac_mode_if_p_changed;
        else
            mode = policy.target_ac_mode_if_p_preserved;
        end
    end

    function V = vsc_capability_voltage(vsc, row)
        if size(vsc, 2) >= c.VAC_INTERNAL && ...
                isfinite(vsc(row, c.VAC_INTERNAL)) && ...
                vsc(row, c.VAC_INTERNAL) > 0
            V = vsc(row, c.VAC_INTERNAL);
        elseif size(vsc, 2) >= c.VAC_PCC && ...
                isfinite(vsc(row, c.VAC_PCC)) && vsc(row, c.VAC_PCC) > 0
            V = vsc(row, c.VAC_PCC);
        else
            V = vsc(row, c.VAC_SET);
        end
    end

    function sig = vsc_capability_active_set_signature(mpc)
        cols = existing_cols([c.AC_MODE c.PAC_SET c.QAC_SET], ...
            mpc.vsc, mpc.vsc);
        vals = reshape(mpc.vsc(:, cols), [], 1);
        sig = sprintf('%.9g,', round(vals(:)' * 1e9) / 1e9);
    end

    function TorF = unified_vsc_capability_enabled()
        TorF = isfield(opt, 'capability_enforce') && ...
            option_is_enabled(opt.capability_enforce);
    end

    function max_it = unified_vsc_capability_max_it()
        max_it = 10;
        if isfield(opt, 'capability_max_it') && ...
                ~isempty(opt.capability_max_it)
            max_it = opt.capability_max_it;
        end
    end

    function TorF = option_is_enabled(val)
        if ischar(val)
            TorF = any(strcmpi(val, {'1', 'on', 'true', 'yes'}));
        else
            TorF = any(val(:) ~= 0);
        end
    end

    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...
            ev, success, changed_any] = ...
            settle_unified_gen_capability_controls(ctx, ctxt, Sdelta, x, ...
            eval, lam, iterations, normF, r, bus_ids, nbranch, ngen, event_k)
        ev = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
        success = 1;
        changed_any = 0;
        if ~unified_gen_capability_enabled()
            V = original_ac_voltage_for_result(r, bus_ids);
            return;
        end

        max_it = unified_gen_capability_max_it();
        visited = cell(max_it + 1, 1);
        visited{1} = gen_capability_active_set_signature(mpcb);
        nvisited = 1;
        for ctrl_it = 1:max_it
            [changed, mpcb_next, mpct_next, report] = ...
                unified_gen_capability_update(r, lam);
            if ~changed
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            changed_any = 1;
            sig = gen_capability_active_set_signature(mpcb_next);
            if any(strcmp(visited(1:nvisited), sig))
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end
            nvisited = nvisited + 1;
            visited{nvisited} = sig;

            mpcb = mpcb_next;
            mpct = mpct_next;
            [ctx, ctxt, Sdelta] = build_unified_context_pair();
            x0 = unified_x_from_controlled_ac(ctx, r.ac, r);
            [x, eval, normF, it, ok] = ...
                solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);
            iterations = iterations + it;
            msg = sprintf(['Generator capability active-set update at ' ...
                'lambda = %.8g; saturated generators %s; ' ...
                're-corrected unified VSC-MTDC point at fixed lambda.'], ...
                lam, mat2str(report.changed_idx(:)'));
            ev = append_event(ev, struct('k', event_k, ...
                'name', 'GEN_CAPABILITY', 'idx', ctrl_it, 'msg', msg));
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            r = build_unified_cpf_result(ctx, x, eval, lam, it, normF);
            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);
        end
        V = original_ac_voltage_for_result(r, bus_ids);
        success = 0;
    end

    function [changed, bnext, tnext, report] = ...
            unified_gen_capability_update(r, lam)
        changed = 0;
        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        bnext = mpcb;
        tnext = mpct;
        report = struct('changed_idx', [], 'bus', [], ...
            'active_limit', {{}}, 'P', [], 'Q', [], ...
            'P_saturated', [], 'Q_saturated', []);

        ng = size(current.gen, 1);
        if ng == 0
            return;
        end

        tol = 1e-8;
        for g = 1:min(ng, size(r.gen, 1))
            if current.gen(g, GEN_STATUS) <= 0 || isload(current.gen(g, :))
                continue;
            end
            if is_slack_gen(current, g)
                continue;
            end

            P0 = r.gen(g, PG);
            Q0 = r.gen(g, QG);
            Smax = gen_capability_option_value('capability_gen_smax', ...
                g, g, default_gen_smax(current, g));
            type = gen_capability_option_value('capability_gen_type', ...
                g, g, 2);
            try
                [sat, Psat, Qsat, ~, info] = ...
                    gen_capability_curve(P0, Q0, Smax, type);
            catch me
                error('runcpf_vsc_mtdc: generator row %d capability evaluation failed: %s', ...
                    g, me.message);
            end
            if ~sat
                continue;
            end

            old_vals = current.gen(g, [PG QG QMAX QMIN]);
            new_vals = old_vals;
            new_vals(1) = Psat;
            q_changed = abs(Qsat - Q0) > tol;
            if q_changed
                new_vals(2:4) = Qsat;
            end
            if all(abs(old_vals - new_vals) <= tol) && ...
                    (~q_changed || gen_bus_is_pq(current, g))
                continue;
            end

            bnext.gen(g, [PG QG QMAX QMIN]) = new_vals;
            tnext.gen(g, [PG QG QMAX QMIN]) = new_vals;
            if q_changed
                bnext = set_gen_bus_type(bnext, g, PQ);
                tnext = set_gen_bus_type(tnext, g, PQ);
            end

            changed = 1;
            report.changed_idx(end+1, 1) = g;
            report.bus(end+1, 1) = current.gen(g, GEN_BUS);
            report.active_limit{end+1, 1} = info.active_limit;
            report.P(end+1, 1) = P0;
            report.Q(end+1, 1) = Q0;
            report.P_saturated(end+1, 1) = Psat;
            report.Q_saturated(end+1, 1) = Qsat;
        end
    end

    function TorF = is_slack_gen(mpc, g)
        row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
        TorF = ~isempty(row) && mpc.bus(row, BUS_TYPE) == REF;
    end

    function Smax = default_gen_smax(mpc, g)
        Smax = mpc.gen(g, MBASE);
        if ~isfinite(Smax) || Smax <= 0
            Smax = mpc.baseMVA;
        end
    end

    function mpc = set_gen_bus_type(mpc, g, type)
        row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
        if ~isempty(row) && mpc.bus(row, BUS_TYPE) ~= REF
            mpc.bus(row, BUS_TYPE) = type;
        end
    end

    function TorF = gen_bus_is_pq(mpc, g)
        row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
        TorF = ~isempty(row) && mpc.bus(row, BUS_TYPE) == PQ;
    end

    function val = gen_capability_option_value(name, g, kk, default)
        val = default;
        if ~isfield(opt, name) || isempty(opt.(name))
            return;
        end
        raw = opt.(name);
        if iscell(raw)
            if isscalar(raw)
                val = raw{1};
            elseif numel(raw) >= g
                val = raw{g};
            elseif numel(raw) >= kk
                val = raw{kk};
            else
                error('runcpf_vsc_mtdc: option %s has invalid length', name);
            end
        elseif isnumeric(raw)
            if isscalar(raw)
                val = raw;
            elseif numel(raw) >= g
                val = raw(g);
            elseif numel(raw) >= kk
                val = raw(kk);
            else
                error('runcpf_vsc_mtdc: option %s has invalid length', name);
            end
        else
            val = raw;
        end
    end

    function sig = gen_capability_active_set_signature(mpc)
        bus_vals = reshape(mpc.bus(:, BUS_TYPE), [], 1);
        cols = existing_cols([PG QG QMAX QMIN], mpc.gen, mpc.gen);
        gen_vals = reshape(mpc.gen(:, cols), [], 1);
        vals = [bus_vals; gen_vals];
        sig = sprintf('%.9g,', round(vals(:)' * 1e9) / 1e9);
    end

    function TorF = unified_gen_capability_enabled()
        if isfield(opt, 'capability_gen_enforce') && ...
                ~isempty(opt.capability_gen_enforce)
            TorF = option_is_enabled(opt.capability_gen_enforce);
        else
            TorF = unified_vsc_capability_enabled();
        end
    end

    function max_it = unified_gen_capability_max_it()
        max_it = 10;
        if isfield(opt, 'capability_gen_max_it') && ...
                ~isempty(opt.capability_gen_max_it)
            max_it = opt.capability_gen_max_it;
        elseif isfield(opt, 'capability_max_it') && ...
                ~isempty(opt.capability_max_it)
            max_it = opt.capability_max_it;
        end
    end

    function sig = psse_active_set_signature(mpc)
        [~, ~, ~, ~, ~, BUS_TYPE2, PD2, QD2, GS2, BS2] = idx_bus;
        [~, ~, ~, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
        [~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
            TAP2, SHIFT2, BR_STATUS2] = idx_brch;
        bus_cols = existing_cols([BUS_TYPE2 PD2 QD2 GS2 BS2], ...
            mpc.bus, mpc.bus);
        gen_cols = existing_cols([QMAX2 QMIN2 VG2 GEN_STATUS2], ...
            mpc.gen, mpc.gen);
        branch_cols = existing_cols([BR_R2 BR_X2 BR_B2 RATE_A2 RATE_B2 ...
            RATE_C2 TAP2 SHIFT2 BR_STATUS2], mpc.branch, mpc.branch);
        vals = [
            reshape(mpc.bus(:, bus_cols), [], 1);
            reshape(mpc.gen(:, gen_cols), [], 1);
            reshape(mpc.branch(:, branch_cols), [], 1)
        ];
        sig = sprintf('%.9g,', round(vals(:)' * 1e9) / 1e9);
    end

    function TorF = unified_psse_controls_enabled()
        TorF = ~psse_controls_frozen && ...
            isfield(mpopt_pf, 'vsc_mtdc') && ...
            isfield(mpopt_pf.vsc_mtdc, 'psse_aware') && ...
            any(mpopt_pf.vsc_mtdc.psse_aware) && has_psse_control_data(mpcb);
    end

    function TorF = freeze_psse_controls_after_limit()
        TorF = isfield(opt, 'psse_control_limit') && ...
            ischar(opt.psse_control_limit) && ...
            strcmpi(opt.psse_control_limit, 'freeze');
    end

    function TorF = has_psse_control_data(mpc)
        TorF = 0;
        if ~isfield(mpc, 'psse') || isempty(mpc.psse)
            return;
        end
        families = {'pqbrak', 'xfmr', 'genq', 'twodc', 'swshunt', 'facts'};
        for ff = 1:length(families)
            if isfield(mpc.psse, families{ff}) && ...
                    ~isempty(mpc.psse.(families{ff}))
                TorF = 1;
                return;
            end
        end
    end

    function max_it = unified_psse_control_max_it()
        max_it = 10;
        if isfield(opt, 'psse_control_max_it') && ...
                ~isempty(opt.psse_control_max_it)
            max_it = opt.psse_control_max_it;
        end
    end

    function [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
            unified_psse_control_update(r, lam)
        ok = 1;
        mpcb_next = mpcb;
        mpct_next = mpct;

        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        [direct, direct_report] = mp.psse_unified_control_update( ...
            current, r.bus);
        if direct_report.supported
            ac_controlled = psse_control_case_from_unified_result(r);
            ac_controlled = copy_original_active_set_to_ac( ...
                ac_controlled, direct);
            [changed, report] = psse_active_set_changed( ...
                current, ac_controlled);
            if changed || (~has_auxiliary_psse_control_data(current) && ...
                    ~psse_report_has_unsatisfied_controls(report))
                if changed
                    [mpcb_next, mpct_next] = apply_psse_active_set_update( ...
                        current, ac_controlled);
                end
                return;
            end
        end

        [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
            auxiliary_psse_control_update(r, lam);
    end

    function [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
            auxiliary_psse_control_update(r, lam)
        changed = 0;
        ok = 1;
        mpcb_next = mpcb;
        mpct_next = mpct;
        report = struct('changed_buses', 0, 'changed_gens', 0, ...
            'changed_branches', 0);
        ac_controlled = [];

        ac_case = psse_control_case_from_unified_result(r);
        if ~isfield(ac_case, 'psse') || isempty(ac_case.psse)
            return;
        end

        control_opt = psse_control_mpopt();
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

        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        [changed, report] = psse_active_set_changed(current, ac_controlled);
        if changed
            [mpcb_next, mpct_next] = apply_psse_active_set_update( ...
                current, ac_controlled);
        end
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
    end

    function ac = copy_original_active_set_to_ac(ac, mpc)
        [~, ~, ~, ~, ~, BUS_TYPE2, PD2, QD2, GS2, BS2, ~, ~, ~] = idx_bus;
        [~, ~, QG2, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
        [~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
            TAP2, SHIFT2, BR_STATUS2] = idx_brch;

        for kk = 1:size(mpc.bus, 1)
            row = find(ac.bus(:, BUS_I) == mpc.bus(kk, BUS_I), 1);
            if ~isempty(row)
                cols = existing_cols([BUS_TYPE2 PD2 QD2 GS2 BS2], ...
                    ac.bus, mpc.bus);
                ac.bus(row, cols) = mpc.bus(kk, cols);
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
    end

    function control_opt = psse_control_mpopt()
        control_opt = mpoption(mpopt, 'verbose', 0, 'out.all', 0, ...
            'pf.enforce_q_lims', 0);
        if isfield(control_opt, 'vsc_mtdc')
            control_opt = rmfield(control_opt, 'vsc_mtdc');
        end
    end

    function [changed, report] = psse_active_set_changed(current, ac)
        [~, ~, ~, ~, ~, BUS_TYPE2, PD2, QD2, GS2, BS2] = idx_bus;
        [~, ~, ~, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
        [~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
            TAP2, SHIFT2, BR_STATUS2] = idx_brch;
        tol = 1e-8;

        ac_bus = original_rows(ac.bus, mpcb.bus(:, BUS_I));
        bus_cols0 = [GS2 BS2];
        if has_psse_genq_control(mpcb)
            bus_cols0 = [BUS_TYPE2 bus_cols0];
        end
        if psse_load_equiv_changed(ac)
            bus_cols0 = [bus_cols0 PD2 QD2];
        end
        bus_cols = existing_cols(bus_cols0, current.bus, ac_bus);
        bus_delta = matrix_delta(current.bus(:, bus_cols), ...
            ac_bus(:, bus_cols), tol);

        ng = size(mpcb.gen, 1);
        gen_cols = existing_cols([QMAX2 QMIN2 VG2 GEN_STATUS2], ...
            current.gen, ac.gen(1:ng, :));
        gen_delta = matrix_delta(current.gen(:, gen_cols), ...
            ac.gen(1:ng, gen_cols), tol);

        branch_cols = existing_cols([BR_R2 BR_X2 BR_B2 RATE_A2 RATE_B2 ...
            RATE_C2 TAP2 SHIFT2 BR_STATUS2], current.branch, ...
            ac.branch(1:size(mpcb.branch, 1), :));
        branch_delta = matrix_delta(current.branch(:, branch_cols), ...
            ac.branch(1:size(mpcb.branch, 1), branch_cols), tol);

        report = struct( ...
            'changed_buses',    nnz(bus_delta), ...
            'changed_gens',     nnz(gen_delta), ...
            'changed_branches', nnz(branch_delta), ...
            'control_violations', psse_control_violations(ac), ...
            'control_cycles', psse_control_cycles(ac) );
        changed = report.changed_buses || report.changed_gens || ...
            report.changed_branches;
    end

    function TorF = psse_report_has_unsatisfied_controls(report)
        TorF = isfield(report, 'control_violations') && ...
            report.control_violations > 0;
    end

    function n = psse_control_violations(mpc)
        n = psse_control_report_count(mpc, 'xfmr', 'below_band') + ...
            psse_control_report_count(mpc, 'xfmr', 'above_band') + ...
            psse_control_report_count(mpc, 'swshunt', 'below_band') + ...
            psse_control_report_count(mpc, 'swshunt', 'above_band');
    end

    function n = psse_control_cycles(mpc)
        n = psse_control_report_count(mpc, 'xfmr', 'cycle_detected') + ...
            psse_control_report_count(mpc, 'swshunt', 'cycle_detected');
    end

    function n = psse_control_report_count(mpc, family, field)
        n = 0;
        if isfield(mpc, 'psse') && isfield(mpc.psse, family) && ...
                isfield(mpc.psse.(family), 'control') && ...
                isfield(mpc.psse.(family).control, field)
            val = mpc.psse.(family).control.(field);
            n = nnz(val);
        end
    end

    function [bnext, tnext] = apply_psse_active_set_update(current, ac)
        [~, ~, ~, ~, ~, BUS_TYPE2, PD2, QD2, GS2, BS2, ~, VM2, VA2] = idx_bus;
        [~, ~, QG2, QMAX2, QMIN2, VG2, ~, GEN_STATUS2] = idx_gen;
        [~, ~, BR_R2, BR_X2, BR_B2, RATE_A2, RATE_B2, RATE_C2, ...
            TAP2, SHIFT2, BR_STATUS2] = idx_brch;
        tol = 1e-8;

        bnext = mpcb;
        tnext = mpct;
        ac_bus = original_rows(ac.bus, mpcb.bus(:, BUS_I));
        if psse_load_equiv_changed(ac)
            load_delta = ac_bus(:, [PD2 QD2]) - current.bus(:, [PD2 QD2]);
        else
            load_delta = zeros(size(bnext.bus, 1), 2);
        end
        shared_bus_cols0 = [GS2 BS2 VM2 VA2];
        if has_psse_genq_control(mpcb)
            shared_bus_cols0 = [BUS_TYPE2 shared_bus_cols0];
        end
        shared_bus_cols = existing_cols(shared_bus_cols0, bnext.bus, ac_bus);
        bnext.bus(:, shared_bus_cols) = ac_bus(:, shared_bus_cols);
        tnext.bus(:, shared_bus_cols) = ac_bus(:, shared_bus_cols);
        bnext.bus(:, [PD2 QD2]) = bnext.bus(:, [PD2 QD2]) + load_delta;
        tnext.bus(:, [PD2 QD2]) = tnext.bus(:, [PD2 QD2]) + load_delta;

        ng = size(mpcb.gen, 1);
        ac_gen = ac.gen(1:ng, :);
        gen_active_cols = existing_cols([QMAX2 QMIN2 VG2 GEN_STATUS2], ...
            current.gen, ac_gen);
        gen_rows = any(abs(current.gen(:, gen_active_cols) - ...
            ac_gen(:, gen_active_cols)) > tol, 2);
        gen_copy_cols = existing_cols([QG2 QMAX2 QMIN2 VG2 GEN_STATUS2], ...
            bnext.gen, ac_gen);
        bnext.gen(gen_rows, gen_copy_cols) = ac_gen(gen_rows, gen_copy_cols);
        tnext.gen(gen_rows, gen_copy_cols) = ac_gen(gen_rows, gen_copy_cols);

        nb = size(mpcb.branch, 1);
        ac_branch = ac.branch(1:nb, :);
        branch_cols = existing_cols([BR_R2 BR_X2 BR_B2 RATE_A2 RATE_B2 ...
            RATE_C2 TAP2 SHIFT2 BR_STATUS2], bnext.branch, ac_branch);
        bnext.branch(:, branch_cols) = ac_branch(:, branch_cols);
        tnext.branch(:, branch_cols) = ac_branch(:, branch_cols);

        bnext = copy_psse_control_fields(bnext, ac);
        tnext = copy_psse_control_fields(tnext, ac);
    end

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
                return;
            end
        end
    end

    function TorF = has_psse_genq_control(mpc)
        TorF = isfield(mpc, 'psse') && psse_family_present(mpc, 'genq');
    end

    function TorF = psse_family_present(mpc, name)
        TorF = isfield(mpc, 'psse') && isfield(mpc.psse, name) && ...
            ~isempty(mpc.psse.(name));
        if TorF && isstruct(mpc.psse.(name)) && ...
                isfield(mpc.psse.(name), 'num') && isempty(mpc.psse.(name).num)
            TorF = 0;
        end
    end

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
    end

    function cols = existing_cols(cols, a, b)
        cols = cols(cols <= size(a, 2) & cols <= size(b, 2));
    end

    function mask = matrix_delta(a, b, tol)
        if isempty(a) || isempty(b)
            mask = false(size(a, 1), 1);
        else
            mask = any(abs(a - b) > tol, 2);
        end
    end

    function x0 = unified_x_from_controlled_ac(ctx, ac, r)
        x0 = ctx.x0;
        ext = ctx.ac.order.bus.i2e;
        Va = ctx.ac.bus(:, VA) * pi / 180;
        Vm = ctx.ac.bus(:, VM);
        for ii = 1:length(ext)
            row = find(ac.bus(:, BUS_I) == ext(ii), 1);
            if ~isempty(row)
                Va(ii) = ac.bus(row, VA) * pi / 180;
                Vm(ii) = ac.bus(row, VM);
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
    end

    function [x, eval, normF, iterations, success] = ...
            solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta)
        x = x0;
        [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
        normF = norm(F, Inf);
        success = normF < ctx.opt.tol;
        iterations = 0;
        while ~success && iterations < ctx.opt.max_it
            if isempty(eval) || ~isfinite(normF)
                break;
            end
            iterations = iterations + 1;
            J = runpf_vsc_mtdc_unified('__jacobian', ctx_lam, eval, []);
            dx = -J \ F;
            [x, F, eval, normF, ctx_lam] = unified_accept_pf_step( ...
                ctx, lam, Sdelta, x, dx, normF);
            success = normF < ctx.opt.tol;
        end
    end

    function [x, F, eval, normF, ctx_lam] = unified_accept_pf_step( ...
            ctx, lam, Sdelta, x0, dx, normF0)
        alpha = 1;
        while alpha >= 1/64
            xt = x0 + alpha * dx;
            [Ft, evalt, ctx_t] = unified_eval_at_lambda(ctx, xt, lam, Sdelta);
            normFt = norm(Ft, Inf);
            if isfinite(normFt) && normFt < normF0
                x = xt;
                F = Ft;
                eval = evalt;
                normF = normFt;
                ctx_lam = ctx_t;
                return;
            end
            alpha = alpha / 2;
        end
        x = x0 + dx;
        [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
        normF = norm(F, Inf);
    end

    function [x, lam, eval, normF, iterations, success] = ...
            unified_cpf_corrector(ctx, Sdelta, xhat, lamhat, xprev, ...
            lamprev, z, h, parm)
        x = xhat;
        lam = lamhat;
        iterations = 0;
        [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
        P = unified_cpf_p(parm, h, z, x, lam, xprev, lamprev);
        normF = norm([F; P], Inf);
        while normF >= ctx.opt.tol && iterations < ctx.opt.max_it
            if isempty(eval) || ~isfinite(normF)
                break;
            end
            iterations = iterations + 1;
            J = runpf_vsc_mtdc_unified('__jacobian', ctx_lam, eval, []);
            dF_dlam = unified_dF_dlam(ctx, Sdelta, x, lam);
            [dPdx, dPdlam] = unified_cpf_p_jac(parm, z, x, lam, ...
                xprev, lamprev);
            A = [J dF_dlam; dPdx dPdlam];
            dx = -A \ [F; P];
            x = x + dx(1:end-1);
            lam = lam + dx(end);
            [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
            P = unified_cpf_p(parm, h, z, x, lam, xprev, lamprev);
            normF = norm([F; P], Inf);
        end
        success = normF < ctx.opt.tol;
    end

    function z = unified_cpf_tangent(ctx, x, lam, Sdelta, zprv, xprev, ...
            lamprev, parm, direction)
        [~, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
        J = runpf_vsc_mtdc_unified('__jacobian', ctx_lam, eval, []);
        dF_dlam = unified_dF_dlam(ctx, Sdelta, x, lam);
        [dPdx, dPdlam] = unified_cpf_p_jac(parm, zprv, x, lam, ...
            xprev, lamprev);
        A = [J dF_dlam; dPdx dPdlam];
        rhs = zeros(length(x) + 1, 1);
        rhs(end) = sign(direction);
        z = A \ rhs;
        z = z / norm(z);
    end

    function tf = unified_nose_event(z0, z1, tol)
        tf = z0(end) > 0 && (z1(end) <= 0 || abs(z1(end)) <= tol);
    end

    function [xn, lamn, evaln, normFn, zn, iterations] = ...
            locate_unified_nose(ctx, Sdelta, xlo, lamlo, zlo, xhi, ...
            lamhi, zhi, parm, direction, tol, hstep)
        max_loc_it = 30;
        iterations = 0;
        hlo = 0;
        hhi = hstep;
        [Flo, eval_lo] = unified_eval_at_lambda(ctx, xlo, lamlo, Sdelta);
        norm_lo = norm(Flo, Inf);
        [Fhi, eval_hi] = unified_eval_at_lambda(ctx, xhi, lamhi, Sdelta);
        norm_hi = norm(Fhi, Inf);

        for ii = 1:max_loc_it
            if abs(zhi(end)) <= tol || abs(zlo(end)) <= tol || ...
                    abs(hhi - hlo) <= tol
                break;
            end
            denom = zlo(end) - zhi(end);
            if abs(denom) < eps
                hmid = (hlo + hhi) / 2;
            else
                alpha = zlo(end) / denom;
                alpha = min(max(alpha, 0.1), 0.9);
                hmid = hlo + alpha * (hhi - hlo);
            end
            hinc = hmid - hlo;
            [xm, lamm, evalm, normFm, corr_it, ok] = ...
                solve_unified_arc_point(ctx, Sdelta, xlo, lamlo, zlo, ...
                hinc, parm);
            iterations = iterations + corr_it;
            if ~ok
                hmid = (hlo + hhi) / 2;
                hinc = hmid - hlo;
                [xm, lamm, evalm, normFm, corr_it, ok] = ...
                    solve_unified_arc_point(ctx, Sdelta, xlo, lamlo, zlo, ...
                    hinc, parm);
                iterations = iterations + corr_it;
                if ~ok
                    break;
                end
            end
            zm = unified_cpf_tangent(ctx, xm, lamm, Sdelta, zlo, ...
                xlo, lamlo, parm, direction);
            if zm(end) > 0
                xlo = xm;
                lamlo = lamm;
                zlo = zm;
                eval_lo = evalm;
                norm_lo = normFm;
                hlo = hmid;
            else
                xhi = xm;
                lamhi = lamm;
                zhi = zm;
                eval_hi = evalm;
                norm_hi = normFm;
                hhi = hmid;
            end
        end

        if abs(zlo(end)) < abs(zhi(end))
            xn = xlo;
            lamn = lamlo;
            zn = zlo;
            evaln = eval_lo;
            normFn = norm_lo;
        else
            xn = xhi;
            lamn = lamhi;
            zn = zhi;
            evaln = eval_hi;
            normFn = norm_hi;
        end
    end

    function [x, lam, eval, normF, iterations, success] = ...
            solve_unified_arc_point(ctx, Sdelta, x0, lam0, z0, h, parm)
        xhat = x0 + h * z0(1:end-1);
        lamhat = lam0 + h * z0(end);
        [x, lam, eval, normF, iterations, success] = ...
            unified_cpf_corrector(ctx, Sdelta, xhat, lamhat, x0, lam0, ...
            z0, h, parm);
    end

    function [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta)
        ctx_lam = unified_context_at_lambda(ctx, lam);
        [F, eval] = unified_eval(ctx_lam, x, ctx.Sbase + lam * Sdelta);
    end

    function [F, eval] = unified_eval(ctx, x, Sbase)
        [F, eval] = runpf_vsc_mtdc_unified('__mismatch', ctx, x, Sbase);
    end

    function ctx_lam = unified_context_at_lambda(ctx, lam)
        ctx_lam = ctx;
        if isfield(ctx, 'cpf_transfer')
            tr = ctx.cpf_transfer;
            ctx_lam.mpc = vsc_cpf_current_mpc(tr.base, tr.target, lam);
        end
    end

    function dF = unified_dF_dlam(ctx, Sdelta, x, lam)
        model = ctx.model;
        dF = zeros(length(ctx.x0), 1);
        if unified_has_vsc_setpoint_transfer(ctx)
            h = 1e-6 * max(1, abs(lam));
            Fp = unified_eval_at_lambda(ctx, x, lam + h, Sdelta);
            Fm = unified_eval_at_lambda(ctx, x, lam - h, Sdelta);
            dF = (Fp - Fm) / (2 * h);
            return;
        end
        row_p = 1:length(model.nonref);
        row_q = length(row_p) + (1:length(model.qeq));
        dF(row_p) = -real(Sdelta(model.nonref));
        dF(row_q) = -imag(Sdelta(model.qeq));
    end

    function TorF = unified_has_vsc_setpoint_transfer(ctx)
        TorF = isfield(ctx, 'cpf_transfer') && ...
            isfield(ctx.cpf_transfer, 'has_vsc_setpoint_transfer') && ...
            ctx.cpf_transfer.has_vsc_setpoint_transfer;
    end

    function P = unified_cpf_p(parm, h, z, x, lam, xprev, lamprev)
        if parm == 1
            if lam >= lamprev
                P = lam - lamprev - h;
            else
                P = lamprev - lam - h;
            end
        elseif parm == 2
            P = sum(([x; lam] - [xprev; lamprev]).^2) - h^2;
        elseif parm == 3
            P = z' * ([x; lam] - [xprev; lamprev]) - h;
        else
            error('runcpf_vsc_mtdc: unknown CPF parameterization %d', parm);
        end
    end

    function [dPdx, dPdlam] = unified_cpf_p_jac(parm, z, x, lam, xprev, lamprev)
        if parm == 1
            dPdx = zeros(1, length(x));
            if lam >= lamprev
                dPdlam = 1;
            else
                dPdlam = -1;
            end
        elseif parm == 2
            dPdx = 2 * (x - xprev)';
            if lam == lamprev
                dPdlam = 1;
            else
                dPdlam = 2 * (lam - lamprev);
            end
        elseif parm == 3
            dPdx = z(1:end-1)';
            dPdlam = z(end);
        else
            error('runcpf_vsc_mtdc: unknown CPF parameterization %d', parm);
        end
    end

    function r = build_unified_cpf_result(ctx, x, eval, lam, iterations, normF)
        mpc = vsc_cpf_current_mpc(mpcb, mpct, lam);
        r = runpf_vsc_mtdc_unified('__results', ctx, eval, mpc);
        r.success = 1;
        r.iterations = iterations;
        r.convergence = struct( ...
            'converged',       1, ...
            'method',          'unified', ...
            'jacobian',        'analytic', ...
            'psse_aware',      ctx.opt.psse_aware, ...
            'tol',             ctx.opt.tol, ...
            'max_mismatch',    normF, ...
            'state_vector_size', length(x), ...
            'formulation',     'monolithic' );
    end

    function V = original_ac_voltage_from_eval(ctx, xhat, lamhat, Sdelta, bus_ids)
        [~, eval_hat] = unified_eval_at_lambda(ctx, xhat, lamhat, Sdelta);
        rhat = runpf_vsc_mtdc_unified('__results', ctx, eval_hat, mpcb);
        V = original_ac_voltage_for_result(rhat, bus_ids);
    end

    function V = original_ac_voltage_for_result(r, bus_ids)
        bus = r.ac.bus;
        V = zeros(length(bus_ids), 1);
        for ii = 1:length(bus_ids)
            row = find(bus(:, BUS_I) == bus_ids(ii), 1);
            V(ii) = bus(row, VM) * exp(1j * pi/180 * bus(row, VA));
        end
    end

    function finish_outputs()
        if exist('results', 'var') && isstruct(results)
            if mpopt.verbose && isfield(results, 'cpf') && isfield(results.cpf, 'done_msg')
                fprintf('CPF TERMINATION: %s\n', results.cpf.done_msg);
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
            if solvedcase
                savecase(solvedcase, results);
            end
        end
    end

    function [t, dispatch] = apply_vsc_hvdc_dispatch_policy(b, t, o)
        dispatch = [];
        if isfield(t, 'vsc_hvdc_dispatch')
            dispatch = t.vsc_hvdc_dispatch;
        end
        policy = [];
        if isfield(o, 'vsc_mtdc')
            if isfield(o.vsc_mtdc, 'dispatch_policy')
                policy = o.vsc_mtdc.dispatch_policy;
            elseif isfield(o.vsc_mtdc, 'hvdc_dispatch')
                policy = o.vsc_mtdc.hvdc_dispatch;
            end
        end
        if ~isempty(policy)
            [t, dispatch] = make_vsc_hvdc_dispatch_target(b, t, policy);
            t.vsc_hvdc_dispatch = dispatch;
        end
    end

    function r = attach_vsc_hvdc_dispatch(r)
        if ~isempty(vsc_hvdc_dispatch) && isfield(r, 'cpf')
            r.cpf.vsc_hvdc_dispatch = vsc_hvdc_dispatch;
        end
    end

    function validate_vsc_cpf_cases(b, t)
        if ~has_vsc_mtdc(b) || ~has_vsc_mtdc(t)
            error('runcpf_vsc_mtdc: base and target cases must both contain busdc, branchdc and vsc fields');
        end
        if b.baseMVA ~= t.baseMVA
            error('runcpf_vsc_mtdc: base and target baseMVA values must match');
        end
        same_size('bus', b.bus, t.bus);
        same_size('gen', b.gen, t.gen);
        same_size('branch', b.branch, t.branch);
        same_size('busdc', b.busdc, t.busdc);
        same_size('branchdc', b.branchdc, t.branchdc);
        same_size('vsc', b.vsc, t.vsc);

        if any(b.bus(:, BUS_I) ~= t.bus(:, BUS_I)) || ...
                any(b.bus(:, BUS_TYPE) ~= t.bus(:, BUS_TYPE))
            error('runcpf_vsc_mtdc: base and target AC bus numbers/types must match');
        end
        if any(b.gen(:, GEN_BUS) ~= t.gen(:, GEN_BUS)) || ...
                any(b.gen(:, GEN_STATUS) ~= t.gen(:, GEN_STATUS))
            error('runcpf_vsc_mtdc: base and target generator buses/statuses must match');
        end
        if any(any(b.branch(:, [F_BUS T_BUS BR_STATUS]) ~= ...
                t.branch(:, [F_BUS T_BUS BR_STATUS])))
            error('runcpf_vsc_mtdc: base and target AC branch topology/status must match');
        end
        if any(any(b.busdc(:, [bdc.BUSDC_I bdc.BUSDC_STATUS]) ~= ...
                t.busdc(:, [bdc.BUSDC_I bdc.BUSDC_STATUS])))
            error('runcpf_vsc_mtdc: base and target DC bus numbers/statuses must match');
        end
        if any(any(b.branchdc(:, [brdc.F_BUSDC brdc.T_BUSDC brdc.BRDC_STATUS]) ~= ...
                t.branchdc(:, [brdc.F_BUSDC brdc.T_BUSDC brdc.BRDC_STATUS])))
            error('runcpf_vsc_mtdc: base and target DC branch topology/status must match');
        end
        fixed_vsc_cols = [c.VSC_BUS c.BUSDC c.VSC_STATUS c.AC_MODE c.DC_MODE ...
            c.LOSS_A:c.REACTOR_RATE_C];
        if any(any(b.vsc(:, fixed_vsc_cols) ~= t.vsc(:, fixed_vsc_cols)))
            error('runcpf_vsc_mtdc: base and target VSC topology, modes and loss/station data must match');
        end
    end

    function validate_unified_cpf_transfer(b, t)
        tol = 1e-12;
        if any(any(abs(b.bus(:, [GS BS VM]) - t.bus(:, [GS BS VM])) > tol))
            error('runcpf_vsc_mtdc: unified monolithic CPF requires constant bus shunts and voltage set points');
        end
        if any(abs(b.gen(:, VG) - t.gen(:, VG)) > tol)
            error('runcpf_vsc_mtdc: unified monolithic CPF requires constant generator voltage set points');
        end
        if any(any(abs(b.branch(:, [BR_R BR_X BR_B TAP SHIFT]) - ...
                t.branch(:, [BR_R BR_X BR_B TAP SHIFT])) > tol))
            error('runcpf_vsc_mtdc: unified monolithic CPF requires constant AC branch admittances');
        end
        if any(abs(b.branchdc(:, brdc.BRDC_R) - t.branchdc(:, brdc.BRDC_R)) > tol)
            error('runcpf_vsc_mtdc: unified monolithic CPF requires constant DC branch resistances');
        end
        if any(abs(b.busdc(:, bdc.VDC) - t.busdc(:, bdc.VDC)) > tol)
            error('runcpf_vsc_mtdc: unified monolithic CPF requires constant initial DC voltages');
        end
    end

    function validate_unified_contexts(ctx, ctxt)
        same_vector('unified non-reference AC buses', ctx.model.nonref, ctxt.model.nonref);
        same_vector('unified AC voltage variables', ctx.model.vm_vars, ctxt.model.vm_vars);
        same_vector('unified reactive equations', ctx.model.qeq, ctxt.model.qeq);
        same_vector('unified VSC voltage controls', ctx.model.vctrl, ctxt.model.vctrl);
        same_vector('unified Pac variables', ctx.model.pac_vars, ctxt.model.pac_vars);
        same_vector('unified DC voltage variables', ctx.model.dc_var, ctxt.model.dc_var);
        if norm(full(ctx.Ybus - ctxt.Ybus), Inf) > 1e-10
            error('runcpf_vsc_mtdc: unified monolithic CPF base and target AC admittance matrices differ');
        end
        if norm(full(ctx.Gdc - ctxt.Gdc), Inf) > 1e-10
            error('runcpf_vsc_mtdc: unified monolithic CPF base and target DC conductance matrices differ');
        end
    end

    function ctx = attach_unified_cpf_transfer(ctx, b, t, Sdelta)
        cols = vsc_setpoint_transfer_cols();
        ctx.cpf_transfer = struct( ...
            'base',                       b, ...
            'target',                     t, ...
            'Sdelta',                     Sdelta, ...
            'vsc_setpoint_cols',          cols, ...
            'has_vsc_setpoint_transfer',  ...
                any(any(abs(b.vsc(:, cols) - t.vsc(:, cols)) > 1e-12)) );
    end

    function same_vector(name, a, b)
        if length(a) ~= length(b) || any(a(:) ~= b(:))
            error('runcpf_vsc_mtdc: base and target %s must match', name);
        end
    end

    function same_size(name, a, b)
        if size(a, 1) ~= size(b, 1) || size(a, 2) ~= size(b, 2)
            error('runcpf_vsc_mtdc: base and target %s matrices must have the same size', name);
        end
    end

    function opt = vsc_cpf_options(o)
        opt = struct('cpf_max_it', 200, 'cpf_max_lam', 5, ...
            'capability_enforce', 0, 'capability_max_it', 10, ...
            'capability_vsc_smax', [], 'capability_vsc_vmax', 1.15, ...
            'capability_vsc_mode', [], 'capability_gen_enforce', [], ...
            'capability_gen_max_it', [], 'capability_gen_smax', [], ...
            'capability_gen_type', 2);
        if isfield(o, 'vsc_mtdc')
            f = fieldnames(o.vsc_mtdc);
            for kk = 1:length(f)
                val = o.vsc_mtdc.(f{kk});
                if ~isempty(val)
                    opt.(f{kk}) = val;
                end
            end
        end
    end

    function mpc = vsc_cpf_current_mpc(b, t, l)
        mpc = b;
        mpc.bus(:, PD) = b.bus(:, PD) + l * (t.bus(:, PD) - b.bus(:, PD));
        mpc.bus(:, QD) = b.bus(:, QD) + l * (t.bus(:, QD) - b.bus(:, QD));
        mpc.gen(:, PG) = b.gen(:, PG) + l * (t.gen(:, PG) - b.gen(:, PG));
        cols = vsc_setpoint_transfer_cols();
        mpc.vsc(:, cols) = b.vsc(:, cols) + l * (t.vsc(:, cols) - b.vsc(:, cols));
        mpc.busdc(:, bdc.VDC) = b.busdc(:, bdc.VDC) + ...
            l * (t.busdc(:, bdc.VDC) - b.busdc(:, bdc.VDC));
    end

    function n = vsc_cpf_transfer_norm(b, t)
        cols = vsc_setpoint_transfer_cols();
        dx = [
            reshape(t.bus(:, [PD QD]) - b.bus(:, [PD QD]), [], 1);
            t.gen(:, PG) - b.gen(:, PG);
            reshape(t.vsc(:, cols) - b.vsc(:, cols), [], 1);
            t.busdc(:, bdc.VDC) - b.busdc(:, bdc.VDC)
        ];
        n = norm(dx(:), Inf);
    end

    function cols = vsc_setpoint_transfer_cols()
        cols = [c.PAC_SET c.QAC_SET c.VAC_SET c.PDC_SET c.VDC_SET c.KDROOP];
    end

    function [r, V] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen)
        V = original_ac_voltage(r, bus_ids);
        r.bus = original_rows(r.ac.bus, bus_ids);
        r.branch = r.ac.branch(1:nbranch, :);
        r.gen = r.ac.gen(1:ngen, :);
    end

    function rows = original_rows(bus, bus_ids)
        rows = zeros(length(bus_ids), size(bus, 2));
        for kk = 1:length(bus_ids)
            row = find(bus(:, BUS_I) == bus_ids(kk), 1);
            rows(kk, :) = bus(row, :);
        end
    end

    function V = original_ac_voltage(r, bus_ids)
        bus = r.ac.bus;
        V = zeros(length(bus_ids), 1);
        for kk = 1:length(bus_ids)
            row = find(bus(:, BUS_I) == bus_ids(kk), 1);
            V(kk) = bus(row, VM) * exp(1j * pi/180 * bus(row, VA));
        end
    end

    function cpf = initialize_trace(r, V, s, l)
        cpf = struct( ...
            'V_hat',       V, ...
            'lam_hat',     l, ...
            'V',           V, ...
            'lam',         l, ...
            'steps',       0, ...
            'iterations',  0, ...
            'max_lam',     l, ...
            'gen',         r.gen, ...
            'busdc',       r.busdc, ...
            'branchdc',    r.branchdc, ...
            'vsc',         r.vsc, ...
            'vsc_iterations', r.iterations, ...
            'default_step', s );
    end

    function cpf = append_trace(cpf, r, V, s, l)
        cpf.V_hat = [cpf.V_hat V];
        cpf.lam_hat = [cpf.lam_hat l];
        cpf.V = [cpf.V V];
        cpf.lam = [cpf.lam l];
        cpf.steps = [cpf.steps s];
        cpf.gen = cat(3, cpf.gen, r.gen);
        cpf.busdc = cat(3, cpf.busdc, r.busdc);
        cpf.branchdc = cat(3, cpf.branchdc, r.branchdc);
        cpf.vsc = cat(3, cpf.vsc, r.vsc);
        cpf.vsc_iterations = [cpf.vsc_iterations r.iterations];
    end

    function A = append_col_pad(A, col)
        col = col(:);
        if isempty(A)
            A = col;
            return;
        end
        nr = max(size(A, 1), length(col));
        if size(A, 1) < nr
            A = [A; NaN(nr - size(A, 1), size(A, 2))];
        end
        if length(col) < nr
            col = [col; NaN(nr - length(col), 1)];
        end
        A = [A col];
    end

    function ev = append_event(ev, add)
        if isempty(add)
            return;
        end
        if ~isempty(ev)
            ev = add_missing_event_fields(ev, fieldnames(add));
            add = add_missing_event_fields(add, fieldnames(ev));
            add = orderfields(add, ev);
        end
        if isempty(ev)
            ev = add;
        else
            ev(end+1:end+length(add)) = add;
        end
    end

    function ev = add_missing_event_fields(ev, names)
        for kk = 1:length(names)
            if ~isfield(ev, names{kk})
                [ev.(names{kk})] = deal([]);
            end
        end
    end

    function cpf = finalize_trace(cpf, it, msg, ev, fail)
        cpf.iterations = it;
        cpf.max_lam = max(cpf.lam);
        cpf.done_msg = msg;
        cpf.events = ev;
        cpf.failure = fail;
    end

    function cpf = empty_cpf_results(msg)
        cpf = struct('V_hat', [], 'lam_hat', [], 'V', [], 'lam', [], ...
            'steps', [], 'iterations', 0, 'max_lam', 0, ...
            'done_msg', msg, 'events', struct('k', {}, 'name', {}, ...
            'idx', {}, 'msg', {}), 'method', [method '_vsc_mtdc']);
    end

    function name = vsc_ac_solver_name(o)
        if strcmp(vsc_pf_method(o), 'unified')
            name = 'unified';
            return;
        end
        name = 'runpf';
        if isfield(o, 'vsc_mtdc') && isfield(o.vsc_mtdc, 'ac_solver') && ...
                ~isempty(o.vsc_mtdc.ac_solver)
            name = o.vsc_mtdc.ac_solver;
        end
    end

    function method = vsc_pf_method(o)
        method = 'unified';
        if isfield(o, 'vsc_mtdc') && isfield(o.vsc_mtdc, 'method') && ...
                ~isempty(o.vsc_mtdc.method)
            method = lower(o.vsc_mtdc.method);
        end
    end

    function title = method_title(method)
        title = [upper(method(1)) method(2:end)];
    end

    function out = internal_dispatch(op, args, default_mpopt)
        if nargin < 2 || isempty(args)
            args = struct();
        end
        if nargin < 3 || isempty(default_mpopt)
            default_mpopt = mpoption;
        end
        switch op
            case '__cpf_system'
                out = internal_cpf_system(args, default_mpopt);
            otherwise
                error('runcpf_vsc_mtdc: unknown internal operation ''%s''', op);
        end
    end

    function out = internal_cpf_system(args, default_mpopt)
        if ~isfield(args, 'base') || ~isfield(args, 'target')
            error('runcpf_vsc_mtdc: __cpf_system requires base and target cases');
        end
        if isfield(args, 'mpopt') && ~isempty(args.mpopt)
            opt0 = args.mpopt;
        else
            opt0 = default_mpopt;
        end
        if opt0.verbose > 4
            opt_pf = mpoption(opt0, 'verbose', 2, 'out.all', 0);
        else
            opt_pf = mpoption(opt0, 'verbose', 0, 'out.all', 0);
        end
        opt_pf = mpoption(opt_pf, 'pf.enforce_q_lims', ...
            opt0.cpf.enforce_q_lims);

        b = loadcase(args.base);
        t = loadcase(args.target);
        [t, dispatch] = apply_vsc_hvdc_dispatch_policy(b, t, opt0);
        validate_vsc_cpf_cases(b, t);
        validate_unified_cpf_transfer(b, t);
        ctx = runpf_vsc_mtdc_unified('__setup', b, opt_pf);
        ctxt = runpf_vsc_mtdc_unified('__setup', t, opt_pf);
        validate_unified_contexts(ctx, ctxt);
        Sdelta = ctxt.Sbase - ctx.Sbase;
        ctx = attach_unified_cpf_transfer(ctx, b, t, Sdelta);
        ctxt = attach_unified_cpf_transfer(ctxt, b, t, Sdelta);

        if isfield(args, 'x') && ~isempty(args.x)
            x = args.x;
        else
            x = ctx.x0;
        end
        if isfield(args, 'lam') && ~isempty(args.lam)
            lam = args.lam;
        else
            lam = 0;
        end
        if isfield(args, 'parameterization') && ~isempty(args.parameterization)
            parm = args.parameterization;
        else
            parm = opt0.cpf.parameterization;
        end
        if isfield(args, 'z') && ~isempty(args.z)
            z = args.z;
        else
            z = zeros(length(x) + 1, 1);
            z(end) = 1;
        end
        if isfield(args, 'h') && ~isempty(args.h)
            h = args.h;
        else
            h = opt0.cpf.step;
        end
        if isfield(args, 'xprev') && ~isempty(args.xprev)
            xprev = args.xprev;
        else
            xprev = x - h * z(1:end-1);
        end
        if isfield(args, 'lamprev') && ~isempty(args.lamprev)
            lamprev = args.lamprev;
        else
            lamprev = lam - h * z(end);
        end

        [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
        J = runpf_vsc_mtdc_unified('__jacobian', ctx_lam, eval, []);
        dF_dlam = unified_dF_dlam(ctx, Sdelta, x, lam);
        P = unified_cpf_p(parm, h, z, x, lam, xprev, lamprev);
        [dPdx, dPdlam] = unified_cpf_p_jac(parm, z, x, lam, ...
            xprev, lamprev);

        out = struct( ...
            'ctx',              ctx, ...
            'ctxt',             ctxt, ...
            'Sdelta',           Sdelta, ...
            'x',                x, ...
            'lam',              lam, ...
            'z',                z, ...
            'h',                h, ...
            'xprev',            xprev, ...
            'lamprev',          lamprev, ...
            'parameterization', parm, ...
            'F',                F, ...
            'P',                P, ...
            'eval',             eval, ...
            'J',                J, ...
            'dF_dlam',          dF_dlam, ...
            'dPdx',             dPdx, ...
            'dPdlam',           dPdlam, ...
            'vsc_hvdc_dispatch', dispatch, ...
            'A',                [J dF_dlam; dPdx dPdlam], ...
            'F_aug',            [F; P] );
    end

end
