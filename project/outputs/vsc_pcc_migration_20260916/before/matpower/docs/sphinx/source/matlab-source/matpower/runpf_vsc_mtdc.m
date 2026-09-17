function [results, success] = runpf_vsc_mtdc(casedata, mpopt, fname, solvedcase)
% runpf_vsc_mtdc - Runs an AC/DC VSC-MTDC power flow.
% ::
%
%   RESULTS = RUNPF_VSC_MTDC(CASEDATA, MPOPT)
%   [RESULTS, SUCCESS] = RUNPF_VSC_MTDC(CASEDATA, MPOPT)
%
%   Runs a power flow for a MATPOWER case with explicit VSC-MTDC data in
%   MPC.BUSDC, MPC.BRANCHDC and MPC.VSC. By default the algorithm solves
%   the AC network, DC network and VSC converter balance equations in one
%   Newton system.
%
%   Set MPOPT.VSC_MTDC.METHOD to 'unified' to request the default unified
%   formulation explicitly. Set it to 'sequential' to use the sequential
%   method:
%
%       1. Build the extended AC case with explicit VSC station topology.
%       2. Solve the AC network with RUNPF.
%       3. Solve the resistive DC network with SOLVE_VSC_DC_PF.
%       4. Update converter powers and losses.
%       5. Iterate until the AC/DC fixed point converges.
%
%   Each VSC station is modeled as
%
%       PCC AC bus -> transformer -> filter bus -> phase reactor
%           -> VSC internal AC bus -> VSC/DC interface
%
%   The transformer, filter and reactor remain separate elements. No
%   transformer/reactor equivalent impedance is formed.
%
%   Sign convention for each VSC converter:
%
%       Pac > 0 is active power injection into the AC network.
%       Pdc > 0 is active power injection into the DC network.
%       Ploss >= 0 and Pac + Pdc + Ploss = 0.
%
%   The DC slack mode fixes Vdc and computes Pdc from the DC balance. Fixed
%   Pdc and optional droop modes are VSC-only controls.
%
%   VSC P-Q capability handling is available in two forms:
%
%       CHECK_CAPABILITY_LIMITS(RESULTS) performs a post-solve audit and
%       reports the saturated operating point without modifying the solution.
%
%       MPOPT.VSC_MTDC.CAPABILITY_ENFORCE = 1, or the PF-specific override
%       MPOPT.VSC_MTDC.CAPABILITY_PF_ENFORCE = 1, enables TESIS-style
%       solve-saturate-continue active-set enforcement. The PF is solved,
%       saturated VSCs are converted to fixed P/Q controls, and the PF is
%       solved again until no VSC capability active-set change remains or
%       MPOPT.VSC_MTDC.CAPABILITY_PF_MAX_IT is reached.
%
%   Capability enforcement is PF/CPF control logic, not OPF constraints. It
%   does not optimize redispatch and does not enforce transformer/reactor
%   thermal limits as branch-flow constraints. This routine does not implement
%   LCC converters or converter type switching.
%
%   Common MPOPT.VSC_MTDC fields used by PF are:
%       METHOD, AC_SOLVER, MAX_IT, TOL, DC_MAX_IT, TOL_P, DC_TOL_P, TOL_V,
%       TOL_Q, PSSE_AWARE, PSSE_CONTROL_MAX_IT, CAPABILITY_ENFORCE,
%       CAPABILITY_MAX_IT, CAPABILITY_PF_ENFORCE, CAPABILITY_PF_MAX_IT,
%       CAPABILITY_VSC_SMAX, CAPABILITY_VSC_VMAX and
%       CAPABILITY_VSC_MODE.
%
%   Outputs:
%       RESULTS : results struct with fields
%           success, iterations, ac, busdc, branchdc, vsc, vsc_state,
%           convergence and et.
%       SUCCESS : 1 if converged, 0 otherwise.
%
% See also runpf, runpf_vsc_mtdc_unified, runcpf_vsc_mtdc, idx_busdc,
% idx_branchdc, idx_vsc, solve_vsc_dc_pf, check_capability_limits,
% enforce_vsc_capability_active_set.

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

