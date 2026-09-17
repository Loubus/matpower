function [checks,evidence] = t_swshunt_acceptance_batch4(quiet,outdir)
%T_SWSHUNT_ACCEPTANCE_BATCH4 Physical shunt decisions and adapter boundaries.
if nargin<1, quiet=0; end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<2, outdir=tempname(fullfile(root,'outputs')); end
assert(~exist(outdir,'dir'),'Use a fresh output directory'); mkdir(outdir);
opt=mpoption('verbose',0,'out.all',0);
checks=struct('id',{},'passed',{},'detail',{});
evidence=struct('options',opt,'matlab',version);

%% Mixed inductive/capacitive blocks: adjacency is ordered by susceptance.
for b=[-20 -10 0 10 20 30]
    for direction=[-1 1]
        f=fixture(); f.psse.swshunt.num(10)=b; f.bus(2,6)=3+b;
        v=1-.1*direction; [a,u]=both(f,[1;v]);
        expected=min(max(b+10*direction,-20),30);
        tag=sprintf('grid_%g_%g',b,direction);
        check(tag,a.current_b==expected && u.psse.swshunt.num(10)==expected, ...
            'both adapters take one adjacent legal mixed-sign step or retain a bound');
        check([tag '.fixed_bs'],u.bus(2,6)==3+expected,'fixed BS remains separate from BINIT');
    end
end
for direction=[-1 1]
    f=fixture(); p0=runpf(f,opt); v=ones(2,1); v(2)=1-.1*direction;
    [a,u]=both(f,v); p=runpf(u,opt); balance(sprintf('direction%d',direction),p);
    check(sprintf('direction%d.physical',direction),direction*(p.bus(2,8)-p0.bus(2,8))>0, ...
        'independent AC solve confirms capacitive increase raises voltage and inductive decrease lowers it');
    nodal=ext2int(p); volts=nodal.bus(:,8).*exp(1j*pi/180*nodal.bus(:,9));
    ywith=makeYbus(nodal.baseMVA,nodal.bus,nodal.branch); nodal.bus(2,6)=3;
    ywithout=makeYbus(nodal.baseMVA,nodal.bus,nodal.branch);
    injection=-imag(volts.*conj((ywith-ywithout)*volts))*f.baseMVA;
    check(sprintf('direction%d.injection',direction), ...
        abs(injection(2)-a.current_b*p.bus(2,8)^2)<1e-10, ...
        'independent admittance difference confirms BINIT times squared local voltage');
    evidence.(sprintf('direction%d',direction+2))=struct('input',f,'base',p0,'candidate',u,'solved',p);
end

%% Disabled controls, inclusive tolerance, reversed and missing bands.
for mode=1:7
    f=fixture();
    switch mode
        case 1, f.psse.system.solver.SWSHNT=0;
        case 2, f.psse.system.solver.SWSHNT=2;
        case 3, f.psse.swshunt.num(2)=0;
        case 4, f.psse.swshunt.num(3)=1;
        case 5, f.psse.swshunt.num(4)=0;
        case 6, f.psse.swshunt.num(2)=3;
        case 7, f.psse.swshunt.num(5)=NaN;
    end
    [a,u]=both(f,[1;.8]);
    check(sprintf('disabled%d',mode),a.current_b==0 && u.psse.swshunt.num(10)==0,'no automatic move');
end
for v=[.97-1e-5 1.03+1e-5 1]
    [a,u]=both(fixture(),[1;v]);
    check(sprintf('band%.8f',v),a.current_b==0 && u.psse.swshunt.num(10)==0,'inclusive deadband edges');
end
f=fixture(); f.psse.swshunt.num([5 6])=[.97 1.03]; [a,u]=both(f,[1;.9]);
check('reversed_band',a.current_b==10 && u.psse.swshunt.num(10)==10,'band ordering preserved');

%% Nonconsecutive IDs, remote regulation and reordered voltage measurements.
f=fixture(); f.bus(:,1)=[101;205]; f.gen(:,1)=101; f.branch(:,1:2)=[101 205];
f.bus(3,:)=f.bus(2,:); f.bus(3,[1 3 4 6])=[309 10 3 0];
f.branch(2,:)=f.branch(1,:); f.branch(2,1:2)=[205 309];
f.psse.swshunt.num([1 7])=[205 309];
[a,u]=both(f,[1;1.1;.9]); measurements=f.bus([3 1 2],:); measurements(:,8)=[.9;1;1.1];
rev=mp.psse_unified_control_update(f,measurements);
check('remote.mapping',a.current_b==10 && u.psse.swshunt.num(10)==10 && isequal(u.bus,rev.bus), ...
    'remote voltage uses external identity rather than measurement row order');
