function [checks,evidence] = t_ultc_beerten_batch3(quiet,outdir)
%T_ULTC_BEERTEN_BATCH3 Short Beerten controls-active PF/CPF physical gate.
% Existing project variant, not certification against the published benchmark.
% Every accepted point is compared to an independent full-equation fixed-state
% PF; endpoint automatic PF and half-step CPF are checked separately.
if nargin<1, quiet=0; end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<2, outdir=tempname(fullfile(root,'outputs')); end
assert(~exist(outdir,'dir'),'Use a fresh output directory'); mkdir(outdir);
opt=mpoption('verbose',0,'out.all',0);
opt.vsc_mtdc.method='unified';
f=loadcase('case5_vsc_mtdc_beerten_ultc_swshunt');
s=mp.psse_xfmr_states(f); c=idx_vsc;
checks=struct('id',{},'passed',{},'detail',{});
evidence=struct('base',f,'options',opt,'matlab',version);
for scenario=1:2
    target=f;
    if scenario==1
        label='uniform'; target.bus(:,[3 4])=2*f.bus(:,[3 4]); stop=.6;
    else
        label='load_side'; target.bus(7,[3 4])=5*f.bus(7,[3 4]); stop=.8;
    end
    cop=mpoption(opt,'cpf.stop_at',stop,'cpf.step',.1);
    r=runcpf_psse(f,target,cop);
    check([label '.endpoint'],r.success && abs(r.cpf.lam(end)-stop)<1e-6,'requested loading reached');
    physical([label '.cpf'],r);
    check([label '.policy'],strcmp(r.cpf.active_set_failure_policy.psse_control.declared_policy,'stop') && ...
        ~any(contains({r.cpf.events.name},'FREEZE')) && ...
        ~any(r.psse.xfmr.control_locked_out),'controls active with stop policy and no lock/freeze event');
    check([label '.initial_move'],any(abs(r.cpf.branch(s.branch_idx,9,1)-f.branch(s.branch_idx,9))>1e-10), ...
        'initial off-grid tap is normalized and electrically corrected');
    if scenario==2
        taps=squeeze(r.cpf.branch(s.branch_idx,9,:));
        check([label '.later_move'],any(abs(diff(taps))>1e-10) && ...
            any(strcmp({r.cpf.events.name},'PSSE_CONTROL') & [r.cpf.events.k]>0), ...
            'load-side growth triggers an accepted post-base tap event');
    end
    fixed=cell(length(r.cpf.lam),1);
    for k=1:length(r.cpf.lam)
        tag=sprintf('%s.point%d',label,k);
        lam=r.cpf.lam(k); point=f;
        point.bus(:,[3 4])=f.bus(:,[3 4])+lam*(target.bus(:,[3 4])-f.bus(:,[3 4]));
        point.bus(:,6)=r.cpf.bus(:,6,k);
        point.branch(:,1:13)=r.cpf.branch(:,1:13,k);
        % runpf_vsc_mtdc solves this specified electrical state directly;
        % automatic control settlement is exercised by runcpf_psse/runpf_psse.
        p=runpf_vsc_mtdc(point,opt); fixed{k}=p;
        physical([tag '.fixed_pf'],p);
        trace_ac_balance(tag,r,k,point);
        [~,rows]=ismember(r.cpf.bus(:,1,k),p.ac.bus(:,1));
        vc=r.cpf.bus(:,8,k).*exp(1j*pi/180*r.cpf.bus(:,9,k));
        vp=p.ac.bus(rows,8).*exp(1j*pi/180*p.ac.bus(rows,9));
        check([tag '.pf_cpf_voltage'],max(abs(vc-vp))<=1e-6,'complex bus voltages agree at matched load and discrete state');
        check([tag '.pf_cpf_converter'],max(abs(p.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS])- ...
            r.cpf.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS],k)),[],'all')/f.baseMVA<=1e-6, ...
            'converter injections and losses agree at matched state');
        check([tag '.load'],max(abs(point.bus(:,[3 4])-r.cpf.bus(:,[3 4],k)),[],'all')<1e-8, ...
            'accepted demand equals affine loading at reported lambda');
        taps=r.cpf.branch(s.branch_idx,9,k);
        check([tag '.grid'],all(arrayfun(@(j) min(abs(s.states_tap{j}-taps(j)))<1e-10,1:s.n)), ...
            'all accepted taps belong to the unchanged finite grid');
        check([tag '.generator_bounds'],all(r.cpf.gen(:,3,k)>=f.gen(:,5)-.01 & ...
            r.cpf.gen(:,3,k)<=f.gen(:,4)+.01),'original generator Q bounds are respected');
        dc_balance(tag,r.cpf.busdc(:,:,k),r.cpf.branchdc(:,:,k),r.cpf.vsc(:,:,k));
    end
    point=f; point.bus(:,[3 4])=f.bus(:,[3 4])+r.cpf.lam(end)*(target.bus(:,[3 4])-f.bus(:,[3 4]));
    p=runpf_psse(point,opt); physical([label '.automatic_pf'],p);
    check([label '.automatic_agreement'],max(abs(p.ac.bus(:,8)-r.ac.bus(:,8)))<=1e-6 && ...
        max(abs(p.branch(:,9)-r.branch(:,9)))<1e-10 && ...
        max(abs(p.bus(:,6)-r.bus(:,6)))<1e-8,'independent automatic PF reaches the same endpoint control state and voltage');
    check([label '.raw_sync'],max(abs(r.psse.xfmr.two.num(:,24)-r.branch(s.branch_idx,9)))<1e-10, ...
        'CW=1 WINDV agrees with exported branch tap');
    half=runcpf_psse(f,target,mpoption(cop,'cpf.step',.05));
    physical([label '.half_step'],half);
    check([label '.step_sensitivity'],half.success && abs(half.cpf.lam(end)-r.cpf.lam(end))<1e-6 && ...
        max(abs(half.ac.bus(:,8)-r.ac.bus(:,8)))<=1e-6 && ...
        max(abs(half.branch(:,9)-r.branch(:,9)))<1e-10,'halved continuation step retains matched endpoint and control state');
    evidence.(label)=struct('target',target,'options',cop,'cpf',r,'fixed_pf',{fixed},'automatic_pf',p,'half_step',half);