if isfield(mpopt, 'model') && strcmpi(mpopt.model, 'DC')
    error('runpf_vsc_mtdc: DC MATPOWER formulation is not supported for VSC-MTDC power flow');
end

t0 = tic;
mpc = loadcase(casedata);
validate_vsc_mtdc_case(mpc);

method = vsc_mtdc_method(mpopt);
opt = vsc_mtdc_options(mpopt);
if vsc_pf_capability_enabled(opt)
    [results, success] = runpf_vsc_capability_loop(mpc, mpopt, opt, ...
        t0, fname, solvedcase);
    return;
end
if strcmp(method, 'unified')
    [results, success] = runpf_vsc_mtdc_unified(mpc, mpopt, fname, solvedcase);
    return;
end

c = idx_vsc;
vsc = mpc.vsc;
nv = size(vsc, 1);

dcopt = struct('max_it', opt.dc_max_it, 'tol_p', opt.dc_tol_p, 'tol_v', opt.tol_v);

state = initialize_vsc_state(mpc);
history = zeros(opt.max_it, 7);
success = 0;
iterations = 0;
last_ac = [];
last_dc = [];
conv = struct('max_delta_pac', Inf, 'max_delta_pdc', Inf, ...
    'max_delta_vdc', Inf, 'max_delta_qac', Inf, ...
    'max_delta_vac_set', Inf, 'max_vac_ctrl_error', Inf, ...
    'max_balance', Inf);

for k = 1:opt.max_it
    iterations = k;
    [ac_case, map] = apply_vsc_ac_model(mpc, state);
    [ac, ac_success] = run_vsc_ac_pf(ac_case, mpopt);
    last_ac = ac;
    if ~ac_success
        break;
    end

    dc_state = read_vsc_ac_state(mpc, state, ac, map);
    fixed_pac = vsc(:, c.AC_MODE) == c.VSC_AC_PQ | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
    dc_state.pdc_override = NaN(nv, 1);
    kk = find(fixed_pac & vsc(:, c.VSC_STATUS) > 0 & vsc(:, c.DC_MODE) ~= c.VSC_DC_VDC);
    dc_state.pdc_override(kk) = -vsc(kk, c.PAC_SET) - dc_state.ploss(kk);

    dc = solve_vsc_dc_pf(mpc, dc_state, dcopt);
    last_dc = dc;
    if ~dc.success
        break;
    end

    [state, conv] = update_vsc_state(mpc, state, ac, dc, map);
    history(k, :) = [conv.max_delta_pac conv.max_delta_pdc ...
        conv.max_delta_vdc conv.max_delta_qac conv.max_delta_vac_set ...
        conv.max_vac_ctrl_error conv.max_balance];

    if conv.max_delta_pac < opt.tol_p && ...
            conv.max_delta_pdc < opt.tol_p && ...
            conv.max_delta_vdc < opt.tol_v && ...
            conv.max_delta_qac < opt.tol_q && ...
            conv.max_delta_vac_set < opt.tol_v && ...
            conv.max_vac_ctrl_error < opt.tol_v && ...
            conv.max_balance < opt.tol_p
        success = 1;
        break;
    end
end

if isempty(last_dc)
    last_dc = initial_dc_results(mpc, state);
end

results = mpc;
results.success = success;
results.iterations = iterations;
results.ac = last_ac;
results.busdc = last_dc.busdc;
results.branchdc = last_dc.branchdc;
results.vsc = build_vsc_results(vsc, state);
results.vsc_state = state;
results.convergence = struct( ...
    'converged',       success, ...
    'tol_p',           opt.tol_p, ...
    'tol_v',           opt.tol_v, ...
    'tol_q',           opt.tol_q, ...
    'max_delta_pac',   conv.max_delta_pac, ...
    'max_delta_pdc',   conv.max_delta_pdc, ...
    'max_delta_vdc',   conv.max_delta_vdc, ...
    'max_delta_qac',   conv.max_delta_qac, ...
    'max_delta_vac_set', conv.max_delta_vac_set, ...
    'max_vac_ctrl_error', conv.max_vac_ctrl_error, ...
    'max_balance',     conv.max_balance, ...
    'history',         history(1:iterations, :) );
