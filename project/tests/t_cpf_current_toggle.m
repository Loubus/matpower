function evidence=t_cpf_current_toggle(base,target,options,outdir)
% Exercise both formulations on a case that activates a preserve-P current limit.
if ~isfolder(outdir),mkdir(outdir);end
checks=struct('name',{},'passed',{});runs=cell(1,3);
options=mpoption(options,'cpf.stop_at','NOSE','cpf.step',.1);
defaults=mpoption;ck('registered_default_enabled',defaults.vsc_mtdc.coupled_current_limits==1);
for k=1:3
    o=options;
    if k==1
        if isfield(o.vsc_mtdc,'coupled_current_limits')
            o.vsc_mtdc=rmfield(o.vsc_mtdc,'coupled_current_limits');
        end
    else
        o=mpoption(o,'vsc_mtdc.coupled_current_limits',k==2);
    end
    file=fullfile(outdir,sprintf('run_%d.mat',k));assert(~isfile(file),'Preserve prior test output');
    lastwarn('');[r,success]=runcpf_psse(base,target,o);[warning_text,warning_id]=lastwarn;
    save(file,'base','target','o','r','success','warning_text','warning_id','-v7.3');runs{k}=r;
    ck(sprintf('run_%d_reports_resolved_toggle',k),r.cpf.coupled_current_limits==(k~=3));
    ck(sprintf('run_%d_retains_turn_detection',k),isfield(r.cpf,'turn_detection'));
end
ck('missing_option_matches_explicit_on',isequaln(runs{1}.cpf.lam,runs{2}.cpf.lam));
ck('on_activates_current_equation',isfield(runs{2},'vsc_current_limit') && any(runs{2}.vsc_current_limit>0));
ck('off_never_activates_current_equation',~isfield(runs{3},'vsc_current_limit') || ~any(runs{3}.vsc_current_limit>0));
ck('off_exercises_projection',any(strcmp({runs{3}.cpf.events.name},'VSC_CAPABILITY')));
on=mpoption(options,'vsc_mtdc.coupled_current_limits',1);
for bad={-1,2,NaN,[0 1],'off'}
    o=on;o.vsc_mtdc.coupled_current_limits=bad{1};rejected=false;
    try,runcpf_vsc_mtdc(base,target,o);catch me,rejected=strcmp(me.identifier,'runcpf_vsc_mtdc:coupled_current_limits');end
    ck('invalid_toggle_rejected',rejected);
end
off=mpoption(options,'vsc_mtdc.coupled_current_limits',0);
for side=1:2
    b=base;t=target;
    if side==1,b.vsc_current_limit=runs{2}.vsc_current_limit;else,t.vsc_current_limit=runs{2}.vsc_current_limit;end
    rejected=false;
    try,runcpf_vsc_mtdc(b,t,off);catch me,rejected=strcmp(me.identifier,'runcpf_vsc_mtdc:current_limit_state_conflict');end
    ck('off_rejects_saved_active_constraint',rejected);
end
summary=cell(1,3);
for k=1:3
    r=runs{k};summary{k}=struct('setting',r.cpf.coupled_current_limits,'lambda',r.cpf.lam(end),'termination',r.cpf.termination);
end
evidence=struct('checks',checks,'passed',sum([checks.passed]),'failed',sum(~[checks.passed]),'runs',{summary});
fid=fopen(fullfile(outdir,'toggle_tests.json'),'w');fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));fclose(fid);
fprintf('CURRENT_TOGGLE: %d passed, %d failed\n',evidence.passed,evidence.failed);
for k=1:3,disp(summary{k});end
assert(evidence.failed==0,'Coupled-current toggle regression failed.');
 function ck(name,passed)
    checks(end+1)=struct('name',name,'passed',logical(passed));
 end
end
