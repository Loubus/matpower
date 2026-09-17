function [checks, evidence] = t_control_acceptance_batch1(quiet, outdir)
%T_CONTROL_ACCEPTANCE_BATCH1 Physical gates independent of exact PSS/E states.
% Run iniciar_proyecto first, then addpath(fullfile(pwd,'tests')).
% Saves all observations before MP-Test reports failures. No expected failures
% are skipped or converted to passes. Requires a fresh output directory.
if nargin < 1, quiet = 0; end
accept_clock = tic;
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 2
    outdir = tempname(fullfile(root, 'outputs'));
end
assert(~exist(outdir, 'dir'), 'Use a fresh acceptance output directory.');
mkdir(outdir);
fixture_path = fullfile(root, 'tests', 'fixtures', 'controls');
oldpath = path;
path_cleanup = onCleanup(@() path(oldpath));
addpath(fixture_path);
[PQ, PV, ~, ~, BUS_I, BT, PD, QD, ~, BS, ~, VM, VA] = idx_bus;
[~, ~, QG, QMAX, QMIN, VG] = idx_gen;
c = idx_vsc;
bdc = idx_busdc;
opt = mpoption('out.all', 0, 'verbose', 0);
opt.vsc_mtdc.method = 'unified';
cpopt = mpoption(opt, 'cpf.stop_at', 0.2, 'cpf.step', 0.1);
checks = struct('id', {}, 'passed', {}, 'detail', {});
evidence = struct('options_pf', opt, 'options_cpf', cpopt, ...
    'matlab_version', version, 'power_tol_pu', 1e-8, ...
    'state_tol', 1e-8, 'voltage_comparison_tol_pu', 1e-6, ...
    'reactive_limit_tol_mvar', 0.01);

%% Solve the unchanged regression scenarios.
sw = cleanup_batch1_vsc_case('shunt');
gq = cleanup_batch1_vsc_case('genq');
target = sw; target.bus(:, [PD QD]) = 1.02*sw.bus(:, [PD QD]);
sp = runpf_psse(sw, opt);
sc = runcpf_psse(sw, target, cpopt);
target = gq; target.bus(:, [PD QD]) = 1.02*gq.bus(:, [PD QD]);
gc = runcpf_psse(gq, target, cpopt);
evidence.inputs = struct('shunt', sw, 'genq', gq);
evidence.shunt_pf = sp; evidence.shunt_cpf = sc; evidence.genq_cpf = gc;

% Preserve all four original expectations separately, with original tolerances.
evidence.legacy = struct('test_number', {110, 111, 283, 284}, ...
    'actual', {sp.convergence.psse_controls.changed, sp.bus(5, BS), ...
        gc.bus(2, BT), gc.gen(2, QG)}, ...
    'expected', {1, 9, PQ, gc.gen(2, QMAX)}, ...
    'passed', {logical(sp.convergence.psse_controls.changed), ...
        abs(sp.bus(5, BS)-9) < 1e-10, gc.bus(2, BT) == PQ, ...
        abs(gc.gen(2, QG)-gc.gen(2, QMAX)) < 1e-10});

%% Electrical and state consistency. AC residuals use the extended station model.
names = {'shunt_pf', 'shunt_cpf', 'genq_cpf'};
for k = 1:length(names)
    name = names{k}; r = evidence.(name);
    check([name '.success'], r.success == 1, sprintf('success=%d', r.success));
    check([name '.solver_residual'], ...
        isfinite(r.convergence.max_mismatch) && ...
        r.convergence.max_mismatch <= r.convergence.tol, ...
        sprintf('mismatch=%.12g configured_tol=%.12g', ...
        r.convergence.max_mismatch, r.convergence.tol));
    ac = ext2int(r.ac);
    Y = makeYbus(ac.baseMVA, ac.bus, ac.branch);
    V = ac.bus(:, VM).*exp(1j*pi/180*ac.bus(:, VA));
    mismatch = V.*conj(Y*V) - makeSbus(ac.baseMVA, ac.bus, ac.gen);
    balance = norm(mismatch, Inf);
    check([name '.ac_balance'], isfinite(balance) && balance <= 1e-8, ...
        sprintf('extended AC nodal mismatch=%.12g pu', balance));
    active = r.vsc(:, c.VSC_STATUS) > 0;
    balance = max(abs(sum(r.vsc(active, [c.PCONV c.PDC c.PLOSS]), 2))) / r.baseMVA;
    check([name '.converter_balance'], isfinite(balance) && balance <= 1e-8, ...
        sprintf('converter balance=%.12g pu', balance));
    vdc = r.busdc(:, bdc.VDC);
    balance = norm(vdc.*(makeGdc(r.busdc,r.branchdc)*vdc) - ...
        r.busdc(:,bdc.PDC)/r.baseMVA, Inf);
    check([name '.dc_balance'], isfinite(balance) && balance <= 1e-8, ...
        sprintf('DC nodal power mismatch=%.12g pu', balance));
