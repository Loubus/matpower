function probe_vsc
% Read-only solver investigation; output path is this new evidence folder.
outdir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(outdir));
addpath(fullfile(root, 'tests', 'fixtures', 'controls'));
[~, ~, ~, ~, ~, BT, PD, QD, ~, BS, ~, VM] = idx_bus;
[~, ~, QG, QMAX, QMIN] = idx_gen;
opt = mpoption('out.all', 0, 'verbose', 0);
opt.vsc_mtdc.method = 'unified';
sw = cleanup_batch1_vsc_case('shunt');
gq = cleanup_batch1_vsc_case('genq');
[sp, prep, op] = mp.psse_prepare_case(sw, mp.psse_mpx_options(opt), 'pf');
rawopt = opt;
rawopt.vsc_mtdc.psse_aware = 0; % diagnostic electrical solution, no control decisions
raw = runpf_vsc_mtdc(sp, rawopt);
[direct_input, di] = mp.psse_unified_control_update(sp, raw.bus);
[direct_solved, ds] = mp.psse_unified_control_update(sp, raw.ac.bus);
pf = runpf_psse(sw, opt);
t = sw; t.bus(:, [PD QD]) = 1.02*t.bus(:, [PD QD]);
cpopt = mpoption(opt, 'cpf.stop_at', 0.2, 'cpf.step', 0.1);
cs = runcpf_psse(sw, t, cpopt);
t = gq; t.bus(:, [PD QD]) = 1.02*t.bus(:, [PD QD]);
cg = runcpf_psse(gq, t, cpopt);
gp = runpf_psse(gq, opt);
auxin = mp.psse_unified_active_set('control_case_from_unified_result', gp);
auxopt = rmfield(opt, 'vsc_mtdc');
aux = runpf_psse(auxin, auxopt);
free_case = rmfield(gq, 'psse');
free_pf = runpf_vsc_mtdc(free_case, rawopt);
locked_case = free_case;
locked_case.bus(2,BT) = 1;
locked_case.gen(2,[QG QMAX QMIN]) = -20;
locked_pf = runpf_vsc_mtdc(locked_case, rawopt);
fprintf('SHUNT raw input/ac Vm5: %.12g %.12g\n', raw.bus(5,VM), raw.ac.bus(5,VM));
fprintf('SHUNT direct input/solved changed=%d/%d BS=%.12g/%.12g\n', di.changed, ds.changed, direct_input.bus(5,BS), direct_solved.bus(5,BS));
fprintf('SHUNT PF success=%d changed=%d BS(top/ac)=%.12g/%.12g BINIT=%.12g Vm(ac)=%.12g\n', pf.success, pf.convergence.psse_controls.changed, pf.bus(5,BS), pf.ac.bus(5,BS), pf.psse.swshunt.num(1,10), pf.ac.bus(5,VM));
fprintf('SHUNT CPF success=%d BS=%.12g BINIT=%.12g Vm=%.12g\n',cs.success,cs.bus(5,BS),cs.psse.swshunt.num(1,10),cs.bus(5,VM));
fprintf('GENQ CPF success=%d bus2=%d QG=%.12g limits=[%.12g %.12g] Vm=%.12g\n',cg.success,cg.bus(2,BT),cg.gen(2,QG),cg.gen(2,QMIN),cg.gen(2,QMAX),cg.bus(2,VM));
fprintf('GENQ PF success=%d top/ac bus2=%d/%d QG=%.12g/%.12g\n',gp.success,gp.bus(2,BT),gp.ac.bus(2,BT),gp.gen(2,QG),gp.ac.gen(2,QG));
disp(cg.psse.genq.control);
fprintf('GENQ auxiliary bus2=%d QG=%.12g limits=[%.12g %.12g]\n',aux.bus(2,BT),aux.gen(2,QG),aux.gen(2,QMIN),aux.gen(2,QMAX));
fprintf('GENQ diagnostic free QG=%.12g Vm=%.12g; explicitly locked QG=%.12g Vm=%.12g success=%d/%d\n', ...
    free_pf.ac.gen(2,QG),free_pf.ac.bus(2,VM),locked_pf.ac.gen(2,QG),locked_pf.ac.bus(2,VM),free_pf.success,locked_pf.success);
save(fullfile(outdir, 'probe.mat'));
end