p0=runpf(f,opt); p=runpf(u,opt); balance('remote',p);
check('remote.physical',p.bus(3,8)>p0.bus(3,8),'remote voltage rises after capacitive step');
f.psse.swshunt.num(7)=999; [a,u]=both(f,[1;.9;1.1]);
check('remote.fallback',a.current_b==10 && u.psse.swshunt.num(10)==10,'missing remote bus falls back to local bus');

%% Competing groups, literal RMPCT, synchronous decisions and row order.
for weights={[100;100],[25;100],[200;50]}
    f=group_fixture(); f.psse.swshunt.num(:,8)=weights{1};
    [a,u]=both(f,[1;1]);
    if weights{1}(1)>=weights{1}(2), expected=[10;0]; else, expected=[0;-10]; end
    check(sprintf('vote_%g_%g',weights{1}),isequal(a.current_b,expected) && ...
        isequal(u.psse.swshunt.num(:,10),expected),'weighted competing errors; upward tie; only winning voters move');
    f.psse.swshunt.num=f.psse.swshunt.num([2 1],:); [~,rev]=both(f,[1;1]);
    check(sprintf('permutation_%g_%g',weights{1}),isequal(rev.psse.swshunt.num([2 1],10),expected), ...
        'device permutation preserves decisions');
end
f=group_fixture(); f.psse.swshunt.num(:,5:6)=repmat([1.03 .97],2,1);
[a,u]=both(f,[1;.9]); check('simultaneous',all(a.current_b==10) && all(u.psse.swshunt.num(:,10)==10) && ...
    u.bus(2,6)==23,'same-bus contributions accumulate; both devices use one voltage sample');
p=runpf_psse(f,opt); balance('group.settled',p); evidence.group=p;

%% Explicit unified locks must suppress both movement and participation.
for mode=1:3
    f=group_fixture();
    if mode==1
        mask=[true;true]; expected=[0;0];
    elseif mode==2
        mask=[true;false]; expected=[0;-10];
    else
        mask=[false;true]; expected=[10;0];
    end
    f.psse.control_lockout.swshunt=mask; b=f.bus; b(:,8)=1;
    [u,r]=mp.psse_unified_control_update(f,b);
    check(sprintf('lock%d',mode),isequal(u.psse.swshunt.num(:,10),expected), ...
        'explicitly locked rows neither move nor vote against an eligible peer');
    evidence.(sprintf('lock%d',mode))=struct('input',f,'output',u,'report',r);
end
f=fixture(); f.psse.control_lockout.swshunt=true; b=f.bus; b(:,8)=[1;.9];
u=mp.psse_unified_control_update(f,b); u.psse.control_lockout.swshunt=false;
released=mp.psse_unified_control_update(u,b);
check('explicit_release',u.psse.swshunt.num(10)==0 && released.psse.swshunt.num(10)==10, ...
    'caller clearing the explicit lock permits the next step; no inferred release rule');

%% Continuous policy: first-step agreement, history-specific AC sensitivity.
f=fixture(); f.psse.swshunt.num(2)=2; f.psse.swshunt.num(8)=40;
[a,u]=both(f,[1;.9]);
check('continuous.first',abs(a.current_b-5)<1e-10 && abs(u.psse.swshunt.num(10)-5)<1e-10, ...
    'quarter span times literal 40 percent; no weight normalization');
s=mp.psse_swshunt_states(f); s.last_vm(2)=.89; s.last_b(2)=-10;
[a,u]=both(f,[1;.9],s);
check('continuous.history',abs(a.current_b-30)<1e-9 && abs(u.psse.swshunt.num(10)-5)<1e-9, ...
    'AC sensitivity estimate and unified fixed increment intentionally differ');
evidence.continuous=struct('input',f,'ac_state',a,'unified',u);
for b=[-20 30]
    f.psse.swshunt.num(10)=b; f.bus(2,6)=3+b;
    if b<0,v=1.2;else,v=.8;end
    [a,u]=both(f,[1;v]); check(sprintf('continuous.bound%d',b),a.current_b==b && u.psse.swshunt.num(10)==b, ...
        'continuous physical bound is retained');
