function [checks, evidence] = t_ultc_acceptance_batch3(quiet, outdir)
%T_ULTC_ACCEPTANCE_BATCH3 Physical, adapter and declared tap-policy coverage.
% Reuses case2_psse_ultc_ntp10_fixture and the existing RAW TAB fixtures.
% Prescribed voltage passes test decisions; independent PF tests physics.
if nargin < 1, quiet = 0; end
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 2, outdir = tempname(fullfile(root,'outputs')); end
assert(~exist(outdir,'dir'), 'Use a fresh output directory'); mkdir(outdir);
opt = mpoption('verbose',0,'out.all',0);
checks = struct('id',{},'passed',{},'detail',{});
evidence = struct('options',opt,'matlab',version);

%% Terminal and remote direction, including reversed electrical orientation.
for mode = 1:6
    f = fixture();
    if mode <= 2
        f.psse.xfmr.two.num(40) = (-1)^mode*2;
        direction = -1;
    elseif mode <= 4
        f.branch(1,1:2) = [2 1]; f.psse.xfmr.two.num(1:2) = [2 1];
        f.psse.xfmr.two.num(40) = (-1)^mode*2;
        direction = (-1)^mode;
    else
        f.bus(3,:) = f.bus(2,:); f.bus(2,3:4) = 0; f.bus(3,1) = 3;
        f.branch(2,:) = f.branch(1,:); f.branch(2,1:2) = [2 3];
        f.branch(2,9) = 0;
        f.psse.xfmr.two.num(40) = (-1)^mode*3;
        direction = -(-1)^mode;
        if mode == 5
            f.branch(1,1:2) = [2 1]; f.psse.xfmr.two.num(1:2) = [2 1];
        end
    end
    s = mp.psse_xfmr_states(f); v = ones(size(f.bus,1),1); v(s.reg_bus_idx) = 0.90;
    [a,u] = both(f,v);
    label = sprintf('terminal%d',mode);
    check([label '.step'], all(abs(a.current_tap-(1+0.05*direction)) < 1e-10) && ...
        max(abs(u.branch(s.branch_idx,9)-a.current_tap)) < 1e-10, 'both paths take the declared adjacent step');
    % Negative own-terminal CONT declares reverse action. Test its interface
    % explicitly without claiming it raises voltage on this radial topology.
    if mode ~= 3
        p0 = runpf(f,opt); p1 = runpf(u,opt);
        check([label '.physical_direction'], p0.success && p1.success && ...
            p1.bus(s.reg_bus_idx,8)>p0.bus(s.reg_bus_idx,8), 'electrical re-solve raises the regulated voltage');
        balance(label,p1);
    end
    evidence.(label) = struct('input',f,'ac_state',a,'unified',u);
end

%% Nonconsecutive identifiers and reordered unified measurements.
f = fixture(); f.bus(:,1) = [91;17]; f.gen(:,1) = 91;
f.branch(:,1:2) = [91 17]; f.psse.xfmr.two.num([1 2 40]) = [91 17 -17];
b = f.bus([2 1],:); b(:,8) = [0.90;1.10];
[u,~] = mp.psse_unified_control_update(f,b);
check('mapping.remote_identity', abs(u.branch(1,9)-0.95)<1e-10, 'measurement joins by bus identity, not row');
p = runpf_psse(f,opt); balance('mapping',p);
check('mapping.export', isequal(p.bus(:,1),f.bus(:,1)) && abs(p.branch(1,9)-0.95)<1e-10, 'AC internal mapping returns original identifiers');
evidence.mapping = p;

%% CW=2 kV conversion plus TAB impedance correction on both paths.
f = fixture(); f.psse.xfmr.two.num([5 24 41 42 51]) = [2 230 253 207 115];
f.psse.xfmr.two.num(46) = 1; f.psse.xfmr.two.tab_applied = true;
f.psse.xfmr.two.nominal_rx = f.branch(:,3:4);
f.psse.impcor = struct('num',[1 .9 .9 0;1 1.1 1.1 0]);
[a,u] = both(f,[1;.90]);
check('cw2.raw', abs(a.current_raw-218.5)<1e-10 && ...
    abs(u.psse.xfmr.two.num(24)-218.5)<1e-10, 'CW=2 writes kV WINDV for the selected per-unit tap');
