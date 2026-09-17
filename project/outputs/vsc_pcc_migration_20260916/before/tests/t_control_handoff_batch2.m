function [checks, evidence] = t_control_handoff_batch2(quiet, outdir)
%T_CONTROL_HANDOFF_BATCH2 Result serialization and physical active-set tests.
% No expected-failure skips. Use a fresh output directory and initialize the
% project before running. Policy choices and original capability limits stay
% unchanged; synthetic expansion tests prescribe solved states explicitly.
if nargin < 1, quiet = 0; end
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 2, outdir = tempname(fullfile(root, 'outputs')); end
assert(~exist(outdir, 'dir'), 'Use a fresh output directory');
mkdir(outdir);
oldpath = path;
cleanup = onCleanup(@() path(oldpath));
addpath(fullfile(root, 'tests', 'fixtures', 'controls'));
[PQ, PV, REF, ~, BI, BT, PD, QD, GS, BS, ~, VM, VA] = idx_bus;
[GB, PG, QG, QMAX, QMIN, VG, ~, ON] = idx_gen;
c = idx_vsc;
opt = mpoption('verbose', 0, 'out.all', 0);
opt.vsc_mtdc.method = 'unified';
checks = struct('id', {}, 'passed', {}, 'detail', {});
evidence = struct('options', opt, 'matlab', version);

%% Export with nonconsecutive buses, unsorted generators and an offline row.
f = loadcase('case5_vsc_mtdc_beerten');
ids = f.bus(:, BI); ext = [41; 17; 83; 29; 65];
f.bus(:, BI) = ext;
for col = 1:2
    [~, k] = ismember(f.branch(:, col), ids);
    f.branch(:, col) = ext(k);
end
[~, k] = ismember(f.gen(:, GB), ids); f.gen(:, GB) = ext(k);
[~, k] = ismember(f.vsc(:, c.VSC_BUS), ids); f.vsc(:, c.VSC_BUS) = ext(k);
f.gen = f.gen([2 1 2], :); f.gen(3, ON) = 0;
f.gencost = repmat([2 0 0 2 1 0], 3, 1);
r = runpf_vsc_mtdc(f, opt); evidence.export_input = f; evidence.export = r;
physical('export', r);
ng = size(f.gen, 1);
proxy_vsc = find(f.vsc(:,c.VSC_STATUS) > 0 & ...
    f.vsc(:,c.AC_MODE) ~= c.VSC_AC_Q & f.vsc(:,c.AC_MODE) ~= c.VSC_AC_PQ);
nv = length(proxy_vsc);
check('export.row_count', size(r.ac.gen, 1) == ng+nv, 'all original and active proxy rows retained');
check('export.original_identity', isequal(r.ac.gen(1:ng, GB), f.gen(:, GB)) && ...
    r.ac.gen(3, ON) == 0, 'original order and offline row retained');
roundtrip = int2ext(ext2int(r.ac, 1));
check('export.roundtrip', max(abs(roundtrip.gen(:)-r.ac.gen(:))) < 1e-8, ...
    'external/internal round trip preserves generator results including proxies');
check('export.proxy_power', max(abs(r.ac.gen(ng+(1:nv), [PG QG]) - ...
    r.vsc(proxy_vsc, [c.PAC c.QAC])), [], 'all') < 1e-8, 'proxy injections equal solved converter AC injections');
check('export.cost_identity', isequal(r.ac.gencost(1:ng,:), f.gencost) && ...
    size(r.ac.gencost,1) == ng+nv, 'original P costs retain identity and proxy has its own zero cost row');
f.gencost = [f.gencost; 2 0 0 2 2 0; 2 0 0 2 3 0; 2 0 0 2 4 0];
f.gentype = {'original2'; 'original1'; 'offline'}; f.genfuel = {'x';'y';'z'};
rcost = runpf_vsc_mtdc(f,opt); roundtrip = int2ext(ext2int(rcost.ac, 1));
evidence.export_pq_cost = rcost;
check('export.pq_cost_identity', isequal(roundtrip.gencost([1:ng ng+nv+(1:ng)],:),f.gencost) && ...
    size(roundtrip.gencost,1) == 2*(ng+nv) && isequal(roundtrip.gentype(1:ng),f.gentype) && ...
    isequal(roundtrip.genfuel(1:ng),f.genfuel), 'P/Q cost blocks and generator labels survive proxy round trip');

