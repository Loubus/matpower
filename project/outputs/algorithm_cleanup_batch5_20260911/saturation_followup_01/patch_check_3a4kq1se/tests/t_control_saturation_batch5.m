function [checks,evidence] = t_control_saturation_batch5(quiet,outdir)
%T_CONTROL_SATURATION_BATCH5 Solved saturation, reversal and full-model reports.
% MCP sessions persist; test the current composed solver files on each run.
clear runpf_vsc_mtdc_unified runcpf_vsc_mtdc
if nargin<1, quiet=0; end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<2, outdir=tempname(fullfile(root,'outputs')); end
assert(~isfolder(outdir),'Use a fresh output directory'); mkdir(outdir);
s=load(fullfile(root,'outputs','algorithm_cleanup_batch4_20260911','beerten_probe.mat'));
f=s.b4f; target=s.b4t; opt=s.b4o; opt.vsc_mtdc.psse_control_limit='saturate';
c=idx_vsc; sh=mp.psse_swshunt_states(f); xf=mp.psse_xfmr_states(f);
checks=struct('id',{},'passed',{},'detail',{});
evidence=struct('base',f,'target',target,'original_options',s.b4o,'options',opt,'fixed',{{}},'automatic',{{}});
defaults=mpoption;
check('default',strcmp(defaults.vsc_mtdc.psse_control_limit,'saturate'),'new explicit default');
r=runcpf_psse(f,target,opt); evidence.cpf=r;
check('target',r.success && r.cpf.termination.requested_endpoint_reached && ...
    abs(r.cpf.lam(end)-.8)<=opt.cpf.target_lam_tol && strcmp(r.cpf.termination.cause,'requested_lambda'), ...
    'unchanged numeric target reached under declared saturation policy');
check('scope',r.convergence.converged && r.convergence.overall_success && ...
    r.convergence.lambda==r.cpf.lam(end) && ~r.cpf.termination.nose_detected && ...
    ~r.cpf.termination.stability_margin_validated,'target completion is not a nose certificate');
check('saturation_report',r.convergence.psse_controls.accepted && ...
    strcmp(r.convergence.psse_controls.status,'saturated') && ...
    ~r.convergence.psse_controls.regulation_satisfied && r.psse.swshunt.control.blocked_low==1, ...
    'accepted physical saturation retains full-model out-of-band report');
check('no_locks',~any(contains({r.cpf.events.name},'FREEZE')) && ...
    r.psse.swshunt.control.locked_out==0 && r.psse.xfmr.control.locked_out==0 && ...
    r.psse.swshunt.control.controllable==1,'saturation never locks either controller');
check('observed',strcmp(r.cpf.active_set_failure_policy.psse_control.observed_policy,'saturate') && ...
    any(strcmp({r.cpf.events.name},'PSSE_CONTROL_SATURATED')),'accepted saturation recorded separately from failure');
physical('endpoint',r);
evidence.endpoint_capability_audit=check_capability_limits(r);
check('ratings_preserved',isequal(r.gen(:,[4 5 9 10]),f.gen(:,[4 5 9 10])) && ...
    isequal(r.vsc(:,c.LOSS_A:c.REACTOR_RATE_C),f.vsc(:,c.LOSS_A:c.REACTOR_RATE_C)), ...
    'original generator limits and converter loss/station ratings retained');
for k=1:numel(r.cpf.lam)
    p=at_lambda(r.cpf.lam(k)); p.bus(:,6)=r.cpf.bus(:,6,k);
    p.branch(:,1:13)=r.cpf.branch(:,1:13,k);
    p.psse.swshunt.num(:,sh.binit_col)=p.bus(5,6)-sh.base_bs(5);
    p.psse.xfmr.two.num(:,24)=p.branch(xf.branch_idx,9);
    pf=runpf_vsc_mtdc(p,s.b4o); evidence.fixed{end+1}=pf;
    tag=sprintf('point%d',k); physical([tag '.fixed'],pf);
    [~,rows]=ismember(r.bus(:,1),pf.ac.bus(:,1));
    check([tag '.match'],pf.success && max(abs(phasor(pf.ac.bus(rows,:))-phasor(r.cpf.bus(:,:,k))))<1e-6, ...
        'independent fixed-state full PF matches accepted CPF voltage');
    ctx=runpf_vsc_mtdc_unified('__setup',p,opt);
    [~,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,r.cpf.x(:,k),[]);
    full=runpf_vsc_mtdc_unified('__results',ctx,ev,p); physical([tag '.stored'],full);
    check([tag '.legal'],any(abs(sh.states{1}-p.psse.swshunt.num(:,sh.binit_col))<1e-9) && ...
        any(abs(xf.states_tap{1}-p.branch(xf.branch_idx,9))<1e-9), 'original discrete grids');