check('cw2.tab', max(abs(u.branch(1,[3 4 9])-[.0095 .095 .95]))<1e-10, 'TAB scales nominal impedance using per-unit winding ratio');
p = runpf_psse(f,opt); balance('cw2',p); evidence.cw2 = p;
for cw = 1:2
    names = {'suite_u_ultc_3w_tab.raw','suite_u_ultc_3w_tab_cw2.raw'};
    raw = fullfile(root,'tests','fixtures','controls','legacy_regression','psse_validation_suite',names{cw});
    f = psse2mpc(raw,0,34); s = mp.psse_xfmr_states(f);
    v = ones(size(f.bus,1),1); v(s.reg_bus_idx(s.controllable)) = .8;
    [a,u] = both(f,v);
    check(sprintf('three_winding%d.interface',cw), ...
        max(abs(a.current_tap-u.branch(s.branch_idx,9)))<1e-10, 'three-winding CW/TAB candidates agree between paths');
    p = runpf_psse(f,opt); balance(sprintf('three_winding%d',cw),p);
    evidence.(sprintf('three_winding%d',cw)) = p;
end

%% Eligibility and deadband: no automatic move for each disabled condition.
for mode = 1:7
    f = fixture();
    switch mode
        case 1, f.psse.system.solver.ACTAPS = 0;
        case 2, f.psse.xfmr.two.num(39) = 0;
        case 3, f.psse.xfmr.two.num(39) = -1;
        case 4, f.psse.xfmr.two.num(12) = 0;
        case 5, f.branch(1,11) = 0;
        case 6, f.psse.xfmr.two.num(40) = 0;
        case 7, f.psse.xfmr.two.num(45) = 1;
    end
    [a,u] = both(f,[1;.9]);
    check(sprintf('disabled%d',mode), a.current_tap==1 && u.branch(1,9)==1, 'disabled device stays fixed in both paths');
end
for v = [.97-1e-5,1.03+1e-5,1]
    [a,u] = both(fixture(),[1;v]);
    check(sprintf('deadband_%.8f',v), a.current_tap==1 && u.branch(1,9)==1, 'deadband and tolerance edges are inclusive');
end

%% Both physical tap bounds remain distinct from lockout and failure.
for bound = [.9 1.1]
    f = fixture(); f.branch(1,9) = bound; f.psse.xfmr.two.num(24) = bound;
    if bound<1, v=.8; else, v=1.2; end
    [a,u,report] = both(f,[1;v]);
    check(sprintf('bound%.1f',bound), a.current_tap==bound && u.branch(1,9)==bound && ...
        a.blocked_violations==1 && report.xfmr_blocked_violations==1 && ...
        ~any(a.locked_out) && ~any(u.psse.xfmr.control_locked_out) && ~a.control_failed, ...
        'saturation is a physical bound, not a numerical or implicit lock');
end

%% Persisted study/numerical locks and explicit unified lockout are not lost.
for mode = 1:3
    f = fixture();
    switch mode
        case 1
            f.psse.xfmr.control_study_locked_rows = 1;
            f.psse.xfmr.control_study_lock_label = 'explicit acceptance fixture';
        case 2
            f.psse.xfmr.control_locked_out = true;
            f.psse.xfmr.control.rebuild_rejected = 1;
            f.psse.xfmr.control.rebuild_rejected_rows = 1;
        case 3
            f.psse.control_lockout.xfmr = true;
    end
    [a,u] = both(f,[1;.9]);
    check(sprintf('lock%d.unified',mode), u.branch(1,9)==1 && u.psse.xfmr.control_locked_out, 'declared lock survives unified handoff and prevents movement');
    if mode<=2
        check(sprintf('lock%d.ac',mode), a.current_tap==1 && a.locked_out && ...
            a.locked_violations==1 && a.blocked_violations==0, 'AC reports locked voltage separately from physical saturation');
    end
    if mode==1
        check('lock.study_provenance',u.psse.xfmr.control.study_locked==1 && ...
            strcmp(u.psse.xfmr.control.study_lock_label,'explicit acceptance fixture') && ...
            u.psse.xfmr.control.rebuild_rejected==0,'declared study lock retains its label and is not reported as numerical rejection');
    elseif mode==2
        check('lock.numerical_provenance',u.psse.xfmr.control.rebuild_rejected==1 && ...
            isequal(u.psse.xfmr.control.rebuild_rejected_rows,1) && ...
            u.psse.xfmr.control.study_locked==0,'numerical lock retains rejected rows and is not reported as a study lock');
    end
    evidence.(sprintf('lock%d',mode)) = struct('input',f,'ac_state',a,'unified',u);