%% VM is initialization; online PV/REF VG supplies the voltage constraint.
f = loadcase('case5_vsc_mtdc_beerten');
f.bus(:, VM) = 0.97; f.bus(:, VA) = 0;
r = runpf_vsc_mtdc(f, opt); evidence.voltage_initialization = r;
physical('voltage_initialization', r);
[~, b] = ismember(f.gen(:, GB), r.ac.bus(:, BI));
check('voltage.schedule', max(abs(r.ac.bus(b, VM)-f.gen(:, VG))) < 1e-6, ...
    'PV/REF solved voltages use unchanged generator schedules');
check('voltage.input', all(f.bus(:, VM) == 0.97), 'input initialization was not overwritten');

%% Independently enumerate the legal shunt grid on the full AC/DC equations.
% The historical B=9 snapshot came from a projection missing an injection.
% This proves the first reachable state from B=0 without using the controller.
f = cleanup_batch1_vsc_case('shunt');
grid = 0:10; grid_vm = zeros(size(grid)); grid_ok = false(size(grid));
for k = 1:length(grid)
    a = f; a.bus(5,BS) = grid(k); a.psse.swshunt.num(1,10) = grid(k);
    a = runpf_vsc_mtdc(a, opt);
    grid_vm(k) = a.ac.bus(5,VM); grid_ok(k) = a.success;
end
p = runpf_psse(f, opt);
first = find(grid_vm >= 0.995-1e-5 & grid_vm <= 1.005+1e-5, 1);
evidence.shunt_grid = struct('B',grid,'Vm',grid_vm,'success',grid_ok,'controlled',p);
check('shunt.grid_solved', all(grid_ok), 'every legal fixed candidate solved on the full model');
check('shunt.first_reachable', ~isempty(first) && p.ac.bus(5,BS) == grid(first), ...
    'accepted automatic state is the first legal state reaching the deadband from zero');
check('shunt.solved_measurement', f.bus(5,VM) == 1 && grid_vm(1) < 0.995-1e-5 && ...
    p.convergence.psse_controls.changed, 'flat input is in-band, but solved low voltage causes adjustment');

%% Both topology adapters conserve totals and restore device-local changes.
for kind = {'branch', 'swdev'}
    name = kind{1}; f = expansion_fixture();
    collapse = str2func(['mp.psse_' name '_collapse']);
    expand = str2func(['mp.psse_' name '_expand']);
    [a, state] = collapse(f);
    check([name '.collapsed'], state.active && size(a.bus, 1) == 2, 'fixture actually merged 11 and 37');
    a.bus(1, [PD QD BS]) = a.bus(1, [PD QD BS]) + [7 2 3];
    a.psse.swshunt.num(1, 10) = 5;
    a.bus(1, BT) = PQ; a.gen(2, [QG QMAX QMIN]) = -20;
    a.bus(:, VM) = [0.99; 1.03];
    e = expand(a, state);
    evidence.expansion.(name) = struct('input', f, 'solved', a, 'expanded', e);
    check([name '.totals'], max(abs(sum(e.bus(:, [PD QD GS BS])) - ...
        sum(a.bus(:, [PD QD GS BS])))) < 1e-8, 'expanded totals equal solved aggregate once');
    check([name '.local_shunt'], e.bus(2, BS) == f.bus(2, BS)+3 && ...
        e.bus(1, BS) == f.bus(1, BS), 'switched increment restored at original device bus 37');
    check([name '.fixed_shunt'], e.bus(2, BS)-e.psse.swshunt.num(1,10) == ...
        f.bus(2, BS)-f.psse.swshunt.num(1,10), 'fixed contribution preserved');
    check([name '.load_delta'], isequal(e.bus(:, [PD QD]), ...
        f.bus(:, [PD QD])+[7 2; 0 0; 0 0]), 'unattributed aggregate load delta placed once at representative');
    check([name '.modes'], isequal(e.bus(:, BT), [PQ; PQ; REF]) && ...
        isequal(e.gen(:, GB), f.gen(:, GB)), 'binding PQ mode and original generator identities survive');
    check([name '.voltage'], isequal(e.bus(:, VM), [0.99; 0.99; 1.03]), 'merged buses inherit solved voltage');
    a.bus(1, BT) = PV; a.gen(2, [QMAX QMIN]) = [100 -100];
    e = expand(a, state);
    check([name '.free_mode'], isequal(e.bus(:, BT), [PQ; PV; REF]), 'free voltage controller restored at its original bus');
