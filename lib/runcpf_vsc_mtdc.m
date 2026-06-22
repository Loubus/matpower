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
%   CPF_POLICIES    incremental CPF load/gen/HVDC redispatch policies,
%                   usually provided as MPC.CPF_POLICIES in the base case
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
%   CAPABILITY_LIMIT  'stop' (default) or 'freeze'. With 'freeze', CPF
%                   continues past a capability loading limit by freezing
%                   the exhausted CPF dispatch at the last feasible point.
%   CAPABILITY_VSC_LIMIT VSC-specific capability limit behavior override,
%                   default empty, falling back to CAPABILITY_LIMIT
%   CAPABILITY_GEN_LIMIT generator-specific capability limit behavior
%                   override, default empty, falling back to CAPABILITY_LIMIT
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
% CPF results include CPF.ACTIVE_SET_FAILURE_POLICY, which reports the
% declared and observed failure policy for enabled PSS/E, VSC capability,
% generator capability, and HVDC derating active-set features.
%
% Capability enforcement is TESIS-style solve-saturate-continue active-set
% logic. It is not OPF constraint enforcement and does not optimize
% redispatch. Capability audits can be run separately with
% CHECK_CAPABILITY_LIMITS.
%
% When MPC.CPF_POLICIES is present, lambda scales only the load direction.
% Generator and HVDC redispatch are accumulated incrementally from the last
% accepted CPF point with d_lambda. HVDC redispatch acts on PAC_SET/QAC_SET,
% not PDC_SET. Cases without CPF_POLICIES keep the historical target-case
% interpolation of generator and VSC set points.
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
[GEN_BUS, PG, QG, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;
c = idx_vsc;
bdc = idx_busdc;
brdc = idx_branchdc;
vsc_hvdc_dispatch = [];
gen_dispatch = [];
cpf_policy_state = struct('enabled', 0);
vsc_capability_recorded_idx = [];
gen_capability_recorded_idx = [];
profile_timing = init_profile_timing(0);

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
mpcb_transfer0 = mpcb;
mpct_transfer0 = mpct;

step = mpopt.cpf.step;
step_min = mpopt.cpf.step_min;
step_max = mpopt.cpf.step_max;
adapt_step = mpopt.cpf.adapt_step;
stop_at = mpopt.cpf.stop_at;
full_trace = ischar(stop_at) && strcmpi(stop_at, 'FULL');
full_trace_target_lam = 0;
target_lam = [];
if isnumeric(stop_at)
    target_lam = stop_at;
end
opt = vsc_cpf_options(mpopt);
cpf_policy_state = init_incremental_cpf_policy_state(mpcb, mpct, opt);
validate_capability_limit_options();
profile_enabled = isfield(opt, 'profile') && option_is_enabled(opt.profile);
profile_timing = init_profile_timing(profile_enabled);
psse_controls_frozen = 0;
vsc_capability_transfer_frozen = 0;
vsc_capability_transfer_backoff_count = 0;
vsc_capability_resaturation_count = 0;
vsc_slack_q_backoff_count = 0;
gen_capability_dispatch_frozen = 0;
unified_context_cache = struct('key', '', 'ctx', [], 'ctxt', [], ...
    'Sdelta', []);
vsc_capability_param_cache = struct('key', {}, 'params', {}, ...
    'policy', {});

if mpopt.verbose > 4
    mpopt_pf = mpoption(mpopt, 'verbose', 2, 'out.all', 0);
else
    mpopt_pf = mpoption(mpopt, 'verbose', 0, 'out.all', 0);
end
mpopt_pf = mpoption(mpopt_pf, 'pf.enforce_q_lims', mpopt.cpf.enforce_q_lims);
method = vsc_pf_method(mpopt_pf);
active_set_policy_config = init_active_set_failure_policy_config();

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
        refresh_incremental_policy_anchor(lam);
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
        base_events = vsc_mtdc_cpf_append_event(base_events, cap_events);
        [ctx, ctxt, Sdelta, x, ~, lam, ~, pf_it, base, V, ...
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
        base_events = vsc_mtdc_cpf_append_event(base_events, gen_cap_events);
        refresh_incremental_policy_anchor(lam);

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
            target_lambda_step = 0;
            trial_parameterization = mpopt.cpf.parameterization;
            if isempty(target_lam)
                if full_trace && z(end) < 0 && ...
                        lam <= full_trace_target_lam + mpopt.cpf.target_lam_tol
                    done_msg = sprintf(['Traced full VSC-MTDC monolithic ' ...
                        'continuation curve in %d continuation steps.'], ...
                        cont_steps);
                    events = vsc_mtdc_cpf_append_event(events, struct( ...
                        'k', cont_steps, 'name', 'TARGET_LAM', ...
                        'idx', 1, 'msg', done_msg, ...
                        'lambda_event', lam));
                    break;
                end
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
                if full_trace && z(end) < 0 && ...
                        lam + trial_step * z(end) <= ...
                        full_trace_target_lam + mpopt.cpf.target_lam_tol
                    trial_step = lam - full_trace_target_lam;
                    trial_parameterization = 1;
                    target_lambda_step = 1;
                end
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

            ctx_hat = ctx;
            Sdelta_hat = Sdelta;
            xhat = x + trial_step * z(1:end-1);
            lamhat = lam + trial_step * z(end);
            if target_lambda_step
                lamhat = full_trace_target_lam;
            end
            [xnew, lamnew, evalnew, normFnew, corr_it, ok] = ...
                unified_cpf_corrector(ctx, Sdelta, xhat, lamhat, x, lam, ...
                    z, trial_step, trial_parameterization);

            if ok
                accepted_step = trial_step;
                r = build_unified_cpf_result(ctx, xnew, evalnew, lamnew, ...
                    corr_it, normFnew);
                [r, V] = stamp_original_ac_solution(r, base_bus_ids, ...
                    base_branch_count, base_gen_count);
                active_set_changed = 0;
                [ctx, ctxt, Sdelta, xnew, evalnew, lamnew, normFnew, ...
                    corr_it, r, V, control_events, control_ok, ...
                    ~, retry_step, active_set_changed] = ...
                    run_active_set_stage('psse', 'PSS/E control', '', ...
                    ctx, ctxt, Sdelta, xnew, evalnew, lamnew, normFnew, ...
                    corr_it, r, base_bus_ids, base_branch_count, ...
                    base_gen_count, cont_steps + 1, trial_step, step_min, ...
                    active_set_changed);
                if ~control_ok
                    if ~isempty(retry_step)
                        curr_step = retry_step;
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        if isempty(target_lam) && ...
                                freeze_psse_controls_after_limit()
                            psse_controls_frozen = 1;
                            failure = [];
                            curr_step = freeze_recovery_step();
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic PSS/E control loading limit ' ...
                                'in %d continuation steps, lambda = %.6g; ' ...
                                'freezing PSS/E discrete controls and ' ...
                                'continuing CPF.'], cont_steps, last_lam);
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
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
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'PSSE_CONTROL_LIMIT', 'idx', 1, ...
                                'msg', done_msg));
                            success = 1;
                        else
                            done_msg = sprintf(['VSC-MTDC monolithic ' ...
                                'PSS/E control re-correction did not ' ...
                                'converge at lambda %.6g.'], lamnew);
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
                                'k', cont_steps + 1, ...
                                'name', 'PSSE_CONTROL_FAIL', 'idx', 1, ...
                                'msg', done_msg));
                            success = 0;
                        end
                        break;
                    end
                end
                events = vsc_mtdc_cpf_append_event(events, control_events);

                [ctx, ctxt, Sdelta, xnew, evalnew, lamnew, normFnew, ...
                    corr_it, r, V, cap_events, cap_ok, ~, ...
                    retry_step, active_set_changed] = ...
                    run_active_set_stage('vsc', 'VSC capability', ...
                    'vsc_capability_recorr_failed', ctx, ctxt, Sdelta, ...
                    xnew, evalnew, lamnew, normFnew, corr_it, r, ...
                    base_bus_ids, base_branch_count, base_gen_count, ...
                    cont_steps + 1, trial_step, step_min, ...
                    active_set_changed);
                if ~cap_ok
                    if ~isempty(retry_step)
                        curr_step = retry_step;
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        if isempty(target_lam) && ...
                                freeze_vsc_capability_after_limit()
                            relief_cleanup = profile_time_scope( ...
                                'vsc_capability_backoff_relief_logic'); %#ok<NASGU>
                            [freeze_changed, freeze_idx, freeze_cols, ...
                                backoff_lambda, relief_action, ...
                                margin_old, margin_new] = ...
                                resaturate_vsc_capability_at_limit();
                            if ~freeze_changed
                                [freeze_changed, freeze_idx, freeze_cols, ...
                                    backoff_lambda, relief_action, ...
                                margin_old, margin_new] = ...
                                    increase_vsc_capability_margin_at_limit();
                            end
                            margin_recovery_attempted = freeze_changed && ...
                                strcmp(relief_action, 'margin_increase');
                            if ~freeze_changed
                                [freeze_changed, freeze_idx, freeze_cols, ...
                                backoff_lambda, relief_action] = ...
                                    relieve_vsc_dc_slack_ac_support_at_limit();
                                margin_old = NaN;
                                margin_new = NaN;
                            end
                            if ~freeze_changed && vsc_capability_transfer_frozen
                                [freeze_changed, freeze_idx, freeze_cols, ...
                                    backoff_lambda] = ...
                                    backoff_vsc_hvdc_transfer_at_limit();
                                relief_action = 'transfer_backoff';
                                margin_old = NaN;
                                margin_new = NaN;
                            elseif ~freeze_changed
                                [freeze_changed, freeze_idx, freeze_cols] = ...
                                    freeze_vsc_capability_transfer_at_limit();
                                backoff_lambda = 0;
                                relief_action = 'transfer_freeze';
                                margin_old = NaN;
                                margin_new = NaN;
                            end
                            if freeze_changed
                                [ctx, ctxt, Sdelta, x, z, freeze_ok] = ...
                                    rebuild_unified_point_after_freeze( ...
                                    x, lam, direction);
                            else
                                freeze_ok = 0;
                            end
                            while freeze_changed && ~freeze_ok && ...
                                    strcmp(relief_action, 'margin_increase')
                                [freeze_changed, freeze_idx, freeze_cols, ...
                                    backoff_lambda, relief_action, ...
                                    margin_old, margin_new] = ...
                                    increase_vsc_capability_margin_at_limit();
                                if freeze_changed
                                    [ctx, ctxt, Sdelta, x, z, freeze_ok] = ...
                                        rebuild_unified_point_after_freeze( ...
                                        x, lam, direction);
                                end
                            end
                            if ~(freeze_changed && freeze_ok) && ...
                                    margin_recovery_attempted
                                [freeze_changed, freeze_idx, freeze_cols, ...
                                    backoff_lambda, relief_action] = ...
                                    relieve_vsc_dc_slack_ac_support_at_limit();
                                margin_old = NaN;
                                margin_new = NaN;
                                if ~freeze_changed && vsc_capability_transfer_frozen
                                    [freeze_changed, freeze_idx, freeze_cols, ...
                                        backoff_lambda] = ...
                                        backoff_vsc_hvdc_transfer_at_limit();
                                    relief_action = 'transfer_backoff';
                                elseif ~freeze_changed
                                    [freeze_changed, freeze_idx, freeze_cols] = ...
                                        freeze_vsc_capability_transfer_at_limit();
                                    backoff_lambda = 0;
                                    relief_action = 'transfer_freeze';
                                end
                                if freeze_changed
                                    [ctx, ctxt, Sdelta, x, z, freeze_ok] = ...
                                        rebuild_unified_point_after_freeze( ...
                                        x, lam, direction);
                                end
                            end
                            clear relief_cleanup;
                            if freeze_changed && freeze_ok
                                failure = [];
                                if any(strcmp(relief_action, ...
                                        {'transfer_freeze', 'transfer_backoff'}))
                                    vsc_capability_transfer_frozen = 1;
                                end
                                curr_step = freeze_recovery_step();
                                recovery_event_cleanup = profile_time_scope( ...
                                    'vsc_capability_recovery_event'); %#ok<NASGU>
                                if strcmp(relief_action, 'margin_increase')
                                    event_name = 'VSC_CAPABILITY_MARGIN_INCREASE';
                                    done_msg = sprintf(['Reached VSC-MTDC ' ...
                                        'monolithic VSC capability loading ' ...
                                        'limit in %d continuation steps, ' ...
                                        'lambda = %.6g; increasing VSC ' ...
                                        'saturation margin from %.4g to ' ...
                                        '%.4g and continuing CPF.'], ...
                                        cont_steps, last_lam, margin_old, ...
                                        margin_new);
                                elseif strcmp(relief_action, 'ac_release')
                                    event_name = 'VSC_CAPABILITY_AC_RELEASE';
                                    done_msg = sprintf(['Reached VSC-MTDC ' ...
                                        'monolithic VSC capability loading ' ...
                                        'limit in %d continuation steps, ' ...
                                        'lambda = %.6g; releasing saturated ' ...
                                        'DC-slack VSC AC voltage control and ' ...
                                        'continuing CPF.'], ...
                                        cont_steps, last_lam);
                                elseif strcmp(relief_action, 'q_saturate')
                                    event_name = 'VSC_CAPABILITY_Q_SATURATION';
                                    done_msg = sprintf(['Reached VSC-MTDC ' ...
                                        'monolithic VSC capability loading ' ...
                                        'limit in %d continuation steps, ' ...
                                        'lambda = %.6g; saturating DC-slack ' ...
                                        'VSC Qac on its capability curve and ' ...
                                        'continuing CPF.'], ...
                                        cont_steps, last_lam);
                                elseif strcmp(relief_action, 'resaturate')
                                    event_name = 'VSC_CAPABILITY_RESATURATION';
                                    done_msg = sprintf(['Reached VSC-MTDC ' ...
                                        'monolithic VSC capability loading ' ...
                                        'limit in %d continuation steps, ' ...
                                        'lambda = %.6g; re-saturating VSC ' ...
                                        'setpoints with the configured ' ...
                                        'capability margin and continuing ' ...
                                        'CPF.'], cont_steps, last_lam);
                                elseif backoff_lambda > 0
                                    event_name = 'VSC_CAPABILITY_BACKOFF';
                                    done_msg = sprintf(['Reached VSC-MTDC ' ...
                                        'monolithic VSC capability loading ' ...
                                        'limit in %d continuation steps, ' ...
                                        'lambda = %.6g; reducing frozen ' ...
                                        'VSC/HVDC transfer by %.6g lambda ' ...
                                        'equivalent and continuing CPF.'], ...
                                        cont_steps, last_lam, backoff_lambda);
                                else
                                    event_name = 'VSC_CAPABILITY_FREEZE';
                                    done_msg = sprintf(['Reached VSC-MTDC ' ...
                                        'monolithic VSC capability loading ' ...
                                        'limit in %d continuation steps, ' ...
                                        'lambda = %.6g; freezing VSC CPF ' ...
                                        'setpoint transfer and continuing CPF.'], ...
                                        cont_steps, last_lam);
                                end
                                recovery_event = struct( ...
                                    'k', cont_steps, ...
                                    'name', event_name, ...
                                    'idx', 1, 'msg', done_msg, ...
                                     'lambda_freeze', last_lam, ...
                                     'backoff_lambda', backoff_lambda, ...
                                     'relief_action', relief_action, ...
                                     'margin_old', margin_old, ...
                                     'margin_new', margin_new, ...
                                     'frozen_vsc_idx', freeze_idx, ...
                                     'frozen_vsc_cols', freeze_cols);
                                if ~vsc_mtdc_cpf_is_duplicate_recovery_event(events, ...
                                        recovery_event)
                                    events = vsc_mtdc_cpf_append_event(events, ...
                                        recovery_event);
                                end
                                clear recovery_event_cleanup;
                                done_msg = '';
                                if mpopt.verbose > 1
                                    fprintf(['step %3d  : VSC capability ' ...
                                        'limit at lambda = %6.3f; ' ...
                                        'applying %s and retrying with ' ...
                                        '%.3g\n'], ...
                                        cont_steps + 1, lamnew, ...
                                        relief_action, curr_step);
                                end
                                continue;
                            end
                        end
                        if isempty(target_lam)
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic VSC capability loading limit ' ...
                                'in %d continuation steps, lambda = %.6g.'], ...
                                cont_steps, last_lam);
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'VSC_CAPABILITY_LIMIT', ...
                                'idx', 1, 'msg', done_msg, ...
                                'vsc_margin_final', ...
                                    vsc_capability_current_margin_fraction()));
                            success = 1;
                        else
                            done_msg = sprintf(['VSC-MTDC monolithic ' ...
                                'VSC capability re-correction did not ' ...
                                'converge at lambda %.6g.'], lamnew);
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
                                'k', cont_steps + 1, ...
                                'name', 'VSC_CAPABILITY_FAIL', ...
                                'idx', 1, 'msg', done_msg));
                            success = 0;
                        end
                        break;
                    end
                end
                events = vsc_mtdc_cpf_append_event(events, cap_events);

                [ctx, ctxt, Sdelta, xnew, evalnew, lamnew, normFnew, ...
                    corr_it, r, V, gen_cap_events, gen_cap_ok, ...
                    gen_cap_changed, retry_step, active_set_changed] = ...
                    run_active_set_stage('gen', 'generator capability', '', ...
                    ctx, ctxt, Sdelta, xnew, evalnew, lamnew, normFnew, ...
                    corr_it, r, base_bus_ids, base_branch_count, ...
                    base_gen_count, cont_steps + 1, trial_step, step_min, ...
                    active_set_changed);
                if ~gen_cap_ok
                    if ~isempty(retry_step)
                        curr_step = retry_step;
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        if isempty(target_lam) && ...
                                freeze_gen_capability_after_limit()
                            [freeze_changed, freeze_idx] = ...
                                freeze_gen_capability_dispatch_at_limit();
                            if freeze_changed
                                [ctx, ctxt, Sdelta, x, z, freeze_ok] = ...
                                    rebuild_unified_point_after_freeze( ...
                                    x, lam, direction);
                            else
                                freeze_ok = 0;
                            end
                            if freeze_changed && freeze_ok
                                failure = [];
                                gen_capability_dispatch_frozen = 1;
                                curr_step = freeze_recovery_step();
                                done_msg = sprintf(['Reached VSC-MTDC ' ...
                                    'monolithic generator capability ' ...
                                    'loading limit in %d continuation ' ...
                                    'steps, lambda = %.6g; freezing ' ...
                                    'generator CPF redispatch and ' ...
                                    'continuing CPF.'], cont_steps, ...
                                    last_lam);
                                events = vsc_mtdc_cpf_append_event(events, struct( ...
                                    'k', cont_steps, ...
                                    'name', 'GEN_CAPABILITY_FREEZE', ...
                                    'idx', 1, 'msg', done_msg, ...
                                    'lambda_freeze', last_lam, ...
                                    'frozen_gen_idx', freeze_idx));
                                done_msg = '';
                                if mpopt.verbose > 1
                                    fprintf(['step %3d  : generator ' ...
                                        'capability limit at lambda = ' ...
                                        '%6.3f; freezing generator ' ...
                                        'redispatch and retrying with ' ...
                                        '%.3g\n'], cont_steps + 1, ...
                                        lamnew, curr_step);
                                end
                                continue;
                            end
                        end
                        if isempty(target_lam)
                            done_msg = sprintf(['Reached VSC-MTDC ' ...
                                'monolithic generator capability loading ' ...
                                'limit in %d continuation steps, lambda = ' ...
                                '%.6g.'], cont_steps, last_lam);
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
                                'k', cont_steps, ...
                                'name', 'GEN_CAPABILITY_LIMIT', ...
                                'idx', 1, 'msg', done_msg));
                            success = 1;
                        else
                            done_msg = sprintf(['VSC-MTDC monolithic ' ...
                                'generator capability re-correction did ' ...
                                'not converge at lambda %.6g.'], lamnew);
                            events = vsc_mtdc_cpf_append_event(events, struct( ...
                                'k', cont_steps + 1, ...
                                'name', 'GEN_CAPABILITY_FAIL', ...
                                'idx', 1, 'msg', done_msg));
                            success = 0;
                        end
                        break;
                    end
                end
                events = vsc_mtdc_cpf_append_event(events, gen_cap_events);
                if gen_cap_changed
                    accepted_step = abs(lamnew - lam);
                    xhat = xnew;
                    lamhat = lamnew;
                    ctx_hat = ctx;
                    Sdelta_hat = Sdelta;
                end

                [ctx, ctxt, Sdelta, xnew, ~, lamnew, ~, ...
                    corr_it, r, V, hvdc_der_events, hvdc_der_ok, ...
                    ~, retry_step, active_set_changed] = ...
                    run_active_set_stage('hvdc', 'HVDC derating', '', ...
                    ctx, ctxt, Sdelta, xnew, evalnew, lamnew, normFnew, ...
                    corr_it, r, base_bus_ids, base_branch_count, ...
                    base_gen_count, cont_steps + 1, trial_step, step_min, ...
                    active_set_changed);
                if ~hvdc_der_ok
                    if ~isempty(retry_step)
                        curr_step = retry_step;
                        continue;
                    else
                        failure = struct('lambda', lamnew, ...
                            'step', trial_step);
                        done_msg = sprintf(['VSC-MTDC monolithic HVDC ' ...
                            'derating re-correction did not converge at ' ...
                            'lambda %.6g.'], lamnew);
                        events = vsc_mtdc_cpf_append_event(events, struct( ...
                            'k', cont_steps + 1, ...
                            'name', 'HVDC_DERATING_FAIL', ...
                            'idx', 1, 'msg', done_msg));
                        success = 0;
                        break;
                    end
                end
                events = vsc_mtdc_cpf_append_event(events, hvdc_der_events);

                if active_set_changed || length(z) ~= length(xnew) + 1 || ...
                        length(x) ~= length(xnew)
                    zseed = zeros(length(xnew) + 1, 1);
                    zseed(end) = direction;
                    znew = unified_cpf_tangent(ctx, xnew, lamnew, Sdelta, ...
                        zseed, xnew, lamnew, 1, direction);
                else
                    znew = unified_cpf_tangent(ctx, xnew, lamnew, Sdelta, z, ...
                        x, lam, trial_parameterization, direction);
                end
                nose_event = ~active_set_changed && isempty(target_lam) && ...
                    strcmpi(stop_at, 'NOSE') && ...
                    unified_nose_event(z, znew, nose_tol);
                if nose_event
                    [xnew, lamnew, ~, ~, znew, loc_it] = ...
                        locate_unified_nose(ctx, Sdelta, x, lam, z, ...
                        xnew, lamnew, znew, trial_parameterization, ...
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

                if nose_event && ~full_trace
                    lam = lamnew;
                    last_lam = lam;
                    last = r;
                    done_msg = sprintf('Reached VSC-MTDC monolithic nose point in %d continuation steps, lambda = %.6g.', ...
                        cont_steps, lam);
                    events = vsc_mtdc_cpf_append_event(events, struct('k', cont_steps, ...
                        'name', 'NOSE', 'idx', 1, 'msg', done_msg));
                    break;
                elseif target_lambda_step
                    lam = lamnew;
                    last_lam = lam;
                    last = r;
                    done_msg = sprintf(['Traced full VSC-MTDC monolithic ' ...
                        'continuation curve in %d continuation steps.'], ...
                        cont_steps);
                    events = vsc_mtdc_cpf_append_event(events, struct( ...
                        'k', cont_steps, 'name', 'TARGET_LAM', ...
                        'idx', 1, 'msg', done_msg, ...
                        'lambda_event', lam));
                    break;
                end

                x = xnew;
                lam = lamnew;
                last_lam = lam;
                last = r;
                refresh_incremental_policy_anchor(lam);
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
        profile_cleanup = profile_time_scope('build_context_pair'); %#ok<NASGU>
        key = unified_context_pair_signature(mpcb, mpct);
        if strcmp(unified_context_cache.key, key)
            profile_count('context_cache_hit');
            ctx = unified_context_cache.ctx;
            ctxt = unified_context_cache.ctxt;
            Sdelta = unified_context_cache.Sdelta;
            return;
        end
        profile_count('context_cache_miss');
        validate_unified_cpf_transfer(mpcb, mpct);
        ctx = runpf_vsc_mtdc_unified('__setup', mpcb, mpopt_pf);
        ctxt = runpf_vsc_mtdc_unified('__setup', mpct, mpopt_pf);
        validate_unified_contexts(ctx, ctxt);
        Sdelta = ctxt.Sbase - ctx.Sbase;
        ctx = attach_unified_cpf_transfer(ctx, mpcb, mpct, Sdelta);
        ctxt = attach_unified_cpf_transfer(ctxt, mpcb, mpct, Sdelta);
        unified_context_cache.key = key;
        unified_context_cache.ctx = ctx;
        unified_context_cache.ctxt = ctxt;
        unified_context_cache.Sdelta = Sdelta;
    end

    function stage = active_set_stage_snapshot(ctx, ctxt, Sdelta)
        stage = struct( ...
            'ctx', ctx, ...
            'ctxt', ctxt, ...
            'Sdelta', Sdelta, ...
            'mpcb', mpcb, ...
            'mpct', mpct, ...
            'cpf_policy_state', cpf_policy_state, ...
            'vsc_capability_recorded_idx', vsc_capability_recorded_idx, ...
            'gen_capability_recorded_idx', gen_capability_recorded_idx);
    end

    function [ctx, ctxt, Sdelta] = restore_active_set_stage_snapshot(stage)
        ctx = stage.ctx;
        ctxt = stage.ctxt;
        Sdelta = stage.Sdelta;
        mpcb = stage.mpcb;
        mpct = stage.mpct;
        cpf_policy_state = stage.cpf_policy_state;
        vsc_capability_recorded_idx = stage.vsc_capability_recorded_idx;
        gen_capability_recorded_idx = stage.gen_capability_recorded_idx;
    end

    function [ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, r, V, ...
            ev, success, changed_any, retry_step, active_changed] = ...
            run_active_set_stage(kind, label, failure_profile_count, ...
            ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, r, ...
            bus_ids, nbranch, ngen, event_k, trial_step, step_min, ...
            active_changed)
        stage0 = active_set_stage_snapshot(ctx, ctxt, Sdelta);
        switch lower(kind)
            case 'psse'
                [ctx, ctxt, Sdelta, x, ~, ~, iterations, r, V, ...
                    ev, success, changed_any] = settle_unified_psse_controls( ...
                    ctx, ctxt, Sdelta, x, eval, lam, iterations, normF, r, ...
                    bus_ids, nbranch, ngen, event_k);
            case 'vsc'
                [ctx, ctxt, Sdelta, x, ~, ~, iterations, r, V, ...
                    ev, success, changed_any] = ...
                    settle_unified_vsc_capability_controls(ctx, ctxt, ...
                    Sdelta, x, eval, lam, iterations, normF, r, bus_ids, ...
                    nbranch, ngen, event_k);
            case 'gen'
                [ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, ...
                    r, V, ev, success, changed_any] = ...
                    settle_unified_gen_capability_controls(ctx, ctxt, ...
                    Sdelta, x, eval, lam, iterations, normF, r, bus_ids, ...
                    nbranch, ngen, event_k);
            case 'hvdc'
                [ctx, ctxt, Sdelta, x, ~, ~, iterations, r, V, ...
                    ev, success, changed_any] = ...
                    settle_unified_hvdc_derating_controls(ctx, ctxt, ...
                    Sdelta, x, eval, lam, iterations, normF, r, bus_ids, ...
                    nbranch, ngen, event_k);
            otherwise
                error('runcpf_vsc_mtdc: unknown active-set stage ''%s''', kind);
        end

        retry_step = [];
        active_changed = active_changed || changed_any;
        if ~success
            if ~isempty(failure_profile_count)
                profile_count(failure_profile_count);
            end
            [ctx, ctxt, Sdelta] = restore_active_set_stage_snapshot(stage0);
            if trial_step / 2 >= step_min
                retry_step = trial_step / 2;
                if mpopt.verbose > 1
                    fprintf(['step %3d  : stepsize = %-9.3g ' ...
                        'lambda = %6.3f %s re-correction did not ' ...
                        'converge, retrying with %.3g\n'], ...
                        event_k, trial_step, lam, label, retry_step);
                end
            end
        end
    end

    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...
            ev, success, changed_any] = settle_unified_psse_controls( ...
            ctx, ctxt, Sdelta, x, eval, lam, iterations, normF, r, ...
            bus_ids, nbranch, ngen, event_k)
        profile_cleanup = profile_time_scope('settle_psse_controls'); %#ok<NASGU>
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
            profile_count('psse_settle_iteration');
            [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
                unified_psse_control_update(r, lam);
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            if ~changed
                profile_count('psse_settle_no_change');
                if psse_report_has_unsatisfied_controls(report)
                    [locked, lock_msg] = ...
                        apply_selective_psse_control_lockout(report, lam);
                    if locked
                        profile_count('psse_settle_selective_freeze');
                        ev = vsc_mtdc_cpf_append_event(ev, struct( ...
                            'k', event_k, 'name', ...
                            'PSSE_CONTROL_SELECTIVE_FREEZE', ...
                            'idx', ctrl_it, 'msg', lock_msg));
                        continue;
                    end
                    success = 0;
                end
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            changed_any = 1;
            profile_count('psse_settle_changed');
            sig = psse_active_set_signature(mpcb_next);
            if any(strcmp(visited(1:nvisited), sig))
                profile_count('psse_settle_cycle_check');
                current = vsc_cpf_current_mpc(mpcb, mpct, lam);
                cycle_direct_cleanup = profile_time_scope( ...
                    'psse_cycle_direct_update'); %#ok<NASGU>
                [direct, direct_report] = ...
                    mp.psse_unified_control_update(current, r.bus);
                clear cycle_direct_cleanup;
                if direct_report.supported && ~direct_report.changed && ...
                        psse_control_violations(direct) == 0
                    mpcb = copy_psse_control_fields(mpcb, direct);
                    mpct = copy_psse_control_fields(mpct, direct);
                    V = original_ac_voltage_for_result(r, bus_ids);
                    return;
                end
                profile_count('psse_settle_cycle_auxiliary');
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
            refresh_incremental_policy_anchor(lam);
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
            ev = vsc_mtdc_cpf_append_event(ev, struct('k', event_k, ...
                'name', 'PSSE_CONTROL', 'idx', ctrl_it, 'msg', msg));
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            profile_count('psse_settle_recorr_success');
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
        profile_cleanup = profile_time_scope('settle_vsc_capability'); %#ok<NASGU>
        ev = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
        success = 1;
        changed_any = 0;
        if ~unified_vsc_capability_enabled()
            profile_count('vsc_capability_disabled');
            V = original_ac_voltage_for_result(r, bus_ids);
            return;
        end
        max_it = unified_vsc_capability_max_it();
        visited = cell(max_it + 1, 1);
        visited{1} = vsc_capability_active_set_signature(mpcb);
        nvisited = 1;
        for ctrl_it = 1:max_it
            profile_count('vsc_capability_settle_iteration');
            [changed, mpcb_next, mpct_next, report] = ...
                unified_vsc_capability_update(r, lam);
            if ~changed
                profile_count('vsc_capability_settle_no_change');
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            changed_any = 1;
            profile_count('vsc_capability_settle_changed');
            sig = vsc_capability_active_set_signature(mpcb_next);
            if any(strcmp(visited(1:nvisited), sig))
                profile_count('vsc_capability_settle_cycle');
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end
            nvisited = nvisited + 1;
            visited{nvisited} = sig;

            mpcb = mpcb_next;
            mpct = mpct_next;
            context_cleanup = profile_time_scope( ...
                'vsc_capability_context_rebuild'); %#ok<NASGU>
            refresh_incremental_policy_anchor(lam);
            [ctx, ctxt, Sdelta] = build_unified_context_pair();
            clear context_cleanup;
            recorr_cleanup = profile_time_scope( ...
                'vsc_capability_fixed_lambda_recorrection'); %#ok<NASGU>
            x0 = unified_x_from_controlled_ac(ctx, r.ac, r);
            [x, eval, normF, it, ok] = ...
                solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);
            clear recorr_cleanup;
            iterations = iterations + it;
            event_cleanup = profile_time_scope( ...
                'vsc_capability_event_construction'); %#ok<NASGU>
            msg = sprintf(['VSC capability active-set update at ' ...
                'lambda = %.8g; saturated converters %s; ' ...
                're-corrected unified VSC-MTDC point at fixed lambda.'], ...
                lam, mat2str(report.changed_idx(:)'));
            record_event = any(~ismember(report.changed_idx(:), ...
                vsc_capability_recorded_idx(:)));
            if record_event
                ev = vsc_mtdc_cpf_append_event(ev, vsc_capability_event_record( ...
                    event_k, ctrl_it, msg, report));
                vsc_capability_recorded_idx = unique( ...
                    [vsc_capability_recorded_idx(:); report.changed_idx(:)]);
                profile_count('vsc_capability_event_appended');
            end
            clear event_cleanup;
            if ~ok
                profile_count('vsc_capability_recorr_failed_inner');
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            profile_count('vsc_capability_recorr_success');
            r = build_unified_cpf_result(ctx, x, eval, lam, it, normF);
            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);
            complete_event_cleanup = profile_time_scope( ...
                'vsc_capability_event_completion'); %#ok<NASGU>
            if record_event
                ev(end) = complete_vsc_capability_event(ev(end), report, r);
            elseif ~isempty(ev) && ...
                    any(ismember(report.changed_idx(:), ...
                    vsc_capability_recorded_idx(:)))
                last_vsc_event = find(strcmp({ev.name}, 'VSC_CAPABILITY'), ...
                    1, 'last');
                if ~isempty(last_vsc_event)
                    ev(last_vsc_event) = complete_vsc_capability_event( ...
                        ev(last_vsc_event), report, r);
                end
            end
            clear complete_event_cleanup;
        end
        V = original_ac_voltage_for_result(r, bus_ids);
        success = 0;
    end

    function [changed, bnext, tnext, report] = ...
            unified_vsc_capability_update(r, lam)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_check_update'); %#ok<NASGU>
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
        profile_count_by('vsc_capability_active_rows_checked', ...
            length(active));
        tol = 1e-8;
        for kk = 1:length(active)
            k = active(kk);
            if size(r.vsc, 2) < c.QAC || size(r.vsc, 1) < k
                continue;
            end
            P0 = r.vsc(k, c.PAC);
            Q0 = r.vsc(k, c.QAC);
            V0 = vsc_capability_voltage(r.vsc, k);
            [params, policy] = cached_vsc_capability_params( ...
                current, k, kk);
            Smax = params.Smax;
            mode = policy.projection_mode;
            Vmax = params.Vmax;

            prefilter_cleanup = profile_time_scope( ...
                'vsc_capability_prefilter'); %#ok<NASGU>
            no_action = vsc_capability_definitely_no_action( ...
                P0, Q0, V0, current.vsc(k, :), params, tol);
            clear prefilter_cleanup;
            if no_action
                profile_count('vsc_capability_prefilter_skipped');
                continue;
            end

            try
                limit_cleanup = profile_time_scope( ...
                    'vsc_capability_limit_detection'); %#ok<NASGU>
                [sat, Psat, Qsat, ~, info] = vsc_capability_curve( ...
                    P0, Q0, Smax, V0, r.vsc(k, :), mode, Vmax, ...
                    mpcb.baseMVA);
                clear limit_cleanup;
            catch me
                clear limit_cleanup;
                error('runcpf_vsc_mtdc: VSC row %d capability evaluation failed: %s', ...
                    k, me.message);
            end
            if sat
                profile_count('vsc_capability_limit_saturated');
                [Psat, Qsat] = apply_vsc_capability_saturation_margin( ...
                    P0, Q0, Psat, Qsat, policy, k);
            else
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
            profile_count('vsc_capability_active_set_update');
            if incremental_cpf_policies_enabled()
                freeze_rows = incremental_hvdc_participant_rows();
                if ~isempty(freeze_rows)
                    cpf_policy_state.hvdc_frozen(freeze_rows) = 1;
                    vsc_capability_transfer_frozen = 1;
                end
            end
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

    function [params, policy] = cached_vsc_capability_params(mpc, k, kk)
        key = vsc_capability_param_cache_key(mpc, k, kk);
        for ii = 1:length(vsc_capability_param_cache)
            if strcmp(vsc_capability_param_cache(ii).key, key)
                profile_count('vsc_capability_param_cache_hit');
                params = vsc_capability_param_cache(ii).params;
                policy = vsc_capability_param_cache(ii).policy;
                return;
            end
        end
        profile_count('vsc_capability_param_cache_miss');
        params = vsc_capability_params(mpc, opt, k, kk);
        policy = vsc_capability_policy(mpc.vsc(k, :), ...
            struct('mode', params.mode), k, kk);
        vsc_capability_param_cache(end+1) = struct( ...
            'key', key, 'params', params, 'policy', policy);
    end

    function key = vsc_capability_param_cache_key(mpc, k, kk)
        cols = existing_cols([c.AC_MODE c.DC_MODE c.TR_R c.TR_X ...
            c.REACTOR_R c.REACTOR_X c.TR_RATE_A c.REACTOR_RATE_A], ...
            mpc.vsc, mpc.vsc);
        vals = mpc.vsc(k, cols);
        key = sprintf('%d:%d:%s:%s', k, kk, ...
            numeric_signature(mpc.baseMVA), numeric_signature(vals));
    end

    function TorF = vsc_capability_definitely_no_action( ...
            P, Q, V, vsc_row, params, tol)
        TorF = 0;
        [ok, pMax, iMax, qCenter, vRadius] = ...
            vsc_capability_fast_limits(vsc_row, params, V);
        if ~ok
            return;
        end
        scale = max(abs([1 pMax iMax qCenter finite_or_zero(vRadius)]));
        guard = max(tol, 1e-10 * scale);
        if ~vsc_capability_fast_inside(P, Q, pMax, iMax, ...
                qCenter, vRadius, guard)
            return;
        end
        TorF = 1;
    end

    function [ok, pMax, iMax, qCenter, vRadius] = ...
            vsc_capability_fast_limits(vsc_row, params, V)
        ok = 0;
        pMax = NaN;
        iMax = NaN;
        qCenter = NaN;
        vRadius = NaN;
        if size(vsc_row, 2) < c.REACTOR_RATE_A || ...
                isempty(V) || ~isfinite(V) || V <= 0 || ...
                isempty(params.Vmax) || ~isfinite(params.Vmax) || ...
                params.Vmax <= 0
            return;
        end
        Smax = params.Smax;
        if isempty(Smax)
            ratings = vsc_row([c.TR_RATE_A c.REACTOR_RATE_A]);
            ratings = ratings(isfinite(ratings) & ratings > 0);
            if isempty(ratings)
                return;
            end
            Smax = min(ratings);
        end
        if ~isscalar(Smax) || ~isfinite(Smax) || Smax <= 0
            return;
        end
        xEq_system = abs(vsc_row(c.TR_R) + vsc_row(c.REACTOR_R) + ...
            1j * (vsc_row(c.TR_X) + vsc_row(c.REACTOR_X)));
        pMax = Smax;
        iMax = V * Smax;
        xEq_element = xEq_system * Smax / mpcb.baseMVA;
        if isfinite(xEq_element) && xEq_element > 1e-10
            qCenter = V^2 * mpcb.baseMVA / xEq_system;
            vRadius = V * params.Vmax * mpcb.baseMVA / xEq_system;
        else
            qCenter = 0;
            vRadius = Inf;
        end
        ok = isfinite(pMax) && isfinite(iMax) && isfinite(qCenter) && ...
            (isfinite(vRadius) || isinf(vRadius));
    end

    function TorF = vsc_capability_fast_inside(P, Q, pMax, iMax, ...
            qCenter, vRadius, guard)
        TorF = abs(P) <= pMax - guard && hypot(P, Q) <= iMax - guard;
        if TorF && isfinite(vRadius)
            TorF = hypot(P, Q + qCenter) <= vRadius - guard;
        end
    end

    function val = finite_or_zero(val)
        if ~isfinite(val)
            val = 0;
        end
    end

    function ev = vsc_capability_event_record(event_k, event_idx, msg, report)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_event_record'); %#ok<NASGU>
        ev = vsc_mtdc_cpf_vsc_capability_event('record', ...
            event_k, event_idx, msg, report);
    end

    function ev = complete_vsc_capability_event(ev, report, r)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_event_complete_fields'); %#ok<NASGU>
        ev = vsc_mtdc_cpf_vsc_capability_event('complete', ...
            ev, report, r.vsc, mpcb.baseMVA);
    end

    function [margin, lam_prev, err] = previous_vsc_capability_margin( ...
            k, ~, Smax, mode, Vmax)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_previous_margin'); %#ok<NASGU>
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
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_event_location'); %#ok<NASGU>
        [lam_event, margin_event, method] = ...
            vsc_mtdc_cpf_vsc_capability_event('lambda', ...
            lam_prev, lam_candidate, margin_prev, margin_candidate);
    end

    function mode = saturated_vsc_ac_mode(policy, P0, Psat, tol)
        if abs(Psat - P0) > tol
            mode = policy.target_ac_mode_if_p_changed;
        else
            mode = policy.target_ac_mode_if_p_preserved;
        end
    end

    function [Psat, Qsat] = apply_vsc_capability_saturation_margin( ...
            P0, ~, Psat, Qsat, policy, k)
        margin = vsc_capability_saturation_margin_fraction(k);
        if margin <= 0
            return;
        end
        margin = min(max(margin, 0), 1);
        if strcmp(policy.projection_mode, 'preservar_p') && ...
                abs(Psat - P0) <= 1e-8
            Qsat = move_toward_origin(Qsat, margin);
        else
            Psat = move_toward_origin(Psat, margin);
            Qsat = move_toward_origin(Qsat, margin);
        end
        if abs(Psat) < 1e-10
            Psat = 0;
        end
        if abs(Qsat) < 1e-10
            Qsat = 0;
        end
    end

    function [needs_sat, Qsat] = vsc_q_margin_saturation_setpoint( ...
            P0, Q0, info, policy, tol, k)
        profile_cleanup = profile_time_scope( ...
            'vsc_slack_q_margin_setpoint'); %#ok<NASGU>
        Qsat = Q0;
        margin = vsc_capability_saturation_margin_fraction(k);
        if margin <= 0 || ~strcmp(policy.projection_mode, 'preservar_p')
            needs_sat = info.margin <= tol;
            return;
        end

        if Q0 >= 0
            Qlim = info.qMax;
        else
            Qlim = info.qMin;
        end
        if ~isfinite(Qlim)
            needs_sat = info.margin <= tol;
            return;
        end

        [~, Qsat] = apply_vsc_capability_saturation_margin( ...
            P0, Q0, P0, Qlim, policy, k);
        if Q0 >= 0
            needs_sat = info.margin <= tol || Q0 >= Qsat - tol;
        else
            needs_sat = info.margin <= tol || Q0 <= Qsat + tol;
        end
    end

    function TorF = fixed_vsc_capability_margin_policy()
        TorF = incremental_cpf_policies_enabled() && ...
            isfield(cpf_policy_state, 'vsc_capability_margin') && ...
            isfield(cpf_policy_state.vsc_capability_margin, ...
            'current_fraction') && ...
            any(cpf_policy_state.vsc_capability_margin.current_fraction(:) > 0) && ...
            (~isfield(cpf_policy_state.vsc_capability_margin, 'enabled') || ...
             ~cpf_policy_state.vsc_capability_margin.enabled);
    end

    function val = move_toward_origin(val, fraction)
        val = (1 - fraction) * val;
    end

    function margin = vsc_capability_saturation_margin_fraction(k)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_margin_fraction'); %#ok<NASGU>
        margin = 1e-3;
        if ~incremental_cpf_policies_enabled()
            return;
        end
        if isfield(cpf_policy_state, 'vsc_capability_margin') && ...
                isfield(cpf_policy_state.vsc_capability_margin, ...
                'current_fraction')
            margin = cpf_policy_state.vsc_capability_margin.current_fraction;
            margin = margin_for_vsc_row(margin, k);
            return;
        end
        p = vsc_mtdc_cpf_policy_state('policy_struct', ...
            cpf_policy_state.policies, ...
            {'vsc_capability', 'capability', 'vsc_saturation'});
        if isempty(p)
            return;
        end
        margin = vsc_mtdc_cpf_policy_state('policy_numeric', p, ...
            {'saturation_margin_fraction', 'margin_fraction', ...
             'inward_margin_fraction'}, 0);
        margin = margin_for_vsc_row(margin, k);
        validate_vsc_capability_margin_fraction(margin, ...
            'saturation margin fraction');
    end

    function margin = margin_for_vsc_row(margin, k)
        if isempty(margin) || isscalar(margin)
            return;
        end
        margin = margin(:);
        if k < 1 || k > length(margin)
            error('runcpf_vsc_mtdc: VSC saturation margin vector has invalid length');
        end
        margin = margin(k);
    end

    function validate_vsc_capability_margin_fraction(margin, label)
        if margin < 0 || margin > 1
            error('runcpf_vsc_mtdc: VSC %s must be in [0, 1]', ...
                label);
        end
    end

    function V = vsc_capability_voltage(vsc, row)
        if size(vsc, 2) >= c.VAC_PCC && ...
                isfinite(vsc(row, c.VAC_PCC)) && vsc(row, c.VAC_PCC) > 0
            V = vsc(row, c.VAC_PCC);
        elseif size(vsc, 2) >= c.VAC_INTERNAL && ...
                isfinite(vsc(row, c.VAC_INTERNAL)) && ...
                vsc(row, c.VAC_INTERNAL) > 0
            V = vsc(row, c.VAC_INTERNAL);
        else
            V = vsc(row, c.VAC_SET);
        end
    end

    function sig = vsc_capability_active_set_signature(mpc)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_active_set_signature'); %#ok<NASGU>
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

    function [ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, r, V, ...
            ev, success, changed_any] = ...
            settle_unified_gen_capability_controls(ctx, ctxt, Sdelta, x, ...
            eval, lam, iterations, normF, r, bus_ids, nbranch, ngen, event_k)
        profile_cleanup = profile_time_scope('settle_gen_capability'); %#ok<NASGU>
        ev = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
        success = 1;
        changed_any = 0;
        if ~unified_gen_capability_enabled()
            V = original_ac_voltage_for_result(r, bus_ids);
            return;
        end
        if gen_capability_dispatch_frozen
            [changed, ~, ~] = unified_gen_capability_update(r, lam);
            if changed
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
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

            [localized, loc_info] = ...
                locate_unified_gen_capability_event(r, report);
            if localized
                report = apply_gen_capability_location_info(report, loc_info);
            end

            mpcb = mpcb_next;
            mpct = mpct_next;
            refresh_incremental_policy_anchor(lam);
            [ctx, ctxt, Sdelta] = build_unified_context_pair();
            x0 = unified_x_from_controlled_ac(ctx, r.ac, r);
            [x, eval, normF, it, ok] = ...
                solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);
            iterations = iterations + it;
            if ~ok && localized
                [ctx, ctxt, Sdelta, x, eval, normF, it_retry, ok, ...
                    lam, report] = retry_gen_capability_localized_solve( ...
                    x0, r, lam, report);
                iterations = iterations + it_retry;
            end
            msg = sprintf(['Generator capability active-set update at ' ...
                'lambda = %.8g; saturated generators %s; ' ...
                're-corrected unified VSC-MTDC point at fixed lambda.'], ...
                lam, mat2str(report.changed_idx(:)'));
            record_event = any(~ismember(report.changed_idx(:), ...
                gen_capability_recorded_idx(:)));
            if record_event
                ev = vsc_mtdc_cpf_append_event(ev, gen_capability_event_record( ...
                    event_k, ctrl_it, msg, report));
                gen_capability_recorded_idx = unique( ...
                    [gen_capability_recorded_idx(:); report.changed_idx(:)]);
            end
            if ~ok
                V = original_ac_voltage_for_result(r, bus_ids);
                success = 0;
                return;
            end
            r = build_unified_cpf_result(ctx, x, eval, lam, it, normF);
            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);
            if record_event
                ev(end) = complete_gen_capability_event(ev(end), report, r);
            elseif ~isempty(ev) && ...
                    any(ismember(report.changed_idx(:), ...
                    gen_capability_recorded_idx(:)))
                last_gen_event = find(strcmp({ev.name}, 'GEN_CAPABILITY'), ...
                    1, 'last');
                if ~isempty(last_gen_event)
                    ev(last_gen_event) = complete_gen_capability_event( ...
                        ev(last_gen_event), report, r);
                end
            end
        end
        V = original_ac_voltage_for_result(r, bus_ids);
        success = 0;
    end

    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...
            ev, success, changed_any] = ...
            settle_unified_hvdc_derating_controls(ctx, ctxt, Sdelta, x, ...
            eval, lam, iterations, normF, r, bus_ids, nbranch, ngen, event_k)
        ev = struct('k', {}, 'name', {}, 'idx', {}, 'msg', {});
        success = 1;
        changed_any = 0;
        if ~unified_hvdc_derating_enabled()
            V = original_ac_voltage_for_result(r, bus_ids);
            return;
        end

        max_it = unified_hvdc_derating_max_it();
        visited = cell(max_it + 1, 1);
        visited{1} = hvdc_derating_active_set_signature(mpcb);
        nvisited = 1;
        for ctrl_it = 1:max_it
            trial_factor = 1;
            trial_ok = 0;
            while trial_factor >= 1 / 64
                stage0 = active_set_stage_snapshot(ctx, ctxt, Sdelta);
                [changed, mpcb_next, mpct_next, report] = ...
                    unified_hvdc_derating_update(r, lam, trial_factor);
                if ~changed
                    V = original_ac_voltage_for_result(r, bus_ids);
                    return;
                end

                sig = hvdc_derating_active_set_signature(mpcb_next);
                if any(strcmp(visited(1:nvisited), sig))
                    cpf_policy_state.hvdc.derating.enabled = 0;
                    msg = sprintf(['HVDC dynamic derating skipped at ' ...
                        'lambda = %.8g; Pac/Qac backoff repeated an ' ...
                        'active-set signature, so the derating policy was ' ...
                        'disabled and CPF continues.'], lam);
                    ev = vsc_mtdc_cpf_append_event(ev, ...
                        vsc_mtdc_cpf_hvdc_derating('skipped_record', ...
                            event_k, ctrl_it, msg, lam, ...
                            report.max_utilization, report.limiting_vsc, ...
                            report.backoff_lambda));
                    V = original_ac_voltage_for_result(r, bus_ids);
                    return;
                end

                mpcb = mpcb_next;
                mpct = mpct_next;
                refresh_incremental_policy_anchor(lam);
                [ctx, ctxt, Sdelta] = build_unified_context_pair();
                x0 = unified_x_from_controlled_ac(ctx, r.ac, r);
                [x_trial, eval_trial, normF_trial, it, ok] = ...
                    solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);
                iterations = iterations + it;
                if ok
                    x = x_trial;
                    eval = eval_trial;
                    normF = normF_trial;
                    trial_ok = 1;
                    break;
                end

                [ctx, ctxt, Sdelta] = ...
                    restore_active_set_stage_snapshot(stage0);
                trial_factor = trial_factor / 2;
            end
            if ~trial_ok
                cpf_policy_state.hvdc.derating.enabled = 0;
                msg = sprintf(['HVDC dynamic derating skipped at lambda = ' ...
                    '%.8g; no fractional Pac/Qac backoff converged, so ' ...
                    'the derating policy was disabled and CPF continues ' ...
                    'from the last converged point.'], lam);
                ev = vsc_mtdc_cpf_append_event(ev, ...
                    vsc_mtdc_cpf_hvdc_derating('skipped_record', ...
                        event_k, ctrl_it, msg, lam, ...
                        report.max_utilization, report.limiting_vsc, ...
                        report.backoff_lambda));
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            if ~changed
                V = original_ac_voltage_for_result(r, bus_ids);
                return;
            end

            changed_any = 1;
            nvisited = nvisited + 1;
            visited{nvisited} = sig;
            msg = sprintf(['HVDC dynamic derating at lambda = %.8g; ' ...
                'limiting VSC %d utilization %.4f; reduced Pac/Qac ' ...
                'toward the base transfer by %.4g lambda-equivalent.'], ...
                lam, report.limiting_vsc, report.max_utilization, ...
                report.backoff_lambda);
            ev = vsc_mtdc_cpf_append_event(ev, ...
                vsc_mtdc_cpf_hvdc_derating('record', ...
                    event_k, ctrl_it, msg, report));
            r = build_unified_cpf_result(ctx, x, eval, lam, 0, normF);
            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);
            ev(end) = vsc_mtdc_cpf_hvdc_derating('complete', ...
                ev(end), report, r, ...
                vsc_cpf_current_mpc(mpcb, mpct, report.lambda_event), ...
                cpf_policy_state.hvdc.derating, opt, mpcb.baseMVA);
        end
        cpf_policy_state.hvdc.derating.enabled = 0;
        ev = vsc_mtdc_cpf_append_event(ev, ...
            vsc_mtdc_cpf_hvdc_derating('skipped_record', event_k, ...
                max_it, sprintf(['HVDC dynamic derating skipped at ' ...
                'lambda = %.8g; maximum derating iterations were ' ...
                'reached, so the derating policy was disabled and CPF ' ...
                'continues.'], lam), lam, NaN, NaN, 0));
        V = original_ac_voltage_for_result(r, bus_ids);
    end

    function [changed, bnext, tnext, report] = ...
            unified_hvdc_derating_update(r, lam, trial_factor)
        if nargin < 3 || isempty(trial_factor)
            trial_factor = 1;
        end
        changed = 0;
        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        bnext = mpcb;
        tnext = mpct;
        h = cpf_policy_state.hvdc;
        d = h.derating;
        report = vsc_mtdc_cpf_hvdc_derating('empty_report', d);

        if ~isfield(current, 'vsc') || isempty(current.vsc) || ...
                ~isfield(r, 'vsc') || isempty(r.vsc)
            return;
        end

        util_report = vsc_mtdc_cpf_hvdc_derating( ...
            'utilization_report', r, current, d, opt, mpcb.baseMVA);
        report = vsc_mtdc_cpf_hvdc_derating( ...
            'copy_utilization_report', report, util_report);
        if isempty(util_report.idx) || ...
                util_report.max_utilization <= d.start_utilization
            return;
        end

        report.backoff_lambda = vsc_mtdc_cpf_hvdc_derating( ...
            'backoff_lambda', util_report.max_utilization, d) * ...
            trial_factor;
        if report.backoff_lambda <= 0
            return;
        end

        rows = incremental_hvdc_participant_rows();
        rows = rows(:);
        if isempty(rows)
            return;
        end
        cols = [c.PAC_SET c.QAC_SET];
        base = cpf_policy_state.structural_base.vsc;
        old_vsc = current.vsc;
        next_vsc = current.vsc;

        transfer = abs(h.transfer_mw_per_lambda) * report.backoff_lambda;
        next_vsc(h.source_idx, c.PAC_SET) = move_toward( ...
            next_vsc(h.source_idx, c.PAC_SET), ...
            base(h.source_idx, c.PAC_SET), transfer);
        next_vsc(h.sink_idx, c.PAC_SET) = move_toward( ...
            next_vsc(h.sink_idx, c.PAC_SET), ...
            base(h.sink_idx, c.PAC_SET), transfer);
        for kk = 1:length(h.qac_idx)
            row = h.qac_idx(kk);
            qstep = abs(h.qac_gain(row) * ...
                cpf_policy_state.total_pd_per_lam * ...
                report.backoff_lambda);
            next_vsc(row, c.QAC_SET) = move_toward( ...
                next_vsc(row, c.QAC_SET), ...
                base(row, c.QAC_SET), qstep);
        end

        next_vsc(rows, cols) = vsc_mtdc_cpf_hvdc_derating( ...
            'apply_floor', old_vsc(rows, cols), ...
            next_vsc(rows, cols), base(rows, cols), ...
            d.min_transfer_scale);
        delta = abs(next_vsc(rows, cols) - old_vsc(rows, cols));
        changed_rows = rows(any(delta > 1e-10, 2));
        if isempty(changed_rows)
            return;
        end

        bnext.vsc(rows, cols) = next_vsc(rows, cols);
        tnext.vsc(rows, cols) = next_vsc(rows, cols);
        changed = 1;
        report.changed_idx = changed_rows(:);
        report.old_pac_set = old_vsc(changed_rows, c.PAC_SET);
        report.new_pac_set = next_vsc(changed_rows, c.PAC_SET);
        report.old_qac_set = old_vsc(changed_rows, c.QAC_SET);
        report.new_qac_set = next_vsc(changed_rows, c.QAC_SET);
        report.lambda_event = lam;
    end

    function TorF = unified_hvdc_derating_enabled()
        TorF = incremental_cpf_policies_enabled() && ...
            cpf_policy_state.hvdc.enabled && ...
            isfield(cpf_policy_state.hvdc, 'derating') && ...
            cpf_policy_state.hvdc.derating.enabled;
    end

    function max_it = unified_hvdc_derating_max_it()
        max_it = cpf_policy_state.hvdc.derating.max_it;
    end

    function sig = hvdc_derating_active_set_signature(mpc)
        sig = vsc_mtdc_cpf_hvdc_derating( ...
            'active_set_signature', mpc);
    end

    function [changed, bnext, tnext, report] = ...
            unified_gen_capability_update(r, lam)
        changed = 0;
        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        bnext = mpcb;
        tnext = mpct;
        report = struct('changed_idx', [], 'bus', [], ...
            'active_limit', {{}}, 'P', [], 'Q', [], ...
            'margin_candidate', [], 'margin_previous', [], ...
            'lambda_previous', [], 'lambda_candidate', [], ...
            'lambda_event', [], 'margin_event', [], ...
            'event_location_method', {{}}, 'previous_margin_error', {{}}, ...
            'P_saturated', [], 'Q_saturated', [], 'S_saturated', [], ...
            'Smax', [], 'gen_type_code', [], 'gen_type', {{}}, ...
            'bisection_iterations', [], 'location_error', {{}});

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
            Smax = gen_capability_metadata_or_option_value(current, opt, ...
                {'Snom', 'Smax', 'smax'}, {'capability_gen_smax'}, ...
                g, g, gen_capability_default_smax(current, g), ...
                'runcpf_vsc_mtdc');
            type = gen_capability_metadata_or_option_value(current, opt, ...
                {'type', 'gen_type'}, {'capability_gen_type'}, ...
                g, g, 2, 'runcpf_vsc_mtdc');
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
            if incremental_cpf_policies_enabled() && ...
                    any(cpf_policy_state.gen.gen_idx == g)
                cpf_policy_state.gen_frozen(g) = 1;
            end
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
            report.margin_candidate(end+1, 1) = info.margin;
            [prev_margin, prev_lam, prev_err] = ...
                previous_gen_capability_margin(g, Smax, type);
            report.margin_previous(end+1, 1) = prev_margin;
            report.lambda_previous(end+1, 1) = prev_lam;
            report.previous_margin_error{end+1, 1} = prev_err;
            [lam_event, margin_event, method] = ...
                vsc_capability_event_lambda(prev_lam, lam, ...
                prev_margin, info.margin);
            report.lambda_candidate(end+1, 1) = lam;
            report.lambda_event(end+1, 1) = lam_event;
            report.margin_event(end+1, 1) = margin_event;
            report.event_location_method{end+1, 1} = method;
            report.P_saturated(end+1, 1) = Psat;
            report.Q_saturated(end+1, 1) = Qsat;
            report.S_saturated(end+1, 1) = abs(Psat + 1j * Qsat);
            report.Smax(end+1, 1) = info.Smax;
            report.gen_type_code(end+1, 1) = info.gen_type_code;
            report.gen_type{end+1, 1} = info.gen_type;
            report.bisection_iterations(end+1, 1) = 0;
            report.location_error{end+1, 1} = '';
        end
    end

    function [localized, loc] = locate_unified_gen_capability_event(r, report)
        localized = 0;
        loc = empty_gen_capability_location();
        if isempty(report.changed_idx)
            return;
        end

        margin_tol = gen_capability_location_margin_tol(report.Smax);
        candidate_tol = 1e-8;
        row = find(report.margin_previous >= -margin_tol & ...
            report.margin_candidate < -candidate_tol & ...
            isfinite(report.lambda_previous) & ...
            isfinite(report.lambda_candidate) & ...
            report.lambda_previous ~= report.lambda_candidate, 1);
        if isempty(row)
            return;
        end

        g = report.changed_idx(row);
        if size(r.gen, 1) < g
            return;
        end

        low_lam = report.lambda_previous(row);
        high_lam = report.lambda_candidate(row);
        high_margin = report.margin_candidate(row);
        if ~(exist('last', 'var') && isstruct(last) && ...
                isfield(last, 'gen') && size(last.gen, 1) >= g)
            return;
        end
        low_P = last.gen(g, PG);
        low_Q = last.gen(g, QG);
        high_P = report.P(row);
        high_Q = report.Q(row);
        target_margin = 0.75 * high_margin;
        lam_tol = max(1e-6, max(step_min, ...
            1e-7 * max(abs([low_lam high_lam 1]))));
        max_loc_it = 12;
        best_err = '';
        loc_count = 0;

        for kk = 1:max_loc_it
            if abs(high_lam - low_lam) <= lam_tol
                break;
            end
            loc_count = kk;
            mid_lam = 0.5 * (low_lam + high_lam);
            alpha = (mid_lam - low_lam) / (high_lam - low_lam);
            Pmid = low_P + alpha * (high_P - low_P);
            Qmid = low_Q + alpha * (high_Q - low_Q);
            [~, margin_mid, err_mid] = gen_capability_margin_from_result( ...
                struct('gen', set_gen_probe_row(r.gen, g, Pmid, Qmid)), ...
                g, report.Smax(row), report.gen_type_code(row));
            if ~isempty(err_mid)
                best_err = err_mid;
                break;
            end
            if margin_mid < target_margin
                high_lam = mid_lam;
                high_P = Pmid;
                high_Q = Qmid;
                high_margin = margin_mid;
            else
                low_lam = mid_lam;
                low_P = Pmid;
                low_Q = Qmid;
            end
        end

        if high_margin < 0 && isfinite(high_lam) && ...
                abs(high_lam - report.lambda_candidate(row)) < ...
                abs(report.lambda_candidate(row) - report.lambda_previous(row))
            localized = 1;
            loc.gen_idx = g;
            loc.lambda_event = high_lam;
            loc.margin_event = high_margin;
            loc.method = 'bisection_margin';
            loc.iterations = loc_count;
            loc.error = best_err;
        end
    end

    function gen = set_gen_probe_row(gen, g, P, Q)
        gen(g, PG) = P;
        gen(g, QG) = Q;
    end

    function loc = empty_gen_capability_location()
        loc = struct('gen_idx', [], 'lambda_event', [], ...
            'margin_event', [], 'method', '', 'iterations', 0, ...
            'error', '');
    end

    function tol = gen_capability_location_margin_tol(Smax)
        tol = max(1e-8, 1e-2 * max(abs(Smax(:))));
    end

    function report = apply_gen_capability_location_info(report, loc)
        if isempty(loc.gen_idx) || isempty(report.changed_idx)
            return;
        end
        rows = find(report.changed_idx == loc.gen_idx);
        for ii = 1:length(rows)
            row = rows(ii);
            report.lambda_event(row, 1) = loc.lambda_event;
            report.margin_event(row, 1) = loc.margin_event;
            report.event_location_method{row, 1} = loc.method;
            report.bisection_iterations(row, 1) = loc.iterations;
            report.location_error{row, 1} = loc.error;
        end
    end

    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, ok, ...
            lam, report] = retry_gen_capability_localized_solve(x0, r, ...
            lam, report)
        iterations = 0;
        ok = 0;
        ctx = [];
        ctxt = [];
        Sdelta = [];
        x = x0;
        eval = [];
        normF = Inf;
        if isempty(report.lambda_candidate) || ...
                ~isfinite(report.lambda_candidate(1)) || ...
                report.lambda_candidate(1) == lam
            return;
        end
        low_lam = lam;
        high_lam = report.lambda_candidate(1);
        max_retry = 6;
        for kk = 1:max_retry
            lam_try = 0.5 * (low_lam + high_lam);
            refresh_incremental_policy_anchor(lam_try);
            [ctx_try, ctxt_try, Sdelta_try] = build_unified_context_pair();
            x0_try = unified_x_from_controlled_ac(ctx_try, r.ac, r);
            [x_try, eval_try, normF_try, it, ok_try] = ...
                solve_unified_pf_at_lambda(ctx_try, x0_try, lam_try, ...
                Sdelta_try);
            iterations = iterations + it;
            if ok_try
                ctx = ctx_try;
                ctxt = ctxt_try;
                Sdelta = Sdelta_try;
                x = x_try;
                eval = eval_try;
                normF = normF_try;
                lam = lam_try;
                ok = 1;
                report.lambda_event(:) = lam_try;
                report.margin_event(:) = NaN;
                report.event_location_method(:) = ...
                    repmat({'bisection_margin_retry'}, ...
                    size(report.event_location_method));
                report.location_error(:) = repmat({''}, ...
                    size(report.location_error));
                return;
            end
            low_lam = lam_try;
        end
        refresh_incremental_policy_anchor(high_lam);
        [ctx_try, ctxt_try, Sdelta_try] = build_unified_context_pair();
        x0_try = unified_x_from_controlled_ac(ctx_try, r.ac, r);
        [x_try, eval_try, normF_try, it, ok_try] = ...
            solve_unified_pf_at_lambda(ctx_try, x0_try, high_lam, ...
            Sdelta_try);
        iterations = iterations + it;
        if ok_try
            ctx = ctx_try;
            ctxt = ctxt_try;
            Sdelta = Sdelta_try;
            x = x_try;
            eval = eval_try;
            normF = normF_try;
            lam = high_lam;
            ok = 1;
            report.lambda_event(:) = high_lam;
            report.margin_event(:) = report.margin_candidate(:);
            report.event_location_method(:) = ...
                repmat({'bisection_margin_fallback'}, ...
                size(report.event_location_method));
            report.location_error(:) = repmat({''}, ...
                size(report.location_error));
        end
    end

    function [sat, margin, err, Psat, Qsat, Ssat, info] = ...
            gen_capability_margin_from_result(r, g, Smax, type)
        sat = 0;
        margin = NaN;
        err = '';
        Psat = NaN;
        Qsat = NaN;
        Ssat = NaN;
        info = struct();
        if size(r.gen, 1) < g
            err = 'result does not contain requested generator row';
            return;
        end
        try
            [sat, Psat, Qsat, Ssat, info] = gen_capability_curve( ...
                r.gen(g, PG), r.gen(g, QG), Smax, type);
            margin = info.margin;
        catch me
            err = me.message;
        end
    end

    function ev = gen_capability_event_record(event_k, event_idx, msg, report)
        ev = vsc_mtdc_cpf_gen_capability_event('record', ...
            event_k, event_idx, msg, report);
    end

    function ev = complete_gen_capability_event(ev, report, r)
        ev = vsc_mtdc_cpf_gen_capability_event('complete', ...
            ev, report, r.bus, r.gen);
    end

    function [margin, lam_prev, err] = previous_gen_capability_margin( ...
            g, Smax, type)
        margin = NaN;
        lam_prev = NaN;
        err = '';
        if ~(exist('last', 'var') && isstruct(last) && ...
                isfield(last, 'gen') && size(last.gen, 1) >= g && ...
                exist('last_lam', 'var') && isfinite(last_lam))
            return;
        end
        [~, margin, err] = gen_capability_margin_from_result(last, g, ...
            Smax, type);
        if isempty(err)
            lam_prev = last_lam;
        end
    end

    function TorF = is_slack_gen(mpc, g)
        row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
        TorF = ~isempty(row) && mpc.bus(row, BUS_TYPE) == REF;
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
        profile_cleanup = profile_time_scope('psse_active_set_signature'); %#ok<NASGU>
        sig = mp.psse_unified_active_set('signature', mpc);
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

    function s = freeze_recovery_step()
        s = min(max(step, step_min), step_max);
    end

    function TorF = freeze_vsc_capability_after_limit()
        TorF = strcmpi(capability_limit_mode('vsc'), 'freeze');
    end

    function margin = vsc_capability_current_margin_fraction()
        margin = NaN;
        if incremental_cpf_policies_enabled() && ...
                isfield(cpf_policy_state, 'vsc_capability_margin') && ...
                isfield(cpf_policy_state.vsc_capability_margin, ...
                'current_fraction')
            margin = cpf_policy_state.vsc_capability_margin.current_fraction;
        end
    end

    function TorF = freeze_gen_capability_after_limit()
        TorF = strcmpi(capability_limit_mode('gen'), 'freeze');
    end

    function mode = capability_limit_mode(kind)
        specific_name = ['capability_' lower(kind) '_limit'];
        mode = opt.capability_limit;
        if isfield(opt, specific_name) && ~isempty(opt.(specific_name))
            mode = opt.(specific_name);
        end
    end

    function validate_capability_limit_options()
        validate_capability_limit_option('capability_limit');
        validate_capability_limit_option('capability_vsc_limit');
        validate_capability_limit_option('capability_gen_limit');
    end

    function validate_capability_limit_option(name)
        if ~isfield(opt, name) || isempty(opt.(name))
            return;
        end
        val = opt.(name);
        if ~ischar(val) || ...
                ~(strcmpi(val, 'stop') || strcmpi(val, 'freeze'))
            error(['runcpf_vsc_mtdc: vsc_mtdc.%s must be ''stop'' ' ...
                'or ''freeze'''], name);
        end
    end

    function [changed, rows, cols, backoff_lam, action, margin_old, ...
            margin_new] = increase_vsc_capability_margin_at_limit()
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_margin_increase'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = [c.AC_MODE c.PAC_SET c.QAC_SET];
        backoff_lam = 0;
        action = '';
        margin_old = NaN;
        margin_new = NaN;
        if ~incremental_cpf_policies_enabled() || ...
                ~isfield(cpf_policy_state, 'vsc_capability_margin') || ...
                ~cpf_policy_state.vsc_capability_margin.enabled || ...
                ~isfield(last, 'vsc') || isempty(last.vsc)
            return;
        end

        margin_state = cpf_policy_state.vsc_capability_margin;
        margin_old = margin_state.current_fraction;
        if margin_old + 1e-12 >= margin_state.max_fraction
            return;
        end
        margin_new = min(margin_state.max_fraction, ...
            margin_old + margin_state.step_fraction);
        if margin_new <= margin_old + 1e-12
            return;
        end

        cpf_policy_state.vsc_capability_margin.current_fraction = ...
            margin_new;
        [changed, bnext, tnext, report] = ...
            unified_vsc_capability_update(last, last_lam);
        if ~changed
            rows = [];
            changed = 1;
            action = 'margin_increase';
            return;
        end

        mpcb = bnext;
        mpct = tnext;
        rows = report.changed_idx(:);
        refresh_incremental_policy_anchor(last_lam);
        action = 'margin_increase';
    end

    function [changed, rows, cols, backoff_lam, action, margin_old, ...
            margin_new] = resaturate_vsc_capability_at_limit()
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_resaturate'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = [c.AC_MODE c.PAC_SET c.QAC_SET];
        backoff_lam = 0;
        action = '';
        margin_old = NaN;
        margin_new = NaN;
        if ~fixed_vsc_capability_margin_policy() || ...
                ~isfield(mpcb, 'vsc') || isempty(mpcb.vsc) || ...
                ~isfield(last, 'vsc') || isempty(last.vsc)
            return;
        end
        max_resaturations = 1000;
        if vsc_capability_resaturation_count >= max_resaturations
            return;
        end

        current = vsc_cpf_current_mpc(mpcb, mpct, last_lam);
        candidate = vsc_capability_failed_candidate_result();
        if ~isfield(candidate, 'vsc') || isempty(candidate.vsc)
            return;
        end
        active = find(current.vsc(:, c.VSC_STATUS) > 0 & ...
            (current.vsc(:, c.AC_MODE) == c.VSC_AC_Q | ...
             current.vsc(:, c.AC_MODE) == c.VSC_AC_PQ));
        active = active(ismember(active, vsc_capability_recorded_idx(:)));
        if isempty(active)
            return;
        end

        tol = 1e-8;
        next_vsc = current.vsc;
        rows = zeros(length(active), 1);
        nrows = 0;
        for kk = 1:length(active)
            k = active(kk);
            if size(candidate.vsc, 1) < k || size(candidate.vsc, 2) < c.QAC
                continue;
            end
            P0 = candidate.vsc(k, c.PAC);
            Q0 = candidate.vsc(k, c.QAC);
            V0 = vsc_capability_voltage(candidate.vsc, k);
            params = vsc_capability_params(current, opt, k, k);
            policy = vsc_capability_policy(current.vsc(k, :), ...
                struct('mode', params.mode), k, k);
            [sat, Psat, Qsat, ~, info] = vsc_capability_curve( ...
                P0, Q0, params.Smax, V0, candidate.vsc(k, :), ...
                policy.projection_mode, params.Vmax, mpcb.baseMVA);
            if ~sat && info.margin > tol
                continue;
            end
            [Psat, Qsat] = apply_vsc_capability_saturation_margin( ...
                P0, Q0, Psat, Qsat, policy, k);
            to_mode = saturated_vsc_ac_mode(policy, P0, Psat, tol);
            new_vals = [to_mode Psat Qsat];
            if all(abs(current.vsc(k, cols) - new_vals) <= tol)
                continue;
            end
            next_vsc(k, cols) = new_vals;
            nrows = nrows + 1;
            rows(nrows) = k;
        end
        rows = rows(1:nrows);
        if isempty(rows)
            return;
        end

        mpcb.vsc(rows, cols) = next_vsc(rows, cols);
        mpct.vsc(rows, cols) = next_vsc(rows, cols);
        if incremental_cpf_policies_enabled()
            cpf_policy_state.anchor_mpc.vsc(rows, cols) = ...
                next_vsc(rows, cols);
            hvdc_rows = incremental_hvdc_participant_rows();
            freeze_rows = intersect(rows(:), hvdc_rows(:));
            if ~isempty(freeze_rows)
                cpf_policy_state.hvdc_frozen(freeze_rows) = 1;
                vsc_capability_transfer_frozen = 1;
            end
        end
        refresh_incremental_policy_anchor(last_lam);
        vsc_capability_resaturation_count = ...
            vsc_capability_resaturation_count + 1;
        changed = 1;
        action = 'resaturate';
    end

    function [changed, rows, cols, backoff_lam, action] = ...
            relieve_vsc_dc_slack_ac_support_at_limit()
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_slack_ac_support'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = [c.AC_MODE c.PAC_SET c.QAC_SET];
        backoff_lam = 0;
        action = '';
        if ~isfield(mpcb, 'vsc') || isempty(mpcb.vsc)
            return;
        end

        [changed, rows, cols] = release_vsc_dc_slack_ac_control_at_limit();
        if changed
            action = 'ac_release';
            return;
        end

        [changed, rows, cols, backoff_lam] = ...
            saturate_vsc_dc_slack_q_at_limit();
        if changed
            action = 'q_saturate';
        end
    end

    function [changed, rows, cols] = ...
            release_vsc_dc_slack_ac_control_at_limit()
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_ac_release'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = [c.AC_MODE c.PAC_SET c.QAC_SET];
        if ~isfield(last, 'vsc') || isempty(last.vsc)
            return;
        end
        current = vsc_cpf_current_mpc(mpcb, mpct, last_lam);
        active = find(current.vsc(:, c.VSC_STATUS) > 0 & ...
            current.vsc(:, c.DC_MODE) == c.VSC_DC_VDC & ...
            (current.vsc(:, c.AC_MODE) == c.VSC_AC_V | ...
             current.vsc(:, c.AC_MODE) == c.VSC_AC_PV));
        if isempty(active)
            return;
        end

        tol = 1e-8;
        rows = zeros(length(active), 1);
        nrows = 0;
        for kk = 1:length(active)
            k = active(kk);
            if size(last.vsc, 1) < k || size(last.vsc, 2) < c.QAC
                continue;
            end
            P0 = last.vsc(k, c.PAC);
            Q0 = last.vsc(k, c.QAC);
            V0 = vsc_capability_voltage(last.vsc, k);
            params = vsc_capability_params(current, opt, k, k);
            policy = vsc_capability_policy(current.vsc(k, :), ...
                struct('mode', params.mode), k, k);
            [~, Psat, Qsat, ~, info] = vsc_capability_curve( ...
                P0, Q0, params.Smax, V0, last.vsc(k, :), ...
                policy.projection_mode, params.Vmax, mpcb.baseMVA);
            if info.margin > tol
                continue;
            end
            [Psat, Qsat] = apply_vsc_capability_saturation_margin( ...
                P0, Q0, Psat, Qsat, policy, k);
            new_vals = [c.VSC_AC_Q Psat Qsat];
            old_vals = current.vsc(k, cols);
            if all(abs(old_vals - new_vals) <= tol)
                continue;
            end
            mpcb.vsc(k, cols) = new_vals;
            mpct.vsc(k, cols) = new_vals;
            if incremental_cpf_policies_enabled()
                cpf_policy_state.anchor_mpc.vsc(k, cols) = new_vals;
                if any(incremental_hvdc_participant_rows() == k)
                    cpf_policy_state.hvdc_frozen(k) = 1;
                end
            end
            nrows = nrows + 1;
            rows(nrows) = k;
            changed = 1;
        end
        rows = rows(1:nrows);
        if changed
            refresh_incremental_policy_anchor(last_lam);
        end
    end

    function [changed, rows, cols, backoff_lam] = ...
            saturate_vsc_dc_slack_q_at_limit()
        profile_cleanup = profile_time_scope('vsc_slack_q_relief'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = [c.AC_MODE c.QAC_SET];
        backoff_lam = 0;
        if ~incremental_cpf_policies_enabled() || ...
                ~isfield(cpf_policy_state, 'vsc_slack_q_relief') || ...
                ~cpf_policy_state.vsc_slack_q_relief.enabled || ...
                ~isfield(last, 'vsc') || isempty(last.vsc)
            return;
        end
        relief = cpf_policy_state.vsc_slack_q_relief;
        if vsc_slack_q_backoff_count >= relief.max_saturations
            return;
        end
        current = vsc_cpf_current_mpc(mpcb, mpct, last_lam);
        candidates = relief.vsc_idx(:);
        candidates = candidates(current.vsc(candidates, c.VSC_STATUS) > 0 & ...
            current.vsc(candidates, c.DC_MODE) == c.VSC_DC_VDC & ...
            current.vsc(candidates, c.AC_MODE) == c.VSC_AC_Q);
        if isempty(candidates)
            return;
        end

        tol = 1e-8;
        backoff_lam = min(max(step, step_min), step_max);
        candidate = vsc_capability_failed_candidate_result();

        next_vsc = cpf_policy_state.anchor_mpc.vsc;
        old_vsc = next_vsc;
        rows = zeros(length(candidates), 1);
        nrows = 0;
        for kk = 1:length(candidates)
            k = candidates(kk);
            if size(last.vsc, 1) < k || size(last.vsc, 2) < c.QAC
                continue;
            end
            P0 = candidate.vsc(k, c.PAC);
            Q0 = candidate.vsc(k, c.QAC);
            V0 = vsc_capability_voltage(candidate.vsc, k);
            params = vsc_capability_params(current, opt, k, k);
            policy = vsc_capability_policy(current.vsc(k, :), ...
                struct('mode', params.mode), k, k);
            [~, ~, ~, ~, info] = vsc_capability_curve( ...
                P0, Q0, params.Smax, V0, candidate.vsc(k, :), ...
                policy.projection_mode, params.Vmax, mpcb.baseMVA);
            [needs_sat, Qsat] = vsc_q_margin_saturation_setpoint( ...
                P0, Q0, info, policy, tol, k);
            if ~needs_sat
                continue;
            end
            next_vsc(k, c.AC_MODE) = c.VSC_AC_Q;
            next_vsc(k, c.QAC_SET) = Qsat;
            nrows = nrows + 1;
            rows(nrows) = k;
        end
        rows = rows(1:nrows);
        rows = unique(rows);
        if isempty(rows) || ...
                all(all(abs(next_vsc(rows, cols) - old_vsc(rows, cols)) <= tol))
            backoff_lam = 0;
            rows = [];
            return;
        end

        cpf_policy_state.anchor_mpc.vsc(rows, cols) = next_vsc(rows, cols);
        mpcb.vsc(rows, cols) = next_vsc(rows, cols);
        mpct.vsc(rows, cols) = next_vsc(rows, cols);
        refresh_incremental_policy_anchor(last_lam);
        vsc_slack_q_backoff_count = vsc_slack_q_backoff_count + 1;
        changed = 1;
    end

    function candidate = vsc_capability_failed_candidate_result()
        candidate = last;
        if exist('r', 'var') && isstruct(r) && isfield(r, 'vsc') && ...
                ~isempty(r.vsc) && size(r.vsc, 2) >= c.QAC
            candidate = r;
        end
    end

    function [changed, rows, cols] = freeze_vsc_capability_transfer_at_limit()
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_transfer_freeze'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = vsc_setpoint_transfer_cols();
        if ~isfield(mpcb, 'vsc') || isempty(mpcb.vsc)
            return;
        end
        if incremental_cpf_policies_enabled()
            rows = incremental_hvdc_participant_rows();
            if isempty(rows) || vsc_capability_transfer_frozen
                return;
            end
            cpf_policy_state.hvdc_frozen(rows) = 1;
            refresh_incremental_policy_anchor(last_lam);
            changed = 1;
            return;
        end
        current = vsc_cpf_current_mpc(mpcb, mpct, last_lam);
        tol = 1e-10;
        delta = abs(mpct_transfer0.vsc(:, cols) - ...
            mpcb_transfer0.vsc(:, cols)) > tol;
        active = mpcb.vsc(:, c.VSC_STATUS) > 0;
        rows = find(active & any(delta, 2));
        if isempty(rows)
            return;
        end
        if all(all(abs(mpcb.vsc(rows, cols) - current.vsc(rows, cols)) <= tol)) && ...
                all(all(abs(mpct.vsc(rows, cols) - current.vsc(rows, cols)) <= tol))
            return;
        end
        mpcb.vsc(rows, cols) = current.vsc(rows, cols);
        mpct.vsc(rows, cols) = current.vsc(rows, cols);
        changed = 1;
    end

    function [changed, rows, cols, backoff_lam] = ...
            backoff_vsc_hvdc_transfer_at_limit()
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_transfer_backoff'); %#ok<NASGU>
        changed = 0;
        rows = [];
        cols = [c.PAC_SET c.QAC_SET];
        backoff_lam = 0;
        if ~incremental_cpf_policies_enabled() || ...
                ~cpf_policy_state.hvdc.enabled
            return;
        end
        max_backoff = 80;
        if vsc_capability_transfer_backoff_count >= max_backoff
            return;
        end
        h = cpf_policy_state.hvdc;
        rows = incremental_hvdc_participant_rows();
        rows = rows(:);
        if isempty(rows)
            return;
        end
        backoff_lam = min(max(step, step_min), step_max);
        base = cpf_policy_state.structural_base.vsc;
        next_vsc = cpf_policy_state.anchor_mpc.vsc;
        old_vsc = next_vsc;
        transfer = h.transfer_mw_per_lambda * backoff_lam;

        next_vsc(h.source_idx, c.PAC_SET) = move_toward( ...
            next_vsc(h.source_idx, c.PAC_SET), ...
            base(h.source_idx, c.PAC_SET), transfer);
        next_vsc(h.sink_idx, c.PAC_SET) = move_toward( ...
            next_vsc(h.sink_idx, c.PAC_SET), ...
            base(h.sink_idx, c.PAC_SET), transfer);
        for kk = 1:length(h.qac_idx)
            row = h.qac_idx(kk);
            qstep = abs(h.qac_gain(row) * ...
                cpf_policy_state.total_pd_per_lam * backoff_lam);
            next_vsc(row, c.QAC_SET) = move_toward( ...
                next_vsc(row, c.QAC_SET), ...
                base(row, c.QAC_SET), qstep);
        end
        if all(all(abs(next_vsc(rows, cols) - old_vsc(rows, cols)) <= 1e-10))
            backoff_lam = 0;
            return;
        end

        cpf_policy_state.anchor_mpc.vsc(rows, cols) = next_vsc(rows, cols);
        mpcb.vsc(rows, cols) = next_vsc(rows, cols);
        mpct.vsc(rows, cols) = next_vsc(rows, cols);
        cpf_policy_state.hvdc_frozen(rows) = 1;
        vsc_capability_transfer_backoff_count = ...
            vsc_capability_transfer_backoff_count + 1;
        changed = 1;
    end

    function val = move_toward(val, target, amount)
        if amount <= 0 || abs(val - target) <= 1e-10
            return;
        end
        if val < target
            val = min(val + amount, target);
        else
            val = max(val - amount, target);
        end
    end

    function [changed, rows] = freeze_gen_capability_dispatch_at_limit()
        changed = 0;
        rows = [];
        if ~isfield(mpcb, 'gen') || isempty(mpcb.gen)
            return;
        end
        if incremental_cpf_policies_enabled()
            rows = incremental_gen_participant_rows();
            rows = rows(~cpf_policy_state.gen_frozen(rows));
            if isempty(rows)
                return;
            end
            cpf_policy_state.gen_frozen(rows) = 1;
            refresh_incremental_policy_anchor(last_lam);
            changed = 1;
            return;
        end
        current = vsc_cpf_current_mpc(mpcb, mpct, last_lam);
        tol = 1e-10;
        for g = 1:size(mpcb.gen, 1)
            if mpcb.gen(g, GEN_STATUS) <= 0 || isload(mpcb.gen(g, :)) || ...
                    is_slack_gen(mpcb, g)
                continue;
            end
            if abs(mpct_transfer0.gen(g, PG) - ...
                    mpcb_transfer0.gen(g, PG)) > tol
                rows(end+1, 1) = g; %#ok<AGROW>
            end
        end
        if isempty(rows)
            return;
        end
        if all(abs(mpcb.gen(rows, PG) - current.gen(rows, PG)) <= tol) && ...
                all(abs(mpct.gen(rows, PG) - current.gen(rows, PG)) <= tol)
            return;
        end
        mpcb.gen(rows, PG) = current.gen(rows, PG);
        mpct.gen(rows, PG) = current.gen(rows, PG);
        changed = 1;
    end

    function [ctx, ctxt, Sdelta, x1, z, ok] = ...
            rebuild_unified_point_after_freeze(x0, lam0, dir0)
        profile_cleanup = profile_time_scope( ...
            'vsc_capability_relief_context_rebuild'); %#ok<NASGU>
        [ctx, ctxt, Sdelta] = build_unified_context_pair();
        [x1, ~, ~, ~, ok] = solve_unified_pf_at_lambda( ...
            ctx, x0, lam0, Sdelta);
        if ~ok
            z = [];
            return;
        end
        zseed = zeros(length(x1) + 1, 1);
        zseed(end) = dir0;
        z = unified_cpf_tangent(ctx, x1, lam0, Sdelta, zseed, ...
            x1, lam0, 1, dir0);
    end

    function TorF = has_psse_control_data(mpc)
        TorF = mp.psse_unified_active_set('has_control_data', mpc, ...
            'raw');
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
        profile_cleanup = profile_time_scope('unified_psse_control_update'); %#ok<NASGU>
        ok = 1;
        mpcb_next = mpcb;
        mpct_next = mpct;

        current_cleanup = profile_time_scope('psse_current_mpc'); %#ok<NASGU>
        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        clear current_cleanup;
        direct_cleanup = profile_time_scope('psse_direct_update'); %#ok<NASGU>
        [direct, direct_report] = mp.psse_unified_control_update( ...
            current, r.bus);
        clear direct_cleanup;
        if direct_report.supported
            profile_count('psse_direct_supported');
            ac_controlled = psse_control_case_from_unified_result(r);
            ac_controlled = copy_original_active_set_to_ac( ...
                ac_controlled, direct);
            [changed, report] = psse_active_set_changed( ...
                current, ac_controlled);
            report = merge_psse_direct_report(report, direct_report);
            has_aux = has_auxiliary_psse_control_data(current, r.bus);
            needs_aux = direct_report_requires_auxiliary_pf(direct_report);
            if has_aux
                profile_count('psse_direct_blocked_by_aux_family');
            elseif needs_aux
                profile_count('psse_direct_blocked_by_requires_aux');
            end
            if changed || (~has_aux && ~needs_aux && ...
                    (~psse_report_has_unsatisfied_controls(report) || ...
                    direct_report_has_blocked_controls(direct_report)))
                if changed
                    [mpcb_next, mpct_next] = apply_psse_active_set_update( ...
                        current, ac_controlled);
                else
                    mpcb = copy_psse_control_fields(mpcb, ac_controlled);
                    mpct = copy_psse_control_fields(mpct, ac_controlled);
                    profile_count('psse_direct_only_fast_path');
                end
                profile_count('psse_direct_return');
                return;
            end
            if psse_report_has_unsatisfied_controls(report)
                profile_count('psse_direct_blocked_by_unsatisfied_controls');
                if isfield(direct_report, 'xfmr_control_violations') && ...
                        direct_report.xfmr_control_violations > 0
                    profile_count('psse_direct_blocked_by_xfmr');
                end
                if isfield(direct_report, 'swshunt_control_violations') && ...
                        direct_report.swshunt_control_violations > 0
                    profile_count('psse_direct_blocked_by_swshunt');
                end
            end
        else
            profile_count('psse_direct_unsupported');
        end

        profile_count('psse_auxiliary_called');
        [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
            auxiliary_psse_control_update(r, lam);
    end

    function TorF = direct_report_requires_auxiliary_pf(report)
        TorF = isfield(report, 'requires_auxiliary_pf') && ...
            option_is_enabled(report.requires_auxiliary_pf);
    end

    function TorF = direct_report_has_blocked_controls(report)
        TorF = isfield(report, 'blocked_violations') && ...
            report.blocked_violations > 0;
    end

    function report = merge_psse_direct_report(report, direct_report)
        names = {'blocked_violations', ...
            'xfmr_blocked_violations', 'xfmr_blocked_low', ...
            'xfmr_blocked_high', 'xfmr_locked_out', ...
            'xfmr_locked_count', ...
            'swshunt_blocked_violations', 'swshunt_blocked_low', ...
            'swshunt_blocked_high', 'swshunt_locked_out', ...
            'swshunt_locked_count'};
        for kk = 1:length(names)
            name = names{kk};
            if isfield(direct_report, name)
                report.(name) = direct_report.(name);
            end
        end
    end

    function [changed, mpcb_next, mpct_next, ac_controlled, report, ok] = ...
            auxiliary_psse_control_update(r, lam)
        profile_cleanup = profile_time_scope('auxiliary_psse_control_update'); %#ok<NASGU>
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

        opt_cleanup = profile_time_scope('psse_control_mpopt'); %#ok<NASGU>
        control_opt = psse_control_mpopt();
        clear opt_cleanup;
        try
            runpf_cleanup = profile_time_scope('psse_aux_runpf_psse'); %#ok<NASGU>
            [ac_controlled, ok] = runpf_psse(ac_case, control_opt);
            clear runpf_cleanup;
        catch
            clear runpf_cleanup;
            profile_count('psse_aux_runpf_exception');
            ok = 0;
            return;
        end
        if ~ok || ~isstruct(ac_controlled) || ~isfield(ac_controlled, 'bus')
            ok = 0;
            return;
        end

        current_cleanup = profile_time_scope('psse_current_mpc'); %#ok<NASGU>
        current = vsc_cpf_current_mpc(mpcb, mpct, lam);
        clear current_cleanup;
        [changed, report] = psse_active_set_changed(current, ac_controlled);
        if changed
            [mpcb_next, mpct_next] = apply_psse_active_set_update( ...
                current, ac_controlled);
        end
    end

    function TorF = has_auxiliary_psse_control_data(mpc, unified_bus)
        if nargin < 2
            unified_bus = [];
        end
        TorF = 0;
        if ~isfield(mpc, 'psse') || isempty(mpc.psse)
            return;
        end
        if psse_family_present(mpc, 'pqbrak') && ...
                pqbrak_auxiliary_active(mpc, unified_bus)
            TorF = 1;
            return;
        end
        families = {'genq', 'twodc', 'facts'};
        for kk = 1:length(families)
            if psse_family_present(mpc, families{kk})
                TorF = 1;
                return;
            end
        end
    end

    function TorF = pqbrak_auxiliary_active(mpc, unified_bus)
        TorF = 1;
        pq = mpc.psse.pqbrak;
        if isfield(pq, 'scale') && ~isempty(pq.scale) && ...
                any(abs(pq.scale(:) - 1) > 1e-10)
            return;
        end
        if ~isfield(pq, 'pqbrak') || isempty(pq.pqbrak) || ...
                isnan(pq.pqbrak) || pq.pqbrak <= 0
            TorF = 0;
            return;
        end
        vm = psse_unified_vm_for_mpc(mpc, unified_bus);
        TorF = any(vm < pq.pqbrak - 1e-10);
    end

    function vm = psse_unified_vm_for_mpc(mpc, unified_bus)
        [~, ~, ~, ~, BUS_I2, ~, ~, ~, ~, ~, ~, VM2] = idx_bus;
        vm = mpc.bus(:, VM2);
        if isempty(unified_bus)
            return;
        end
        for kk = 1:size(mpc.bus, 1)
            row = find(unified_bus(:, BUS_I2) == mpc.bus(kk, BUS_I2), 1);
            if ~isempty(row)
                vm(kk) = unified_bus(row, VM2);
            end
        end
    end

    function ac = psse_control_case_from_unified_result(r)
        profile_cleanup = profile_time_scope('psse_case_from_result'); %#ok<NASGU>
        ac = mp.psse_unified_active_set( ...
            'control_case_from_unified_result', r);
    end

    function ac = copy_original_active_set_to_ac(ac, mpc)
        profile_cleanup = profile_time_scope('psse_copy_active_set_to_ac'); %#ok<NASGU>
        ac = mp.psse_unified_active_set( ...
            'copy_original_active_set_to_ac', ac, mpc);
    end

    function control_opt = psse_control_mpopt()
        control_opt = mpoption(mpopt, 'verbose', 0, 'out.all', 0, ...
            'pf.enforce_q_lims', 0);
        if isfield(control_opt, 'vsc_mtdc')
            control_opt = rmfield(control_opt, 'vsc_mtdc');
        end
    end

    function [changed, report] = psse_active_set_changed(current, ac)
        profile_cleanup = profile_time_scope('psse_active_set_changed'); %#ok<NASGU>
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
        TorF = mp.psse_unified_active_set( ...
            'report_has_unsatisfied_controls', report);
    end

    function [changed, msg] = apply_selective_psse_control_lockout(report, lam)
        changed = 0;
        msg = '';
        if ~freeze_psse_controls_after_limit()
            return;
        end
        [xf_changed, xf_detail] = lockout_blocked_psse_family( ...
            'xfmr', report);
        [sw_changed, sw_detail] = lockout_blocked_psse_family( ...
            'swshunt', report);
        changed = xf_changed || sw_changed;
        if ~changed
            return;
        end
        details = {};
        if xf_changed
            details{end+1} = xf_detail;
        end
        if sw_changed
            details{end+1} = sw_detail;
        end
        msg = sprintf(['Selective PSS/E control freeze at lambda = %.8g; ' ...
            'locked %s at blocked control limit and continuing remaining ' ...
            'PSS/E discrete controls.'], lam, strjoin(details, ', '));
    end

    function [changed, detail] = lockout_blocked_psse_family(family, report)
        changed = 0;
        detail = '';
        rows = blocked_psse_rows(family, report);
        if isempty(rows)
            return;
        end
        mpcb = set_psse_control_lockout(mpcb, family, rows);
        mpct = set_psse_control_lockout(mpct, family, rows);
        changed = 1;
        row_txt = strtrim(sprintf('%d ', rows));
        detail = sprintf('%s rows [%s]', family, row_txt);
    end

    function rows = blocked_psse_rows(family, report)
        rows = [];
        low_name = [family '_blocked_low'];
        high_name = [family '_blocked_high'];
        mask = [];
        if isfield(report, low_name)
            mask = logical(report.(low_name)(:));
        end
        if isfield(report, high_name)
            high = logical(report.(high_name)(:));
            if isempty(mask)
                mask = high;
            else
                n = min(length(mask), length(high));
                mask(1:n) = mask(1:n) | high(1:n);
                if length(high) > length(mask)
                    mask(end+1:length(high)) = high(length(mask)+1:end);
                end
            end
        end
        if ~isempty(mask)
            rows = find(mask);
            rows = rows(:).';
        end
    end

    function mpc = set_psse_control_lockout(mpc, family, rows)
        if isempty(rows)
            return;
        end
        if ~isfield(mpc, 'psse') || isempty(mpc.psse)
            mpc.psse = struct();
        end
        if ~isfield(mpc.psse, 'control_lockout') || ...
                isempty(mpc.psse.control_lockout)
            mpc.psse.control_lockout = struct();
        end
        n = max(rows);
        if isfield(mpc.psse.control_lockout, family)
            locked = logical(mpc.psse.control_lockout.(family)(:));
            if length(locked) < n
                locked(n, 1) = false;
            end
        else
            locked = false(n, 1);
        end
        locked(rows) = true;
        mpc.psse.control_lockout.(family) = locked;
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
        n = mp.psse_unified_active_set('control_report_count', mpc, ...
            family, field);
    end

    function [bnext, tnext] = apply_psse_active_set_update(current, ac)
        profile_cleanup = profile_time_scope('psse_apply_active_set_update'); %#ok<NASGU>
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
        TorF = mp.psse_unified_active_set('load_equiv_changed', ac);
    end

    function TorF = has_psse_genq_control(mpc)
        TorF = mp.psse_unified_active_set('has_genq_control', mpc);
    end

    function TorF = psse_family_present(mpc, name)
        TorF = mp.psse_unified_active_set('family_present', mpc, name);
    end

    function mpc = copy_psse_control_fields(mpc, ac)
        mpc = mp.psse_unified_active_set('copy_control_fields', mpc, ac);
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
        profile_cleanup = profile_time_scope('solve_pf_at_lambda'); %#ok<NASGU>
        x = x0;
        [F, eval, ctx_lam] = unified_eval_at_lambda(ctx, x, lam, Sdelta);
        normF = norm(F, Inf);
        success = normF < ctx.opt.tol;
        iterations = 0;
        max_it = max(ctx.opt.max_it, 30);
        while ~success && iterations < max_it
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
        while alpha >= 1/1024
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
        profile_cleanup = profile_time_scope('cpf_corrector'); %#ok<NASGU>
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
        profile_cleanup = profile_time_scope('cpf_tangent'); %#ok<NASGU>
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
        profile_cleanup = profile_time_scope('eval_at_lambda'); %#ok<NASGU>
        ctx_lam = unified_context_at_lambda(ctx, lam);
        [F, eval] = unified_eval(ctx_lam, x, unified_Sbase_at_lambda(ctx, ...
            ctx_lam, lam, Sdelta));
    end

    function [F, eval] = unified_eval(ctx, x, Sbase)
        profile_cleanup = profile_time_scope('mismatch_eval'); %#ok<NASGU>
        [F, eval] = runpf_vsc_mtdc_unified('__mismatch', ctx, x, Sbase);
    end

    function ctx_lam = unified_context_at_lambda(ctx, lam)
        ctx_lam = ctx;
        if isfield(ctx, 'cpf_transfer')
            tr = ctx.cpf_transfer;
            ctx_lam.mpc = vsc_cpf_current_mpc(tr.base, tr.target, lam);
        end
    end

    function S = unified_Sbase_at_lambda(ctx, ctx_lam, lam, Sdelta)
        profile_cleanup = profile_time_scope('sbase_at_lambda'); %#ok<NASGU>
        if incremental_cpf_policies_enabled()
            [S, ok] = fast_unified_Sbase(ctx, ctx_lam.mpc);
            if ~ok
                profile_count('fast_sbase_fallback');
                ctx_eff = runpf_vsc_mtdc_unified('__setup', ctx_lam.mpc, ...
                    mpopt_pf);
                S = ctx_eff.Sbase;
            else
                profile_count('fast_sbase_hit');
            end
        else
            S = ctx.Sbase + lam * Sdelta;
        end
    end

    function dF = unified_dF_dlam(ctx, Sdelta, x, lam)
        model = ctx.model;
        dF = zeros(length(ctx.x0), 1);
        if incremental_cpf_policies_enabled() || ...
                unified_has_vsc_setpoint_transfer(ctx)
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

    function key = unified_context_pair_signature(b, t)
        key = [unified_context_signature(b) '|' unified_context_signature(t)];
    end

    function sig = unified_context_signature(mpc)
        parts = {
            numeric_signature(mpc.baseMVA);
            numeric_signature(mpc.bus);
            numeric_signature(mpc.branch);
            numeric_signature(mpc.gen);
            numeric_signature(mpc.busdc);
            numeric_signature(mpc.branchdc);
            numeric_signature(mpc.vsc)
        };
        sig = strjoin(parts, ';');
    end

    function sig = numeric_signature(x)
        if isempty(x)
            sig = '[]';
        else
            vals = round(full(x(:)') * 1e9) / 1e9;
            sig = sprintf('%dx%d:', size(x, 1), size(x, 2));
            sig = [sig sprintf('%.9g,', vals)];
        end
    end

    function [S, ok] = fast_unified_Sbase(ctx, mpc)
        profile_cleanup = profile_time_scope('fast_sbase'); %#ok<NASGU>
        ok = 0;
        S = [];
        if ~isfield(ctx, 'ac') || ~isfield(ctx.ac, 'order') || ...
                ~isfield(ctx.ac.order, 'bus') || ...
                ~isfield(ctx.ac.order.bus, 'i2e')
            return;
        end
        if ~fast_sbase_vsc_compatible(ctx.mpc, mpc)
            return;
        end
        ac = ctx.ac;
        ext_bus = ac.order.bus.i2e(:);
        bus_cols = existing_cols([PD QD GS BS], ac.bus, mpc.bus);
        for kk = 1:size(mpc.bus, 1)
            row = find(ext_bus == mpc.bus(kk, BUS_I), 1);
            if isempty(row)
                return;
            end
            ac.bus(row, bus_cols) = mpc.bus(kk, bus_cols);
        end
        if ~isfield(ac.order, 'gen') || ~isfield(ac.order.gen, 'i2e')
            return;
        end
        gen_ext = ac.order.gen.i2e(:);
        gen_cols = existing_cols([PG QG GEN_STATUS], ac.gen, mpc.gen);
        for kk = 1:length(gen_ext)
            g = gen_ext(kk);
            if g < 1 || g > size(mpc.gen, 1)
                return;
            end
            ac.gen(kk, gen_cols) = mpc.gen(g, gen_cols);
        end
        S = makeSbus(ac.baseMVA, ac.bus, ac.gen, ctx.mpopt);
        ok = 1;
    end

    function TorF = fast_sbase_vsc_compatible(a, b)
        TorF = isfield(a, 'vsc') && isfield(b, 'vsc') && ...
            size(a.vsc, 1) == size(b.vsc, 1) && ...
            size(a.bus, 1) == size(b.bus, 1) && ...
            size(a.gen, 1) == size(b.gen, 1);
        if ~TorF
            return;
        end
        cols = existing_cols([c.VSC_STATUS c.VSC_BUS c.BUSDC c.AC_MODE ...
            c.FILTER_G c.FILTER_B], a.vsc, b.vsc);
        TorF = isequal(round(a.vsc(:, cols) * 1e9), ...
            round(b.vsc(:, cols) * 1e9));
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
        profile_cleanup = profile_time_scope('build_cpf_result'); %#ok<NASGU>
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
            if profile_timing.enabled && isfield(results, 'cpf')
                results.cpf.timing = profile_summary();
            end
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
        if ~isempty(gen_dispatch) && isfield(r, 'cpf')
            r.cpf.gen_dispatch = gen_dispatch;
        end
        if incremental_cpf_policies_enabled() && isfield(r, 'cpf')
            r.cpf.cpf_policies = cpf_policy_state.policies;
            r.cpf.lambda_definition = incremental_lambda_definition();
            r.cpf.redispatch_basis = ...
                'incremental_from_previous_accepted_cpf_point';
        end
        if isfield(r, 'cpf')
            r.cpf.active_set_failure_policy = ...
                active_set_failure_policy_report(r.cpf.events);
        end
    end

    function cfg = init_active_set_failure_policy_config()
        cfg = struct( ...
            'psse_control', active_set_policy_record('psse_control', ...
                'PSS/E discrete controls', psse_control_feature_enabled(), ...
                psse_control_declared_policy(), ...
                'vsc_mtdc.psse_control_limit'), ...
            'vsc_capability', active_set_policy_record('vsc_capability', ...
                'VSC capability', unified_active_set_stages_enabled() && ...
                unified_vsc_capability_enabled(), ...
                capability_declared_policy('vsc'), ...
                'vsc_mtdc.capability_vsc_limit'), ...
            'gen_capability', active_set_policy_record('gen_capability', ...
                'generator capability', unified_active_set_stages_enabled() && ...
                unified_gen_capability_enabled(), ...
                capability_declared_policy('gen'), ...
                'vsc_mtdc.capability_gen_limit'), ...
            'hvdc_derating', active_set_policy_record('hvdc_derating', ...
                'HVDC dynamic derating', unified_active_set_stages_enabled() && ...
                unified_hvdc_derating_enabled(), ...
                hvdc_derating_declared_policy(), ...
                'cpf_policies.hvdc.vsc_derating') );
    end

    function rec = active_set_policy_record(id, feature, enabled, policy, source)
        if ~enabled
            policy = 'not-enabled';
        end
        rec = struct( ...
            'id', id, ...
            'feature', feature, ...
            'enabled', logical(enabled), ...
            'declared_policy', lower(policy), ...
            'observed_policy', 'not-triggered', ...
            'source', source, ...
            'event_count', 0, ...
            'last_event', '' );
    end

    function policy = psse_control_declared_policy()
        policy = 'stop';
        if isfield(opt, 'psse_control_limit') && ...
                ischar(opt.psse_control_limit) && ...
                strcmpi(opt.psse_control_limit, 'freeze')
            policy = 'freeze';
        end
    end

    function policy = capability_declared_policy(kind)
        policy = lower(capability_limit_mode(kind));
    end

    function policy = hvdc_derating_declared_policy()
        if unified_hvdc_derating_enabled()
            policy = 'warn-and-disable';
        else
            policy = 'not-enabled';
        end
    end

    function TorF = psse_control_feature_enabled()
        TorF = unified_active_set_stages_enabled() && ...
            isfield(mpopt_pf, 'vsc_mtdc') && ...
            isfield(mpopt_pf.vsc_mtdc, 'psse_aware') && ...
            any(mpopt_pf.vsc_mtdc.psse_aware) && ...
            has_psse_control_data(mpcb_transfer0);
    end

    function TorF = unified_active_set_stages_enabled()
        TorF = strcmp(method, 'unified');
    end

    function report = active_set_failure_policy_report(ev)
        report = active_set_policy_config;
        report.psse_control = active_set_policy_observed_record( ...
            report.psse_control, ev, {'PSSE_CONTROL'}, ...
            {'PSSE_CONTROL_LIMIT', 'PSSE_CONTROL_FAIL'}, ...
            {'PSSE_CONTROL_FREEZE', 'PSSE_CONTROL_SELECTIVE_FREEZE'}, ...
            {}, {});
        report.vsc_capability = active_set_policy_observed_record( ...
            report.vsc_capability, ev, {'VSC_CAPABILITY'}, ...
            {'VSC_CAPABILITY_LIMIT', 'VSC_CAPABILITY_FAIL'}, ...
            {'VSC_CAPABILITY_FREEZE'}, {}, ...
            {'VSC_CAPABILITY_MARGIN_INCREASE', ...
             'VSC_CAPABILITY_AC_RELEASE', ...
             'VSC_CAPABILITY_Q_SATURATION', ...
             'VSC_CAPABILITY_RESATURATION'});
        report.gen_capability = active_set_policy_observed_record( ...
            report.gen_capability, ev, {'GEN_CAPABILITY'}, ...
            {'GEN_CAPABILITY_LIMIT', 'GEN_CAPABILITY_FAIL'}, ...
            {'GEN_CAPABILITY_FREEZE'}, {}, {});
        report.hvdc_derating = active_set_policy_observed_record( ...
            report.hvdc_derating, ev, {'HVDC_DERATING'}, ...
            {'HVDC_DERATING_FAIL'}, {}, {'HVDC_DERATING_SKIPPED'}, {});
    end

    function rec = active_set_policy_observed_record(rec, ev, enforce_names, ...
            stop_names, freeze_names, warn_disable_names, experimental_names)
        all_names = [enforce_names(:); stop_names(:); freeze_names(:); ...
            warn_disable_names(:); experimental_names(:)];
        rec.event_count = active_set_event_count(ev, all_names);
        rec.last_event = active_set_last_event(ev, all_names);
        if ~rec.enabled
            rec.observed_policy = 'not-enabled';
        elseif active_set_has_event(ev, warn_disable_names)
            rec.observed_policy = 'warn-and-disable';
        elseif active_set_has_event(ev, experimental_names)
            rec.observed_policy = 'experimental';
        elseif active_set_has_event(ev, freeze_names)
            rec.observed_policy = 'freeze';
        elseif active_set_has_event(ev, stop_names)
            rec.observed_policy = 'stop';
        elseif active_set_has_event(ev, enforce_names)
            rec.observed_policy = 'enforce';
        end
    end

    function TorF = active_set_has_event(ev, wanted)
        TorF = active_set_event_count(ev, wanted) > 0;
    end

    function count = active_set_event_count(ev, wanted)
        count = 0;
        if isempty(ev) || isempty(wanted) || ~isfield(ev, 'name')
            return;
        end
        names = {ev.name};
        for kk = 1:length(wanted)
            count = count + sum(strcmp(names, wanted{kk}));
        end
    end

    function name = active_set_last_event(ev, wanted)
        name = '';
        if isempty(ev) || isempty(wanted) || ~isfield(ev, 'name')
            return;
        end
        for kk = length(ev):-1:1
            if any(strcmp(ev(kk).name, wanted))
                name = ev(kk).name;
                return;
            end
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
            'cpf_policies', [], 'profile', 0, ...
            'psse_control_limit', 'stop', 'psse_control_max_it', 20, ...
            'capability_enforce', 0, 'capability_max_it', 10, ...
            'capability_limit', 'stop', 'capability_vsc_limit', [], ...
            'capability_gen_limit', [], ...
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

    function st = init_incremental_cpf_policy_state(b, t, o)
        [st, gen_dispatch0, vsc_hvdc_dispatch0] = ...
            vsc_mtdc_cpf_policy_state('init', b, t, o);
        if isfield(st, 'enabled') && st.enabled
            gen_dispatch = gen_dispatch0;
            vsc_hvdc_dispatch = vsc_hvdc_dispatch0;
        end
    end

    function TorF = incremental_cpf_policies_enabled()
        TorF = isstruct(cpf_policy_state) && ...
            isfield(cpf_policy_state, 'enabled') && cpf_policy_state.enabled;
    end

    function refresh_incremental_policy_anchor(lam)
        if ~incremental_cpf_policies_enabled()
            return;
        end
        cpf_policy_state.anchor_mpc = incremental_cpf_current_mpc( ...
            mpcb, mpct, lam);
        cpf_policy_state.anchor_lam = lam;
    end

    function mpc = incremental_cpf_current_mpc(b, ~, lam)
        mpc = vsc_mtdc_cpf_policy_state('current_mpc', ...
            b, lam, cpf_policy_state);
    end

    function rows = incremental_gen_participant_rows()
        rows = vsc_mtdc_cpf_policy_state( ...
            'gen_participant_rows', cpf_policy_state);
    end

    function rows = incremental_hvdc_participant_rows()
        rows = vsc_mtdc_cpf_policy_state( ...
            'hvdc_participant_rows', cpf_policy_state);
    end

    function s = incremental_lambda_definition()
        s = vsc_mtdc_cpf_policy_state( ...
            'lambda_definition', cpf_policy_state);
    end

    function mpc = vsc_cpf_current_mpc(b, t, l)
        if incremental_cpf_policies_enabled()
            mpc = incremental_cpf_current_mpc(b, t, l);
            return;
        end
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
            'bus',         r.bus, ...
            'branch',      r.branch, ...
            'gen',         r.gen, ...
            'busdc',       r.busdc, ...
            'branchdc',    r.branchdc, ...
            'vsc',         r.vsc, ...
            'vsc_iterations', r.iterations, ...
            'default_step', s );
    end

    function cpf = append_trace(cpf, r, V, s, l)
        profile_cleanup = profile_time_scope('append_trace'); %#ok<NASGU>
        cpf.V_hat = [cpf.V_hat V];
        cpf.lam_hat = [cpf.lam_hat l];
        cpf.V = [cpf.V V];
        cpf.lam = [cpf.lam l];
        cpf.steps = [cpf.steps s];
        cpf.bus = cat(3, cpf.bus, r.bus);
        cpf.branch = cat(3, cpf.branch, r.branch);
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

    function cpf = finalize_trace(cpf, it, msg, ev, fail)
        profile_cleanup = profile_time_scope('finalize_trace'); %#ok<NASGU>
        cpf.iterations = it;
        cpf.max_lam = max(cpf.lam);
        cpf.done_msg = msg;
        cpf.events = ev;
        cpf.failure = fail;
    end

    function timing = init_profile_timing(enabled)
        timing = struct( ...
            'enabled', logical(enabled), ...
            'total', struct(), ...
            'count', struct() );
    end

    function cleanup = profile_time_scope(name)
        if profile_timing.enabled
            tstart = tic;
            cleanup = onCleanup(@() profile_add_time(name, tstart));
        else
            cleanup = [];
        end
    end

    function profile_add_time(name, tstart)
        if ~profile_timing.enabled
            return;
        end
        profile_ensure_counter(name);
        profile_timing.total.(name) = profile_timing.total.(name) + ...
            toc(tstart);
        profile_timing.count.(name) = profile_timing.count.(name) + 1;
    end

    function profile_count(name)
        if ~profile_timing.enabled
            return;
        end
        profile_ensure_counter(name);
        profile_timing.count.(name) = profile_timing.count.(name) + 1;
    end

    function profile_count_by(name, amount)
        if ~profile_timing.enabled
            return;
        end
        profile_ensure_counter(name);
        profile_timing.count.(name) = profile_timing.count.(name) + amount;
    end

    function profile_ensure_counter(name)
        if ~isfield(profile_timing.total, name)
            profile_timing.total.(name) = 0;
            profile_timing.count.(name) = 0;
        end
    end

    function out = profile_summary()
        names = fieldnames(profile_timing.total);
        total = zeros(length(names), 1);
        count = zeros(length(names), 1);
        for kk = 1:length(names)
            total(kk) = profile_timing.total.(names{kk});
            count(kk) = profile_timing.count.(names{kk});
        end
        if isempty(names)
            average = zeros(0, 1);
            order = [];
        else
            average = total ./ max(count, 1);
            [~, order] = sort(total, 'descend');
        end
        out = struct( ...
            'enabled', profile_timing.enabled, ...
            'names', {names(order)}, ...
            'total', total(order), ...
            'count', count(order), ...
            'average', average(order) );
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
        setup = internal_cpf_setup(args, default_mpopt);

        [F, eval, ctx_lam] = unified_eval_at_lambda(setup.ctx, ...
            setup.x, setup.lam, setup.Sdelta);
        J = runpf_vsc_mtdc_unified('__jacobian', ctx_lam, eval, []);
        dF_dlam = unified_dF_dlam(setup.ctx, setup.Sdelta, setup.x, ...
            setup.lam);
        P = unified_cpf_p(setup.parameterization, setup.h, setup.z, ...
            setup.x, setup.lam, setup.xprev, setup.lamprev);
        [dPdx, dPdlam] = unified_cpf_p_jac(setup.parameterization, ...
            setup.z, setup.x, setup.lam, setup.xprev, setup.lamprev);

        out = struct( ...
            'ctx',              setup.ctx, ...
            'ctxt',             setup.ctxt, ...
            'Sdelta',           setup.Sdelta, ...
            'x',                setup.x, ...
            'lam',              setup.lam, ...
            'z',                setup.z, ...
            'h',                setup.h, ...
            'xprev',            setup.xprev, ...
            'lamprev',          setup.lamprev, ...
            'parameterization', setup.parameterization, ...
            'F',                F, ...
            'P',                P, ...
            'eval',             eval, ...
            'J',                J, ...
            'dF_dlam',          dF_dlam, ...
            'dPdx',             dPdx, ...
            'dPdlam',           dPdlam, ...
            'vsc_hvdc_dispatch', setup.vsc_hvdc_dispatch, ...
            'A',                [J dF_dlam; dPdx dPdlam], ...
            'F_aug',            [F; P] );
    end

    function setup = internal_cpf_setup(args, default_mpopt)
        % Contract for internal derivative tests only:
        % required args: base, target.
        % optional args: mpopt, x, lam, parameterization, z, h, xprev, lamprev.
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
        opt = vsc_cpf_options(opt0);
        cpf_policy_state = init_incremental_cpf_policy_state(b, t, opt);
        if ~isempty(vsc_hvdc_dispatch)
            dispatch = vsc_hvdc_dispatch;
        end
        validate_vsc_cpf_cases(b, t);
        validate_unified_cpf_transfer(b, t);
        ctx = runpf_vsc_mtdc_unified('__setup', b, opt_pf);
        ctxt = runpf_vsc_mtdc_unified('__setup', t, opt_pf);
        validate_unified_contexts(ctx, ctxt);
        Sdelta = ctxt.Sbase - ctx.Sbase;
        ctx = attach_unified_cpf_transfer(ctx, b, t, Sdelta);
        ctxt = attach_unified_cpf_transfer(ctxt, b, t, Sdelta);

        x = internal_arg_or_default(args, 'x', ctx.x0);
        lam = internal_arg_or_default(args, 'lam', 0);
        parameterization = internal_arg_or_default(args, ...
            'parameterization', opt0.cpf.parameterization);
        z = internal_arg_or_default(args, 'z', []);
        if isempty(z)
            z = zeros(length(x) + 1, 1);
            z(end) = 1;
        end
        h = internal_arg_or_default(args, 'h', opt0.cpf.step);
        xprev = internal_arg_or_default(args, 'xprev', x - h * z(1:end-1));
        lamprev = internal_arg_or_default(args, 'lamprev', lam - h * z(end));

        setup = struct( ...
            'ctx',              ctx, ...
            'ctxt',             ctxt, ...
            'Sdelta',           Sdelta, ...
            'x',                x, ...
            'lam',              lam, ...
            'z',                z, ...
            'h',                h, ...
            'xprev',            xprev, ...
            'lamprev',          lamprev, ...
            'parameterization', parameterization, ...
            'vsc_hvdc_dispatch', dispatch );
    end

    function val = internal_arg_or_default(args, name, default)
        if isfield(args, name) && ~isempty(args.(name))
            val = args.(name);
        else
            val = default;
        end
    end

end