end
for lam=[s.b4r.cpf.failure.lambda .45 .8]
    p=at_lambda(lam); pf=runpf_psse(p,opt); physical(sprintf('auto%.8g',lam),pf);
    a=pf.convergence.psse_controls.acceptance;
    check(sprintf('auto%.8g.report',lam),pf.success && a.accepted && a.saturated && ...
        ~a.regulation_satisfied && pf.psse.swshunt.control.below_band==1 && ...
        pf.psse.swshunt.control.inside_band==0,'full-model out-of-band voltage cannot be overwritten by auxiliary report');
    if lam==.8
        check('automatic_endpoint_match',max(abs(phasor(pf.ac.bus)-phasor(r.ac.bus)))<1e-6, ...
            'automatic PF from original controls agrees with CPF');
    end
    evidence.automatic{end+1}=pf;
end
stress=f;stress.bus(:,[3 4])=1000*stress.bus(:,[3 4]);
failed=runcpf_psse(stress,stress,opt);evidence.failed_electrical=failed;
check('electrical_failure',~failed.success && ~failed.convergence.converged && ...
    isempty(failed.cpf.lam),'saturation cannot accept a failed base electrical solve');
stop=runpf_psse(at_lambda(s.b4r.cpf.failure.lambda),s.b4o); evidence.stop_pf=stop;
check('stop_pf',~stop.success && stop.convergence.converged && ...
    ~stop.convergence.overall_success && ~stop.convergence.psse_controls.converged && ...
    strcmp(stop.convergence.psse_controls.acceptance.status,'control_bound'), ...
    'explicit stop rejects regulation while accurately retaining electrical convergence');
for step=[.05 .025]
    a=runcpf_psse(f,target,mpoption(opt,'cpf.step',step));
    check(sprintf('step%g',step),a.success && abs(a.cpf.lam(end)-.8)<=opt.cpf.target_lam_tol && ...
        max(abs(phasor(a.ac.bus)-phasor(r.ac.bus)))<1e-6,'same target and state with smaller steps');
    evidence.(sprintf('step%d',round(1000*step)))=a;
end
% Separate negative fixture: a narrow regulation band between discrete states
% forces alternating shunt requests. Original cases/grid/tolerances are not
% changed; this does not represent the main Beerten loading scenario.
cycle_base=f;cycle_base.psse.swshunt.num(1,5:6)=[.95001 .95];
cycle_target=target;cycle_target.psse.swshunt=cycle_base.psse.swshunt;
cycle_opt=mpoption(opt,'cpf.stop_at','NOSE');
cycle=runcpf_psse(cycle_base,cycle_target,cycle_opt);
evidence.cycle=struct('base',cycle_base,'target',cycle_target,'options',cycle_opt,'result',cycle);
check('cycle_outcome',~cycle.success && ~cycle.convergence.overall_success && ...
    ~cycle.cpf.termination.requested_endpoint_reached && ~cycle.cpf.termination.nose_detected && ...
    any(strcmp(cycle.cpf.termination.cause,{'control_cycle','control_iteration_limit'})), ...
    'cycling cannot turn an unmet NOSE request into successful completion');
check('cycle_last_accepted',cycle.convergence.converged && ...
    cycle.convergence.lambda==cycle.cpf.lam(end) && ~isempty(cycle.cpf.failure) && ...
    cycle.cpf.failure.lambda>cycle.cpf.lam(end), ...
    'failed control transition remains separate from the accepted electrical point');
% Separate unreachable tap-regulation objective exercises physical saturation
% through both complete solvers, using the original transformer grid/ratings.
tap_base=f;tap_base.psse=rmfield(tap_base.psse,'swshunt');
tap_base.psse.xfmr.two.num(1,43:44)=[1.31 1.30];
tap_target=tap_base;tap_target.bus(:,[3 4])=1.02*tap_base.bus(:,[3 4]);
tap_pf=runpf_psse(tap_base,opt);tap_cpf=runcpf_psse(tap_base,tap_target,opt);
physical('tap_saturated_pf',tap_pf);physical('tap_saturated_cpf',tap_cpf);
check('tap_pf_saturation',tap_pf.success && ...
    tap_pf.convergence.psse_controls.acceptance.saturated && ...
    ~tap_pf.convergence.psse_controls.acceptance.regulation_satisfied && ...
    tap_pf.psse.xfmr.control.locked_out==0,'full PF accepts unmet regulation at the physical tap bound');
check('tap_cpf_saturation',tap_cpf.success && ...
    tap_cpf.cpf.termination.requested_endpoint_reached && ...
    tap_cpf.convergence.psse_controls.saturated && ...
    tap_cpf.psse.xfmr.control.locked_out==0,'CPF retains the eligible saturated tap and reaches the unchanged numeric target');