results.et = toc(t0);

if ~isempty(fname)
    fd = fopen(fname, 'a');
    if fd ~= -1
        fprintf(fd, 'VSC-MTDC power flow success = %d, iterations = %d, elapsed = %.4g s\n', ...
            results.success, results.iterations, results.et);
        fclose(fd);
    end
end
if ~isempty(solvedcase)
    savecase(solvedcase, results);
end

if nargout > 1
    success = results.success;
end


function validate_vsc_mtdc_case(mpc)
bdc = idx_busdc;
brdc = idx_branchdc;
c = idx_vsc;

bad_fields = {'converter', 'hvdc', 'converter_type'};
for i = 1:length(bad_fields)
    if isfield(mpc, bad_fields{i})
        error('runpf_vsc_mtdc: unsupported field ''%s'' found; use busdc, branchdc and vsc only', bad_fields{i});
    end
end
if ~isfield(mpc, 'busdc') || size(mpc.busdc, 2) < bdc.BASE_KVDC
    error('runpf_vsc_mtdc: case must contain a busdc field with at least %d columns', bdc.BASE_KVDC);
end
if ~isfield(mpc, 'branchdc') || size(mpc.branchdc, 2) < brdc.BRDC_STATUS
    error('runpf_vsc_mtdc: case must contain a branchdc field with at least %d columns', brdc.BRDC_STATUS);
end
if ~isfield(mpc, 'vsc') || size(mpc.vsc, 2) < c.REACTOR_RATE_C
    error('runpf_vsc_mtdc: case must contain a vsc field with at least %d columns', c.REACTOR_RATE_C);
end

vsc = mpc.vsc;
active = find(vsc(:, c.VSC_STATUS) > 0);
if isempty(active)
    error('runpf_vsc_mtdc: at least one VSC must be in service');
end
if ~any(vsc(active, c.DC_MODE) == c.VSC_DC_VDC)
    error('runpf_vsc_mtdc: at least one in-service VSC must use VSC_DC_VDC mode');
end

valid_ac = [c.VSC_AC_Q; c.VSC_AC_V; c.VSC_AC_PQ; c.VSC_AC_PV];
valid_dc = [c.VSC_DC_VDC; c.VSC_DC_PDC; c.VSC_DC_DROOP];
if any(~ismember(vsc(active, c.AC_MODE), valid_ac))
    error('runpf_vsc_mtdc: unknown AC_MODE in vsc matrix');
end
if any(~ismember(vsc(active, c.DC_MODE), valid_dc))
    error('runpf_vsc_mtdc: unknown DC_MODE in vsc matrix');
end
fixed_pac = vsc(:, c.AC_MODE) == c.VSC_AC_PQ | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
if any(fixed_pac(active) & vsc(active, c.DC_MODE) == c.VSC_DC_VDC)
    error('runpf_vsc_mtdc: VSC_DC_VDC converters cannot use fixed Pac AC modes');
end
if any(vsc(active, c.LOSS_A) < 0 | vsc(active, c.LOSS_B) < 0 | vsc(active, c.LOSS_C) < 0)
    error('runpf_vsc_mtdc: VSC loss coefficients must be non-negative');
end
if any(mpc.branchdc(mpc.branchdc(:, brdc.BRDC_STATUS) > 0, brdc.BRDC_R) <= 0)
    error('runpf_vsc_mtdc: in-service branchdc rows must have positive resistance');
end

for k = active'
    if isempty(find(mpc.bus(:, 1) == vsc(k, c.VSC_BUS), 1))
        error('runpf_vsc_mtdc: VSC row %d refers to an unknown AC bus', k);
    end
    if isempty(find(mpc.busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1))
        error('runpf_vsc_mtdc: VSC row %d refers to an unknown DC bus', k);
    end
end