end

%% Original GENQ fixture is interior; increased demand crosses its same bound.
f = cleanup_batch1_vsc_case('genq'); target = f;
light = f; light.bus(:,[PD QD]) = 1.02*f.bus(:,[PD QD]);
lc = runcpf_psse(f,light,mpoption(opt,'cpf.stop_at',0.2,'cpf.step',0.1));
matched = f; matched.bus(:,[PD QD]) = f.bus(:,[PD QD]) + ...
    lc.cpf.lam(end)*(light.bus(:,[PD QD])-f.bus(:,[PD QD]));
lp = runpf_vsc_mtdc(matched,opt);
evidence.interior = struct('cpf',lc,'independent_pf',lp);
check('genq.interior_reference', lp.success && lc.success && ...
    lp.ac.gen(2,QG) > f.gen(2,QMIN) && lp.ac.gen(2,QG) < f.gen(2,QMAX) && ...
    abs(lp.ac.gen(2,QG)-lc.gen(2,QG)) <= 0.01 && ...
    max(abs(lp.ac.bus(:,VM)-lc.ac.bus(:,VM))) <= 1e-6 && ~lc.psse.genq.control.limited(2), ...
    'independent full-model PV solve validates interior Q without clamping to a snapshot');
target.bus(:, [PD QD]) = 1.25*f.bus(:, [PD QD]);
cop = mpoption(opt, 'cpf.stop_at', 1, 'cpf.step', 0.1);
r = runcpf_psse(f, target, cop); p = runpf_psse(target, opt);
evidence.crossing = struct('base', f, 'target', target, 'cpf', r, 'pf', p);
physical('crossing.cpf', r); physical('crossing.pf', p);
for item = {r, p}
    a = item{1}; if isfield(a, 'cpf'), label = 'cpf'; else, label = 'pf'; end
    check(['crossing.' label '.binding'], abs(a.gen(2,QG)-f.gen(2,QMAX)) <= 0.01 && ...
        a.ac.bus(2,BT) == PQ && a.psse.genq.control.limited(2) && ...
        a.psse.genq.control.at_max(2), 'original -20 MVAr upper bound agrees with PQ equation and report');
    expected_load = target.bus(:,[PD QD]);
    if isfield(a,'cpf')
        expected_load = f.bus(:,[PD QD]) + a.cpf.lam(end)* ...
            (target.bus(:,[PD QD])-f.bus(:,[PD QD]));
    end
    check(['crossing.' label '.demand'], max(abs(a.ac.bus(1:5,[PD QD]) - ...
        expected_load), [], 'all') < 1e-8, 'accepted model retains demands at its reported lambda');
end
check('crossing.event', any(strcmp({r.cpf.events.name}, 'PSSE_CONTROL') & ...
    [r.cpf.events.k] > 0), 'binding change is recorded after the initial CPF point');
check('crossing.pf_cpf', max(abs(r.ac.bus(:,VM)-p.ac.bus(:,VM))) <= 1e-6, 'independent endpoint PF matches CPF');
qtrace = squeeze(r.cpf.gen(2,QG,:)); btrace = squeeze(r.cpf.bus(2,BT,:));
vtrace = squeeze(r.cpf.bus(2,VM,:));
check('crossing.accepted_trace', all(qtrace >= f.gen(2,QMIN)-0.01 & qtrace <= f.gen(2,QMAX)+0.01) && ...
    all(abs(qtrace(btrace == PQ)-f.gen(2,QMAX)) <= 0.01) && ...
    all(abs(vtrace(btrace == PV)-f.gen(2,VG)) <= 1e-6), 'every accepted CPF point respects original Q limits and its active equation');