evidence.tap_saturation=struct('base',tap_base,'target',tap_target,'pf',tap_pf,'cpf',tap_cpf);
% Prescribed voltages test both bounds and subsequent reverse requests.
% These decision probes are separate from the electrical loading scenario.
for family={'swshunt','xfmr'}
    name=family{1}; p=f;
    if strcmp(name,'swshunt'), p.psse=rmfield(p.psse,'xfmr'); else, p.psse=rmfield(p.psse,'swshunt'); end
    for direction=[-1 1]
        q=p;
        if strcmp(name,'swshunt')
            st=mp.psse_swshunt_states(q); st.current_b=st.bmin;
            if direction>0, st.current_b=st.bmax; end
            q=mp.psse_swshunt_update(q,st); reg=st.reg_bus_idx;
            vm=st.vswhi+.1; if direction>0, vm=st.vswlo-.1; end
        else
            st=mp.psse_xfmr_states(q); j=1;
            if direction*st.side_sign>0, j=numel(st.states_tap{1}); end
            st.current_tap=st.states_tap{1}(j); st.current_raw=st.states_raw{1}(j);
            q=mp.psse_xfmr_update(q,st); reg=st.reg_bus_idx;
            vm=st.vma+.1; if direction>0, vm=st.vmi-.1; end
        end
        b=q.bus; b(reg,8)=vm;
        [sat,d]=mp.psse_unified_control_update(q,b);
        a=mp.psse_unified_control_acceptance(d,'saturate');
        tag=sprintf('%s.bound%d',name,direction);
        check(tag,~d.changed && a.accepted && a.saturated,'outward request at a physical bound is settled');
        b(reg,8)=2-vm;
        [back,rev]=mp.psse_unified_control_update(sat,b);
        reverse_acceptance=mp.psse_unified_control_acceptance(rev,'saturate');
        check([tag '.reverse'],rev.changed && ~reverse_acceptance.accepted, ...
            'opposite request moves away from bound and requires re-correction');
        evidence.([name sprintf('%d',direction+2)])=struct('saturated',sat,'reverse',back);
        bad=d; bad.changed=1; reject(bad,[tag '.changed']);
        bad=d; bad.control_cycles=1; reject(bad,[tag '.cycle']);
        bad=d; bad.requires_auxiliary_pf=1; reject(bad,[tag '.unsupported']);
        bad=d; bad.blocked_violations=0; reject(bad,[tag '.unresolved']);
        q.psse.control_lockout.(name)=true;
        [locked,ld]=mp.psse_unified_control_update(q,b);
        la=mp.psse_unified_control_acceptance(ld,'saturate');
        check([tag '.lock'],~ld.changed && ~la.saturated && ...
            locked.psse.(name).control.locked_out==1,'explicit lock is preserved and not reclassified as saturation');
    end
end
save(fullfile(outdir,'saturation.mat'),'checks','evidence','-v7.3');
fid=fopen(fullfile(outdir,'checks.json'),'w');fprintf(fid,'%s\n',jsonencode(checks,'PrettyPrint',true));fclose(fid);
t_begin(numel(checks),quiet);
for k=1:numel(checks),t_ok(checks(k).passed,[checks(k).id ': ' checks(k).detail]);end
t_end;
    function check(id,passed,detail)
        checks(end+1)=struct('id',id,'passed',logical(passed),'detail',detail);
    end
    function reject(d,tag)
        a=mp.psse_unified_control_acceptance(d,'saturate');
        check(tag,~a.accepted,'saturation cannot excuse unresolved work');
    end
    function p=at_lambda(lam)
        p=f;p.bus(:,[3 4])=f.bus(:,[3 4])+lam*(target.bus(:,[3 4])-f.bus(:,[3 4]));
    end
    function v=phasor(b)
        v=b(:,8).*exp(1j*pi/180*b(:,9));
    end
    function physical(tag,p)
        a=ext2int(p.ac);v=phasor(a.bus);
        ac=norm(v.*conj(makeYbus(a.baseMVA,a.bus,a.branch)*v)-makeSbus(a.baseMVA,a.bus,a.gen),Inf);
        [~,rows]=ismember(p.vsc(:,c.BUSDC),p.busdc(:,1));
        dc=norm(p.busdc(:,3).*(makeGdc(p.busdc,p.branchdc)*p.busdc(:,3))- ...
            accumarray(rows,p.vsc(:,c.PDC),[size(p.busdc,1) 1])/f.baseMVA,Inf);
        conv=max(abs(sum(p.vsc(:,[c.PAC c.PDC c.PLOSS]),2)))/f.baseMVA;
        current=hypot(p.vsc(:,c.PAC),p.vsc(:,c.QAC))./(f.baseMVA*p.vsc(:,c.VAC_INTERNAL));
        loss=max(abs(p.vsc(:,c.LOSS_A)+p.vsc(:,c.LOSS_B).*current+ ...
            p.vsc(:,c.LOSS_C).*current.^2-p.vsc(:,c.PLOSS)))/f.baseMVA;
        check([tag '.balance'],max([ac dc conv loss])<1e-8, ...
            sprintf('full AC %.3g DC %.3g converter %.3g loss %.3g pu',ac,dc,conv,loss));
    end
end
