function [checks,evidence] = t_pqbrak_off_batch5(quiet,outdir)
%T_PQBRAK_OFF_BATCH5 Global default, cache restoration, and constant-load nose.
if nargin<1, quiet=0; end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<2, outdir=tempname(fullfile(root,'outputs')); end
assert(~isfolder(outdir),'Use a fresh directory'); mkdir(outdir);
checks=struct('id',{},'passed',{}); evidence=struct();
o=mpoption('verbose',0,'out.all',0);
check('default_off',o.exp.psse_pqbrak==0);
old=o;old.v=26;old.exp=rmfield(old.exp,'psse_pqbrak'); upgraded=mpoption(old);
check('old_options_off',upgraded.exp.psse_pqbrak==0 && upgraded.v==27);
p=loadcase('case9');p.psse.rev=34;p.psse.system.general.PQBRAK=.7;
p.bus(:,8)=.6;p.gen(:,6)=.6;p.gen(:,2)=.1*p.gen(:,2);p.bus(:,3:4)=.1*p.bus(:,3:4);
off=mp.psse_pqbrak_prepare(p);
check('raw_threshold_does_not_enable',~off.psse.pqbrak.enabled && isequal(off.bus,p.bus));
onopt=mpoption(o,'exp.psse_pqbrak',1);on=mp.psse_pqbrak_prepare(p,onopt);
check('explicit_opt_in',on.psse.pqbrak.enabled && any(on.psse.pqbrak.scale<1));
extra=[(1:size(p.bus,1))' -(1:size(p.bus,1))'];
on.bus(:,3:4)=on.bus(:,3:4)+extra;
restored=mp.psse_pqbrak_prepare(on,o);
check('restore_native_preserve_equivalents',max(abs(restored.bus(:,3:4)-p.bus(:,3:4)-extra),[],'all')<1e-12);
again=mp.psse_pqbrak_prepare(restored,o);
check('disable_idempotent',isequal(again.bus,restored.bus) && all(again.psse.pqbrak.scale==1));
reordered=on;reordered.bus=flipud(on.bus);reordered=mp.psse_pqbrak_prepare(reordered,o);
check('restore_external_bus_mapping',max(abs(reordered.bus(:,3:4)-flipud(p.bus(:,3:4)+extra)),[],'all')<1e-12);
[~,pol]=mp.psse_solver_options(o,p);k=find(strcmp({pol.effective.name},'PQBRAK'));
check('policy_reports_disabled',isscalar(k) && strcmp(pol.effective(k).status,'disabled') && pol.effective(k).value==.7);
a=runpf_psse(p,o);b=runpf(p,o);evidence.low_voltage_pf={a,b};
check('low_voltage_pf_constant_load',a.success && b.success && ~a.psse.pqbrak.enabled && ...
    max(abs(a.bus(:,8:9)-b.bus(:,8:9)),[],'all')<1e-9 && isequal(a.bus(:,3:4),p.bus(:,3:4)));
s=load(fullfile(root,'outputs','algorithm_cleanup_batch4_20260911','beerten_probe.mat'));
f=s.b4f;t=s.b4t;opt=mpoption(s.b4o,'cpf.stop_at','NOSE', ...
    'vsc_mtdc.psse_control_limit','saturate','exp.psse_pqbrak',0);
sh=mp.psse_swshunt_states(f);xf=mp.psse_xfmr_states(f);c=idx_vsc;
for step=[.1 .05 .025]
    thisopt=mpoption(opt,'cpf.step',step);r=runcpf_psse(f,t,thisopt);
    evidence.(sprintf('step%d',round(step*1000)))=r;
    check(sprintf('nose_%g',step),r.success && strcmp(r.cpf.termination.cause,'nose_event') && ...
        r.cpf.termination.nose_detected && r.cpf.termination.requested_endpoint_reached && ...
        r.convergence.converged && abs(r.cpf.z(end,end))<=opt.cpf.nose_tol);
    check(sprintf('off_%g',step),~r.psse.pqbrak.enabled && all(r.psse.pqbrak.scale==1) && ...
        ~any(strcmp({r.cpf.events.name},'PSSE_CONTROL_FAILED')));
    if step==.1, ref=r; else
        check(sprintf('step_agreement_%g',step),abs(r.cpf.lam(end)-ref.cpf.lam(end))<1e-5 && ...
            max(abs(r.bus(:,8)-ref.bus(:,8)))<1e-4);
    end
end
r=ref;
for k=1:numel(r.cpf.lam)
    p=f;p.bus(:,3:4)=f.bus(:,3:4)+r.cpf.lam(k)*(t.bus(:,3:4)-f.bus(:,3:4));
    p.bus(:,6)=r.cpf.bus(:,6,k);p.branch(:,1:13)=r.cpf.branch(:,1:13,k);
    p.psse.swshunt.num(:,sh.binit_col)=p.bus(5,6)-sh.base_bs(5);
    p.psse.xfmr.two.num(:,24)=p.branch(xf.branch_idx,9);
    ctx=runpf_vsc_mtdc_unified('__setup',p,opt);
    [F,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,r.cpf.x(:,k),[]);
    full=runpf_vsc_mtdc_unified('__results',ctx,ev,p);
    ai=ext2int(full.ac);v=ai.bus(:,8).*exp(1j*pi/180*ai.bus(:,9));
    ac=norm(v.*conj(makeYbus(ai.baseMVA,ai.bus,ai.branch)*v)-makeSbus(ai.baseMVA,ai.bus,ai.gen),Inf);
    [~,rows]=ismember(full.vsc(:,c.BUSDC),full.busdc(:,1));
    dc=norm(full.busdc(:,3).*(makeGdc(full.busdc,full.branchdc)*full.busdc(:,3))- ...
        accumarray(rows,full.vsc(:,c.PDC),[size(full.busdc,1) 1])/f.baseMVA,Inf);
    conv=max(abs(sum(full.vsc(:,[c.PCONV c.PDC c.PLOSS]),2)))/f.baseMVA;
    check(sprintf('point%d_equations',k),max([norm(F,Inf) ac dc conv])<1e-8);
    check(sprintf('point%d_load_schedule',k),max(abs(r.cpf.bus(:,3:4,k)-p.bus(:,3:4)),[],'all')<1e-10);
    [~,original_rows]=ismember(r.bus(:,1),full.ac.bus(:,1));
    check(sprintf('point%d_voltage_tables',k),max(abs(full.ac.bus(original_rows,8:9)-r.cpf.bus(:,8:9,k)),[],'all')<1e-9);
end
[~,decision]=mp.psse_unified_control_update(r,r.ac.bus);
acceptance=mp.psse_unified_control_acceptance(decision,'saturate');
evidence.localized_nose_controls=acceptance;
check('localized_nose_controls_settled',acceptance.accepted && ~decision.changed);
check('localized_state_reporting',isequal(r.convergence.state_vector,r.cpf.x(:,end)) && ...
    isequal(r.bus,r.cpf.bus(:,:,end)) && r.convergence.lambda==r.cpf.lam(end));
evidence.nose_capability_audit=check_capability_limits(r);
evidence.options=opt;
save(fullfile(outdir,'evidence.mat'),'evidence','checks','-v7.3');
fid=fopen(fullfile(outdir,'checks.json'),'w');fprintf(fid,'%s\n',jsonencode(checks,'PrettyPrint',true));fclose(fid);
t_begin(numel(checks),quiet);for k=1:numel(checks),t_ok(checks(k).passed,checks(k).id);end;t_end;
    function check(id,passed)
        checks(end+1)=struct('id',id,'passed',logical(passed));
    end
end
