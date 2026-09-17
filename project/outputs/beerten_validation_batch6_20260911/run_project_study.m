function summary=run_project_study(outdir)
% Original fixture, declared capability option changes, fresh evidence.
s=load('outputs/algorithm_cleanup_batch4_20260911/beerten_probe.mat');
u=load('outputs/algorithm_cleanup_batch5_20260911/pqbrak_off_01/nose_03/nose.mat');
base=s.b4f; target=s.b4t; original_options=u.options;
options=mpoption(original_options,'vsc_mtdc.capability_enforce',1, ...
 'vsc_mtdc.capability_gen_enforce',1,'cpf.enforce_q_lims',1);
% q_lims is requested, but this fixture has no RAW GENQ metadata; the unified
% path does not independently enforce its Q box. Audit the original box too.
% P, voltage and flow event enforcement are unavailable in unified CPF.
save(fullfile(outdir,'scenario.mat'),'base','target','original_options','options');
summary=struct();
for step=[.1 .05 .025]
 name=sprintf('capability_step_%03d',round(1000*step));
 o=mpoption(options,'cpf.step',step); diary(fullfile(outdir,[name '.log']));
 timer=tic; result=runcpf_psse(base,target,o); seconds=toc(timer); diary off
 save(fullfile(outdir,[name '.mat']),'result','o','seconds','-v7.3');
 summary.(name)=export_trace(result,base,target,o,outdir,name);
 summary.(name).seconds=seconds;
end
summary.unconstrained=export_trace(u.result,base,target,u.options,outdir,'unconstrained');
pf=runpf_psse(base,options); save(fullfile(outdir,'base_pf.mat'),'pf','options');
jsonwrite(fullfile(outdir,'base_pf.json'),pack(pf));
jsonwrite(fullfile(outdir,'project_summary.json'),summary);
disp(summary);
end
function a=export_trace(r,f,t,o,outdir,name)
c=idx_vsc; sh=mp.psse_swshunt_states(f); xf=mp.psse_xfmr_states(f);
points=cell(1,numel(r.cpf.lam)); audits=cell(size(points));
for k=1:numel(points)
 p=f; p.bus=r.cpf.bus(:,:,k); p.branch=r.cpf.branch(:,1:13,k);
 p.gen=r.cpf.gen(:,:,k); p.vsc=r.cpf.vsc(:,1:29,k); p.busdc=r.cpf.busdc(:,1:4,k);
 p.psse.swshunt.num(:,sh.binit_col)=p.bus(5,6)-sh.base_bs(5);
 p.psse.xfmr.two.num(:,24)=p.branch(xf.branch_idx,9);
 % Materialization is internal equation checking, never independent PF.
 ctx=runpf_vsc_mtdc_unified('__setup',p,o);
 xx=r.cpf.x(:,k); xx=xx(isfinite(xx));
 [F,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,xx,[]);
 rr=runpf_vsc_mtdc_unified('__results',ctx,ev,p);
 ai=ext2int(rr.ac); v=ai.bus(:,8).*exp(1j*pi/180*ai.bus(:,9));
 ac=norm(v.*conj(makeYbus(ai.baseMVA,ai.bus,ai.branch)*v)-makeSbus(ai.baseMVA,ai.bus,ai.gen),Inf);
 [~,rows]=ismember(rr.vsc(:,c.BUSDC),rr.busdc(:,1));
 dc=norm(rr.busdc(:,3).*(makeGdc(rr.busdc,rr.branchdc)*rr.busdc(:,3))-accumarray(rows,rr.vsc(:,c.PDC),[size(rr.busdc,1) 1])/f.baseMVA,Inf);
 conv=max(abs(sum(rr.vsc(:,[c.PAC c.PDC c.PLOSS]),2)))/f.baseMVA;
 pctrl=mp.psse_prepare_case(p,o,'cpf');
 [~,decision]=mp.psse_unified_control_update(pctrl,rr.ac.bus);
 acceptance=mp.psse_unified_control_acceptance(decision,'saturate');
 points{k}=struct('lambda',r.cpf.lam(k),'case',p,'vsc',r.cpf.vsc(:,:,k),'ac_bus',rr.ac.bus,'ac_branch',rr.ac.branch,'ac_gen',rr.ac.gen);
 audits{k}=struct('lambda',r.cpf.lam(k),'residual',norm(F,Inf),'ac',ac,'dc',dc,'converter',conv, ...
 'load_error',max(abs(p.bus(:,3:4)-f.bus(:,3:4)-r.cpf.lam(k)*(t.bus(:,3:4)-f.bus(:,3:4))),[],'all'), ...
 'control',acceptance,'change_requested',decision.changed);
end
a=struct('success',r.success,'termination',r.cpf.termination,'events',r.cpf.events,'failure',r.cpf.failure, ...
 'points',numel(points),'last_lambda',r.cpf.lam(end),'V5',r.bus(5,8),'demand_MW',sum(r.bus(:,3)));
jsonwrite(fullfile(outdir,[name '.json']),struct('summary',a,'points',{points},'audits',{audits}));
end
function r=pack(p)
r=struct('bus',p.bus,'gen',p.gen,'branch',p.branch,'vsc',p.vsc,'busdc',p.busdc,'success',p.success,'convergence',p.convergence);
end
function jsonwrite(path,value)
fid=fopen(path,'w'); cleanup=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(value));
end