end
f=fixture(); f.psse.swshunt.num(2)=2; p=runpf_psse(f,opt); balance('continuous.settled',p); evidence.continuous_pf=p;

%% AC candidate screening and cycle memory remain adapter-specific.
f=fixture(); f.psse.swshunt.num(11:14)=[1 1e6 0 0];
[a,u]=both(f,[1;.8]);
check('screening.rejected',a.current_b==0 && a.candidate_rejected==1, ...
    'AC rejects pathological electrical candidate and retains BINIT');
check('screening.provisional',u.psse.swshunt.num(10)==1e6, ...
    'direct unified selector is provisional; electrical acceptance belongs to outer solver');
evidence.screening=struct('input',f,'ac_state',a,'unified',u);
f=fixture(); f.psse.swshunt.num([5 6])=[.95001 .95]; p=runpf_psse(f,opt);
balance('cycle',p); evidence.cycle=p;
check('cycle.ac',p.psse.swshunt.control.cycle_detected && p.psse.swshunt.control.cycle_resolved, ...
    'AC detects actual repeated BINIT state and retains best visited solution');
[~,u]=both(f,[1;.8]); [~,rev]=both(u,[1;1.2]);
check('cycle.unified',rev.psse.swshunt.num(10)==0 && ~rev.psse.swshunt.control.cycle_detected, ...
    'direct unified passes can reverse; outer solver owns history');

save(fullfile(outdir,'shunt.mat'),'checks','evidence');
fid=fopen(fullfile(outdir,'shunt.json'),'w'); fprintf(fid,'%s\n',jsonencode(checks,'PrettyPrint',true)); fclose(fid);
t_begin(length(checks),quiet);
for k=1:length(checks), t_ok(checks(k).passed,[checks(k).id ': ' checks(k).detail]); end
t_end;
    function check(id,passed,detail)
        checks(end+1)=struct('id',id,'passed',logical(passed),'detail',detail);
    end
    function balance(tag,result)
        ai=ext2int(result); y=makeYbus(ai.baseMVA,ai.bus,ai.branch);
        volts=ai.bus(:,8).*exp(1j*pi/180*ai.bus(:,9));
        residual=norm(volts.*conj(y*volts)-makeSbus(ai.baseMVA,ai.bus,ai.gen),Inf);
        check([tag '.balance'],result.success && residual<=1e-8,sprintf('success=%d, AC nodal residual %.12g pu',result.success,residual));
    end
    function [ctrl_state,unified_case]=both(input_case,measured_vm,ctrl_state)
        if nargin<3,ctrl_state=[];end
        dm=struct('source',input_case,'elements',struct('bus',struct('tab',struct('vm',measured_vm))));
        task=struct('dmc',[],'data_model_build',@(mpc,varargin) mpc);
        [~,ctrl_state]=mp.psse_swshunt_control(task,[],[],dm,opt,{},ctrl_state);
        measured_bus=input_case.bus; measured_bus(:,8)=measured_vm;
        unified_case=mp.psse_unified_control_update(input_case,measured_bus);
    end
end
function f=fixture()
f.version='2'; f.baseMVA=100;
f.bus=[1 3 0 0 0 0 1 1 0 230 1 1.1 .9;2 1 40 15 0 3 1 1 0 230 1 1.1 .9];
f.gen=[1 40 0 300 -300 1 100 1 200 0 zeros(1,11)];
f.branch=[1 2 .02 .15 0 200 200 200 0 0 1 -360 360];
base=case5_vsc_mtdc_beerten_ultc_swshunt(); f.psse=rmfield(base.psse,'xfmr');
f.psse.system.adjust.MXTPSS=20;
f.psse.swshunt.num([1:8 10:16])=[2 1 0 1 1.03 .97 2 100 0 2 -10 3 10 0 0];
end
function f=group_fixture()
f=fixture(); f.psse.swshunt.num=repmat(f.psse.swshunt.num,2,1);
f.psse.swshunt.txt=repmat(f.psse.swshunt.txt,2,1);
f.psse.swshunt.num(:,5:6)=[1.06 1.04;.96 .94];
end