cop = mpoption(cop, 'cpf.step', 0.05);
r2 = runcpf_psse(f, target, cop); evidence.crossing.half_step = r2;
physical('crossing.half_step', r2);
check('crossing.step_sensitivity', max(abs(r.ac.bus(:,VM)-r2.ac.bus(:,VM))) <= 1e-6 && ...
    abs(r2.gen(2,QG)-f.gen(2,QMAX)) <= 0.01, 'halved CPF step preserves endpoint state and bound');
auxcase = mp.psse_unified_active_set('control_case_from_unified_result', r);
aux = runpf_psse(auxcase, rmfield(opt, 'vsc_mtdc')); evidence.crossing.auxiliary = aux;
check('crossing.auxiliary_load', max(abs(aux.bus(1:5,[PD QD])-r.ac.bus(1:5,[PD QD])), [], 'all') < 1e-8, ...
    'repeated auxiliary solve does not replay base load cache');
check('crossing.auxiliary_mode', aux.bus(2,BT) == PQ && aux.psse.genq.control.limited(2) && ...
    abs(aux.gen(2,QG)-f.gen(2,QMAX)) <= 0.01, 'repeated auxiliary solve retains accepted binding mode');

save(fullfile(outdir, 'handoff.mat'), 'checks', 'evidence');
fid = fopen(fullfile(outdir, 'handoff.json'), 'w');
fprintf(fid, '%s\n', jsonencode(checks, 'PrettyPrint', true)); fclose(fid);
t_begin(length(checks), quiet);
for k = 1:length(checks), t_ok(checks(k).passed, [checks(k).id ': ' checks(k).detail]); end
t_end;

    function check(id, passed, detail)
        checks(end+1) = struct('id',id,'passed',logical(passed),'detail',detail);
    end
    function physical(name, a)
        check([name '.success'], a.success == 1 && ...
            a.convergence.max_mismatch <= a.convergence.tol, 'success and configured nonlinear residual');
        ai = ext2int(a.ac); y = makeYbus(ai.baseMVA, ai.bus, ai.branch);
        v = ai.bus(:,VM).*exp(1j*pi/180*ai.bus(:,VA));
        residual = norm(v.*conj(y*v)-makeSbus(ai.baseMVA,ai.bus,ai.gen),Inf);
        check([name '.ac_balance'], residual <= 1e-8, sprintf('independent AC mismatch %.12g pu',residual));
        residual = max(abs(sum(a.vsc(:,[c.PAC c.PDC c.PLOSS]),2)))/a.baseMVA;
        check([name '.converter_balance'], residual <= 1e-8, sprintf('converter mismatch %.12g pu',residual));
    end
    function a = expansion_fixture()
        a = loadcase('case9'); a.bus = a.bus(1:3,:);
        a.bus(:,BI) = [11;37;90]; a.bus(:,BT) = [PQ;PV;REF];
        a.bus(:,[PD QD GS BS]) = [10 3 1 4;20 5 2 9;0 0 0 0];
        a.gen(:,GB) = [11;37;90]; a.gen(:,ON) = [0;1;1];
        a.gen(:,[QMAX QMIN]) = repmat([100 -100],3,1);
        a.branch = a.branch(1:2,:); a.branch(:,1:2) = [11 37;37 90];
        a.branch(:,3:5) = [0 0 0;0.01 0.1 0]; a.branch(:,9:10) = 0;
        sw = cleanup_batch1_vsc_case('shunt'); a.psse = sw.psse;
        a.psse.swshunt.num(1,1) = 37; a.psse.swshunt.num(1,10) = 2;
        a.psse.swdev = struct('branch_idx',1,'status',1,'x',0,'f_bus_idx',1,'t_bus_idx',2);
    end
end