for k = active(vsc(active, c.DC_MODE) == c.VSC_DC_VDC)'
    b = vsc(k, c.BUSDC);
    same_bus_slack = active(vsc(active, c.DC_MODE) == c.VSC_DC_VDC & vsc(active, c.BUSDC) == b);
    if any(abs(vsc(same_bus_slack, c.VDC_SET) - vsc(k, c.VDC_SET)) > 1e-10)
        error('runpf_vsc_mtdc: DC slack converters at the same DC bus must have the same VDC_SET');
    end
end


function opt = vsc_mtdc_options(mpopt)
opt = struct('max_it', 20, 'dc_max_it', 20, 'tol_p', 1e-6, ...
    'dc_tol_p', 1e-8, 'tol_v', 1e-8, 'tol_q', 1e-6);
if isfield(mpopt, 'vsc_mtdc')
    f = fieldnames(mpopt.vsc_mtdc);
    for k = 1:length(f)
        val = mpopt.vsc_mtdc.(f{k});
        if ~isempty(val)
            opt.(f{k}) = val;
        end
    end
end


function method = vsc_mtdc_method(mpopt)
method = 'unified';
if isfield(mpopt, 'vsc_mtdc') && isfield(mpopt.vsc_mtdc, 'method') && ...
        ~isempty(mpopt.vsc_mtdc.method)
    method = lower(mpopt.vsc_mtdc.method);
end
if ~ismember(method, {'sequential', 'unified'})
    error('runpf_vsc_mtdc: unknown VSC-MTDC method ''%s''', method);
end


function TorF = vsc_pf_capability_enabled(opt)
if isfield(opt, 'capability_pf_enforce') && ...
        ~isempty(opt.capability_pf_enforce)
    TorF = option_is_enabled(opt.capability_pf_enforce);
elseif isfield(opt, 'capability_enforce') && ~isempty(opt.capability_enforce)
    TorF = option_is_enabled(opt.capability_enforce);
else
    TorF = 0;
end


function TorF = option_is_enabled(val)
if ischar(val)
    TorF = any(strcmpi(val, {'1', 'on', 'true', 'yes'}));
else
    TorF = any(val(:) ~= 0);
end


function max_it = vsc_pf_capability_max_it(opt)
if isfield(opt, 'capability_pf_max_it') && ...
        ~isempty(opt.capability_pf_max_it)
    max_it = opt.capability_pf_max_it;
elseif isfield(opt, 'capability_max_it') && ~isempty(opt.capability_max_it)
    max_it = opt.capability_max_it;
else
    max_it = 5;
end
max_it = max(1, max_it);


function [results, success] = runpf_vsc_capability_loop(mpc, mpopt, opt, ...
        t0, fname, solvedcase)
max_it = vsc_pf_capability_max_it(opt);
mpopt_solve = disable_vsc_pf_capability(mpopt);
current = mpc;
reports = repmat(enforce_vsc_capability_active_set(mpc, mpc, opt), 0, 1);
success = 0;
failed = 0;
final_violations = Inf;
iterations = 0;

for k = 1:max_it
    iterations = k;
    [results, solve_success] = runpf_vsc_mtdc(current, mpopt_solve);
    [next, report] = enforce_vsc_capability_active_set(current, results, opt);
    reports = append_pf_capability_report(reports, report);
    if ~solve_success
        failed = 1;
        break;
    end
    if ~report.changed
        final = check_vsc_capability(results, vsc_capability_check_options(opt));
        final_violations = final.violations;
        success = final_violations == 0;
        failed = ~success;
        break;
    end
    current = next;
end

if iterations == max_it && reports(end).changed
    failed = 1;
    success = 0;
    final_violations = reports(end).violations;
end

results.success = success;
results.et = toc(t0);
results.vsc_capability = check_vsc_capability(results, ...
    vsc_capability_check_options(opt));
results.convergence.vsc_capability = struct( ...
    'enabled',          1, ...
    'converged',        success, ...
    'failed',           failed, ...
    'iterations',       iterations, ...
    'max_it',           max_it, ...
    'changed',          any([reports.changed]), ...
    'final_violations', final_violations, ...
    'reports',          reports );