end

for pair = {sp, sc}
    r = pair{1};
    if isfield(r, 'cpf'), name = 'shunt_cpf'; else, name = 'shunt_pf'; end
    b = r.psse.swshunt.num(1, 10);
    fixed_bs = sw.bus(5, BS) - sw.psse.swshunt.num(1, 10);
    row = find(r.ac.bus(:, BUS_I) == 5, 1);
    check([name '.legal_state'], b >= -1e-8 && b <= 10+1e-8 && ...
        abs(b-round(b)) <= 1e-8, sprintf('BINIT=%.12g; legal grid=0:10', b));
    check([name '.state_sync'], ...
        abs(r.bus(5, BS)-fixed_bs-b) <= 1e-8 && ...
        abs(r.ac.bus(row, BS)-fixed_bs-b) <= 1e-8, ...
        sprintf('BS top/ac=%.12g/%.12g fixed+BINIT=%.12g', ...
        r.bus(5, BS), r.ac.bus(row, BS), fixed_bs+b));
    v = r.ac.bus(row, VM);
    check([name '.settled_voltage'], v >= 0.995-1e-5 && v <= 1.005+1e-5, ...
        sprintf('solved Vm5=%.12g; this fixture has reachable deadband', v));
end

% A binding limit is an electrical mode, not just a flag in a report.
q = gc.gen(2, QG); ctrl = gc.psse.genq.control;
check('genq.original_bounds', q >= gq.gen(2,QMIN)-0.01 && ...
    q <= gq.gen(2,QMAX)+0.01, sprintf('QG=%.12g original range=[-100,-20]', q));
check('genq.reported_binding_limit', ~ctrl.limited(2) || ...
    ((~ctrl.at_max(2) || abs(q-gq.gen(2,QMAX)) <= 0.01) && ...
     (~ctrl.at_min(2) || abs(q-gq.gen(2,QMIN)) <= 0.01)), ...
    sprintf('limited=%d at_max=%d QG=%.12g', ctrl.limited(2), ctrl.at_max(2), q));
check('genq.fixed_q_equation', abs(gc.gen(2,QMAX)-gc.gen(2,QMIN)) > 1e-8 || ...
    abs(q-gc.gen(2,QMAX)) <= 0.01, ...
    sprintf('matrix QMIN/QMAX/QG=%.12g/%.12g/%.12g', ...
    gc.gen(2,QMIN), gc.gen(2,QMAX), q));
check('genq.mode_consistency', ~ctrl.limited(2) || gc.bus(2,BT) == PQ, ...
    sprintf('single local generator: limited=%d bus_type=%d', ctrl.limited(2), gc.bus(2,BT)));
check('genq.pv_voltage_schedule', gc.bus(2,BT) ~= PV || ...
    abs(gc.bus(2,VM)-gc.gen(2,VG)) <= 1e-6, ...
    sprintf('PV Vm=%.12g VG=%.12g',gc.bus(2,VM),gc.gen(2,VG)));

% Expansion must preserve solved controls when an auxiliary model is returned.
% These diagnostic projections retain the existing solver and input settings.
for kind_cell = {'shunt', 'genq'}
    kind = kind_cell{1};
    f = cleanup_batch1_vsc_case(kind);
    raw = runpf_vsc_mtdc(f,opt);
    projection = mp.psse_unified_active_set('control_case_from_unified_result',raw);
    auxiliary = runpf_psse(projection,rmfield(opt,'vsc_mtdc'));
    before = int2ext(auxiliary.task.dm.source);
    if strcmp(kind,'shunt')
        row = find(before.bus(:,BUS_I)==5,1);
        check('expansion.shunt_state', abs(auxiliary.bus(5,BS)-before.bus(row,BS)) <= 1e-8, ...
            sprintf('BS5 before/after expansion=%.12g/%.12g',before.bus(row,BS),auxiliary.bus(5,BS)));
    else
        row = find(before.bus(:,BUS_I)==2,1);
        check('expansion.genq_mode', auxiliary.bus(2,BT)==before.bus(row,BT), ...
            sprintf('bus2 type before/after expansion=%d/%d',before.bus(row,BT),auxiliary.bus(2,BT)));
    end
    evidence.auxiliary.(kind) = auxiliary;
    evidence.before_expansion.(kind) = before;