end
save(fullfile(outdir,'beerten.mat'),'checks','evidence');
fid=fopen(fullfile(outdir,'beerten.json'),'w'); fprintf(fid,'%s\n',jsonencode(checks,'PrettyPrint',true)); fclose(fid);
t_begin(length(checks),quiet);
for k=1:length(checks), t_ok(checks(k).passed,[checks(k).id ': ' checks(k).detail]); end
t_end;

    function check(id,passed,detail)
        checks(end+1)=struct('id',id,'passed',logical(passed),'detail',detail);
    end
    function physical(tag,p)
        check([tag '.success'],p.success && p.convergence.max_mismatch<=p.convergence.tol, ...
            sprintf('success; nonlinear residual %.12g <= %.12g',p.convergence.max_mismatch,p.convergence.tol));
        a=ext2int(p.ac); y=makeYbus(a.baseMVA,a.bus,a.branch);
        v=a.bus(:,8).*exp(1j*pi/180*a.bus(:,9));
        residual=norm(v.*conj(y*v)-makeSbus(a.baseMVA,a.bus,a.gen),Inf);
        check([tag '.ac_balance'],residual<=1e-8,sprintf('complete station-network AC balance %.12g pu',residual));
        dc_balance(tag,p.busdc,p.branchdc,p.vsc);
    end
    function dc_balance(tag,bd,br,vs)
        residual=max(abs(sum(vs(:,[c.PAC c.PDC c.PLOSS]),2)))/f.baseMVA;
        check([tag '.converter_balance'],residual<=1e-8,sprintf('converter power balance %.12g pu',residual));
        current=hypot(vs(:,c.PAC),vs(:,c.QAC))./(f.baseMVA*vs(:,c.VAC_INTERNAL));
        loss=vs(:,c.LOSS_A)+vs(:,c.LOSS_B).*current+vs(:,c.LOSS_C).*current.^2;
        check([tag '.loss_equation'],max(abs(loss-vs(:,c.PLOSS)))/f.baseMVA<=1e-8 && all(loss>=0), ...
            'unchanged converter loss equation and nonnegative losses');
        [~,rows]=ismember(vs(:,c.BUSDC),bd(:,1));
        injection=accumarray(rows,vs(:,c.PDC),[size(bd,1) 1])/f.baseMVA;
        residual=norm(bd(:,3).*(makeGdc(bd,br)*bd(:,3))-injection,Inf);
        check([tag '.dc_balance'],residual<=1e-8,sprintf('DC nodal balance %.12g pu',residual));
    end
    function trace_ac_balance(tag,r,k,point)
        % Materialize the actual stored continuation state, including station
        % angles, on this point's load/tap/shunt model. No PF solution or
        % station-phasor approximation replaces the accepted CPF state.
        ctx = runpf_vsc_mtdc_unified('__setup',point,opt);
        [~,ev] = runpf_vsc_mtdc_unified('__mismatch',ctx,r.cpf.x(:,k),[]);
        full = runpf_vsc_mtdc_unified('__results',ctx,ev,point);
        [~,rows] = ismember(r.cpf.bus(:,1,k),full.ac.bus(:,1));
        check([tag '.cpf_state_identity'], ...
            max(abs(full.ac.bus(rows,[8 9])-r.cpf.bus(:,[8 9],k)),[],'all')<1e-10 && ...
            max(abs(full.vsc(:,[c.PAC c.QAC c.PDC])-r.cpf.vsc(:,[c.PAC c.QAC c.PDC],k)),[],'all')<1e-8, ...
            'stored state reproduces the accepted bus and converter trace');
        a=ext2int(full.ac); y=makeYbus(a.baseMVA,a.bus,a.branch);
        v=a.bus(:,8).*exp(1j*pi/180*a.bus(:,9));
        residual=norm(v.*conj(y*v)-makeSbus(a.baseMVA,a.bus,a.gen),Inf);
        check([tag '.cpf_ac_balance'],residual<=1e-8, ...
            sprintf('actual CPF full station-network balance %.12g pu',residual));
    end
end