if ~isempty(fname)
    fd = fopen(fname, 'a');
    if fd ~= -1
        fprintf(fd, ['VSC-MTDC power flow capability success = %d, ' ...
            'iterations = %d, elapsed = %.4g s\n'], ...
            results.success, results.iterations, results.et);
        fclose(fd);
    end
end
if ~isempty(solvedcase)
    savecase(solvedcase, results);
end


function reports = append_pf_capability_report(reports, report)
if isempty(reports)
    reports = report;
else
    reports(end+1, 1) = report;
end


function mpopt = disable_vsc_pf_capability(mpopt)
if ~isfield(mpopt, 'vsc_mtdc')
    mpopt.vsc_mtdc = struct();
end
mpopt.vsc_mtdc.capability_enforce = 0;
mpopt.vsc_mtdc.capability_pf_enforce = 0;


function opt_out = vsc_capability_check_options(opt)
opt_out = struct();
if isfield(opt, 'capability_vsc_smax')
    opt_out.vsc_smax = opt.capability_vsc_smax;
end
if isfield(opt, 'capability_vsc_vmax')
    opt_out.vmax = opt.capability_vsc_vmax;
end
if isfield(opt, 'capability_vsc_mode')
    opt_out.mode = opt.capability_vsc_mode;
end


function [ac, success] = run_vsc_ac_pf(ac_case, mpopt)
solver = 'runpf';
if isfield(mpopt, 'vsc_mtdc') && isfield(mpopt.vsc_mtdc, 'ac_solver') && ...
        ~isempty(mpopt.vsc_mtdc.ac_solver)
    solver = lower(mpopt.vsc_mtdc.ac_solver);
end

switch solver
    case 'runpf'
        [ac, success] = runpf(ac_case, mpopt);
    case 'runpf_psse'
        [ac, success] = runpf_psse(ac_case, mpopt);
    otherwise
        error('runpf_vsc_mtdc: unknown VSC-MTDC AC solver ''%s''', solver);
end


function state = initialize_vsc_state(mpc)
c = idx_vsc;
bdc = idx_busdc;
vsc = mpc.vsc;
nv = size(vsc, 1);

state = struct( ...
    'pac',            zeros(nv, 1), ...
    'qac',            zeros(nv, 1), ...
    'pdc',            zeros(nv, 1), ...
    'vdc',            zeros(nv, 1), ...
    'vac_pcc',        ones(nv, 1), ...
    'vac_filter',     ones(nv, 1), ...
    'vac_internal_set', ones(nv, 1), ...
    'vac_internal',   ones(nv, 1), ...
    'ploss',          zeros(nv, 1), ...
    'iac',            zeros(nv, 1), ...
    'ptr_loss',       zeros(nv, 1), ...
    'preactor_loss',  zeros(nv, 1), ...
    'is_dc_slack',    zeros(nv, 1), ...
    'filter_bus',     zeros(nv, 1), ...
    'internal_bus',   zeros(nv, 1), ...
    'tr_branch',      zeros(nv, 1), ...
    'reactor_branch', zeros(nv, 1) );

active = find(vsc(:, c.VSC_STATUS) > 0);
state.qac(active) = vsc(active, c.QAC_SET);
state.vac_internal_set(active) = vsc(active, c.VAC_SET);
state.vac_internal(active) = vsc(active, c.VAC_SET);
state.pdc(active) = vsc(active, c.PDC_SET);
for k = active'
    b = find(mpc.busdc(:, bdc.BUSDC_I) == vsc(k, c.BUSDC), 1);
    state.vdc(k) = mpc.busdc(b, bdc.VDC);
    if vsc(k, c.DC_MODE) == c.VSC_DC_VDC
        state.vdc(k) = vsc(k, c.VDC_SET);
        state.is_dc_slack(k) = 1;
    end
end