end

% PF and CPF at identical loading and frozen, explicitly selected legal states.
for b = [0 6 9 10]
    f = sw; f.bus(5, BS) = b; f.psse.swshunt.num(1,10) = b;
    f.psse.system.solver.SWSHNT = 0;
    t = f; t.bus(:,[PD QD]) = 1.02*f.bus(:,[PD QD]);
    r = runcpf_psse(f, t, cpopt);
    final = f; final.bus(:,[PD QD]) = ...
        f.bus(:,[PD QD]) + r.cpf.lam(end)*(t.bus(:,[PD QD])-f.bus(:,[PD QD]));
    p = runpf_psse(final, opt);
    dv = max(abs(r.bus(:,VM)-p.ac.bus(1:size(f.bus,1),VM)));
    check(sprintf('matched_fixed_B%d',b), r.success && p.success && dv <= 1e-6, ...
        sprintf('CPF/PF success=%d/%d max dVm=%.12g pu',r.success,p.success,dv));
    check(sprintf('disabled_B%d',b), abs(p.ac.bus(5,BS)-b) <= 1e-8 && ...
        abs(r.bus(5,BS)-b) <= 1e-8, 'disabled automatic adjustment preserves chosen state');
    evidence.fixed_states(b+1).pf = p;
    evidence.fixed_states(b+1).cpf = r;
end

% Focused direction and fixed-shunt tests use measured voltages, not PSS/E targets.
f = sw; f.bus(5,BS) = 7; f.psse.swshunt.num(1,10) = 2; % fixed part = 5
for v = [0.98 1.00 1.02]
    measured = f.bus; measured(5,VM) = v;
    [u, ~] = mp.psse_unified_control_update(f, measured);
    b = u.psse.swshunt.num(1,10);
    if v < 0.995, correct = b > 2;
    elseif v > 1.005, correct = b < 2;
    else, correct = b == 2;
    end
    check(sprintf('direction_%.2f',v), correct && abs(u.bus(5,BS)-5-b) <= 1e-8, ...
        sprintf('Vm=%.3f BINIT=%.12g fixed part=%.12g',v,b,u.bus(5,BS)-b));
end
for b = [0 10]
    f = sw; f.bus(5,BS) = b; f.psse.swshunt.num(1,10) = b;
    measured = f.bus;
    if b == 0, measured(5,VM) = 1.02; else, measured(5,VM) = 0.98; end
    [u, rep] = mp.psse_unified_control_update(f, measured);
    check(sprintf('saturated_B%d',b), u.bus(5,BS) == b && ...
        u.psse.swshunt.num(1,10) == b && rep.blocked_violations > 0, ...
        'outward request preserves physical bound and reports blocked regulation');
end
f = sw; f.psse.swshunt.num(1,7) = 4; % explicitly regulate remote bus 4
measured = f.bus; measured(5,VM) = 1.00; measured(4,VM) = 0.98;
[u, ~] = mp.psse_unified_control_update(f, measured);
check('remote_measurement', u.psse.swshunt.num(1,10) > 0, ...
    'low remote Vm4 requests capacitance even when local Vm5 is in band');
f = sw; f.psse.swshunt.num(1,4) = 0;
measured = f.bus; measured(5,VM) = 0.98;
[u, ~] = mp.psse_unified_control_update(f, measured);
check('out_of_service', u.bus(5,BS) == 0 && u.psse.swshunt.num(1,10) == 0, ...
    'out-of-service shunt neither adjusts nor injects');

evidence.elapsed_seconds = toc(accept_clock);
save(fullfile(outdir, 'acceptance.mat'), 'checks', 'evidence');
fid = fopen(fullfile(outdir, 'acceptance.json'), 'w');
assert(fid >= 0, 'Cannot write acceptance report');
file_cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(struct('checks',checks,'legacy',evidence.legacy), ...
    'PrettyPrint',true));
clear file_cleanup;
t_begin(length(checks), quiet);
for k = 1:length(checks)
    t_ok(checks(k).passed, [checks(k).id ': ' checks(k).detail]);
end
t_end;
fprintf('Numerical fixtures and checks elapsed %.3f seconds.\n', evidence.elapsed_seconds);

    function check(id, passed, detail)
        checks(end+1) = struct('id', id, 'passed', logical(passed), 'detail', detail);
    end
end