end

%% Interacting parallel transformers: synchronous steps and permutation.
f = fixture(); f.branch = [f.branch;f.branch];
f.psse.xfmr.two.num = repmat(f.psse.xfmr.two.num,2,1);
f.psse.xfmr.two.txt = repmat(f.psse.xfmr.two.txt,2,1);
f.psse.xfmr.two.branch_idx = [1;2];
[a,u] = both(f,[1;.9]);
check('interaction.simultaneous', all(abs(a.current_tap-.95)<1e-10) && ...
    all(abs(u.branch(:,9)-.95)<1e-10), 'all eligible devices step from the same solved voltage');
f.psse.xfmr.two.branch_idx = [2;1]; [~,rev] = both(f,[1;.9]);
check('interaction.order', isequal(rev.branch,u.branch), 'permuting device metadata does not introduce sequential voltage updates');
p = runpf_psse(f,opt); balance('interaction',p); evidence.interaction = p;

%% Actual cycling uses AC history; unified direct pass remains memoryless.
f = fixture(); f.psse.xfmr.two.num([43 44]) = [1.001 .999];
p = runpf_psse(f,opt); evidence.cycle = p;
check('cycle.detected', p.psse.xfmr.control.cycle_detected && ...
    p.psse.xfmr.control.cycle_resolved && ~any(p.psse.xfmr.control_locked_out), 'AC resolves a repeated grid state without inventing a lock');
balance('cycle',p);
[~,u] = both(f,[1;.9]); [~,u2] = both(u,[1;1.1]);
check('cycle.unified_pass', abs(u2.branch(1,9)-1)<1e-10 && ...
    ~u2.psse.xfmr.control.cycle_detected, 'direct unified pass can reverse; solver layer owns cycling');

%% Existing numerical replay guard: pathological rejected candidate is restored.
f = fixture(); s = mp.psse_xfmr_states(f); target = s;
target.current_tap = 1e6; target.current_raw = 1e6;
a = mp.psse_xfmr_guard_candidate(f,s,target,opt); evidence.guard = a;
check('numerical.rejection', a.current_tap==1 && a.locked_out && ...
    a.rebuild_rejected==1 && isequal(a.rebuild_rejected_rows,1) && ...
    ~a.at_min && ~a.at_max && a.blocked_violations==0, 'failed electrical replay restores state and records numerical cause, not saturation');

save(fullfile(outdir,'ultc.mat'),'checks','evidence');
fid=fopen(fullfile(outdir,'ultc.json'),'w'); fprintf(fid,'%s\n',jsonencode(checks,'PrettyPrint',true)); fclose(fid);
t_begin(length(checks),quiet);
for k=1:length(checks), t_ok(checks(k).passed,[checks(k).id ': ' checks(k).detail]); end
t_end;

    function check(id,passed,detail)
        checks(end+1)=struct('id',id,'passed',logical(passed),'detail',detail);
    end
    function balance(label,p)
        ai=ext2int(p); y=makeYbus(ai.baseMVA,ai.bus,ai.branch);
        solved_voltage=ai.bus(:,8).*exp(1j*pi/180*ai.bus(:,9));
        residual=norm(solved_voltage.*conj(y*solved_voltage)-makeSbus(ai.baseMVA,ai.bus,ai.gen),Inf);
        check([label '.balance'], p.success && residual<=1e-8, sprintf('success and AC residual %.12g pu',residual));
    end
    function [s,u,r] = both(f,v)
        dm=struct('source',f,'elements',struct('bus',struct('tab',struct('vm',v))));
        task=struct('dmc',[],'data_model_build',@(mpc,varargin) mpc);
        [~,s]=mp.psse_xfmr_control(task,[],[],dm,opt,{},[]);
        b=f.bus; b(:,8)=v; [u,r]=mp.psse_unified_control_update(f,b);
    end
end

function f = fixture()
f=case2_psse_ultc_ntp10_fixture(100,50);
f.psse.xfmr.two.num([43 44 45])=[1.03 .97 5];
end