state.pac(active) = -state.pdc(active);
fixed_pac = vsc(:, c.AC_MODE) == c.VSC_AC_PQ | vsc(:, c.AC_MODE) == c.VSC_AC_PV;
state.pac(fixed_pac & vsc(:, c.VSC_STATUS) > 0) = vsc(fixed_pac & vsc(:, c.VSC_STATUS) > 0, c.PAC_SET);
[state.ploss, state.iac] = calc_vsc_losses(mpc.baseMVA, state.pac, ...
    state.qac, state.vac_internal, vsc);
state.ploss(vsc(:, c.VSC_STATUS) <= 0) = 0;
kk = active(~fixed_pac(active));
state.pac(kk) = -state.pdc(kk) - state.ploss(kk);


function state = read_vsc_ac_state(mpc, state, ac, map)
[~, ~, ~, ~, BUS_I, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
[~, ~, QG] = idx_gen;
c = idx_vsc;
vsc = mpc.vsc;
active = find(vsc(:, c.VSC_STATUS) > 0);

for k = active'
    pcc = find(ac.bus(:, BUS_I) == vsc(k, c.VSC_BUS), 1);
    filter = find(ac.bus(:, BUS_I) == map.filter_bus(k), 1);
    internal = find(ac.bus(:, BUS_I) == map.internal_bus(k), 1);
    state.vac_pcc(k) = ac.bus(pcc, VM);
    state.vac_filter(k) = ac.bus(filter, VM);
    state.vac_internal(k) = ac.bus(internal, VM);
    if map.uses_gen(k)
        state.qac(k) = ac.gen(map.gen(k), QG);
    else
        state.qac(k) = vsc(k, c.QAC_SET);
    end
end
[state.ploss, state.iac] = calc_vsc_losses(mpc.baseMVA, state.pac, ...
    state.qac, state.vac_internal, vsc);
state.ploss(vsc(:, c.VSC_STATUS) <= 0) = 0;


function dc = initial_dc_results(mpc, state)
bdc = idx_busdc;
brdc = idx_branchdc;
busdc = mpc.busdc;
branchdc = mpc.branchdc;
if size(busdc, 2) < bdc.IDC
    busdc = [busdc zeros(size(busdc, 1), bdc.IDC - size(busdc, 2))];
end
if size(branchdc, 2) < brdc.ITDC
    branchdc = [branchdc zeros(size(branchdc, 1), brdc.ITDC - size(branchdc, 2))];
end
dc = struct('success', 0, 'iterations', 0, 'max_mismatch', Inf, ...
    'busdc', busdc, 'branchdc', branchdc, 'vdc', busdc(:, bdc.VDC), ...
    'pdc', state.pdc, 'Gdc', makeGdc(busdc, branchdc));


function vsc_out = build_vsc_results(vsc, state)
c = idx_vsc;
nv = size(vsc, 1);
if size(vsc, 2) < c.REACTOR_BRANCH
    vsc_out = [vsc zeros(nv, c.REACTOR_BRANCH - size(vsc, 2))];
else
    vsc_out = vsc;
end
vsc_out(:, c.PAC) = state.pac;
vsc_out(:, c.QAC) = state.qac;
vsc_out(:, c.PDC) = state.pdc;
vsc_out(:, c.VDC) = state.vdc;
vsc_out(:, c.VAC_PCC) = state.vac_pcc;
vsc_out(:, c.VAC_FILTER) = state.vac_filter;
vsc_out(:, c.VAC_INTERNAL) = state.vac_internal;
vsc_out(:, c.PLOSS) = state.ploss;
vsc_out(:, c.PTR_LOSS) = state.ptr_loss;
vsc_out(:, c.PREACTOR_LOSS) = state.preactor_loss;
vsc_out(:, c.IS_DC_SLACK) = state.is_dc_slack;
vsc_out(:, c.FILTER_BUS) = state.filter_bus;
vsc_out(:, c.INTERNAL_BUS) = state.internal_bus;
vsc_out(:, c.TR_BRANCH) = state.tr_branch;
vsc_out(:, c.REACTOR_BRANCH) = state.reactor_branch;
