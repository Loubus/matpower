function summary=summarize_batch5(outdir)
assert(~isfolder(outdir)); mkdir(outdir);
b5root=fileparts(mfilename('fullpath'));
s=load(fullfile(b5root,'focused_final','evidence','termination.mat'));
r=s.evidence.result; d=r.cpf.failure.diagnostic; f=s.evidence.base; t=s.evidence.target; o=s.evidence.options;
tr=load(fullfile(b5root,'trace_01','trace.mat'));
c=idx_vsc; sh=mp.psse_swshunt_states(f); xf=mp.psse_xfmr_states(f);
summary=struct('success',r.success,'termination',r.cpf.termination, ...
 'last_lambda',r.cpf.lam(end),'candidate_lambda',r.cpf.failure.lambda, ...
 'last_vm5',r.bus(5,8),'candidate_vm5',d.candidate.bus(5,8), ...
 'last_residual',r.convergence.max_mismatch,'candidate_residual',d.candidate.convergence.max_mismatch, ...
 'candidate_tap',d.candidate.branch(xf.branch_idx,9), ...
 'tap_regulated_bus',f.bus(xf.reg_bus_idx,1),'tap_regulated_vm',d.candidate.bus(xf.reg_bus_idx,8), ...
 'shunt_states',sh.states{1},'shunt_band',[sh.vswlo sh.vswhi], ...
 'control_voltage_tolerance',sh.vtol,'candidate_gen',d.candidate.gen(:,1:10), ...
 'candidate_vsc',d.candidate.vsc(:,[c.AC_MODE c.DC_MODE c.PAC c.QAC c.VAC_INTERNAL]), ...
 'optional_capability_enforce',o.vsc_mtdc.capability_enforce, ...
 'cpf_enforce_q_lims',o.cpf.enforce_q_lims, ...
 'capability_audit',s.evidence.capability_audit,'steps',[], ...
 'corrections',[],'max_fixed_ac_balance',0,'fixed_states',[]);
for k=1:numel(tr.B5TRACE)
 a=tr.B5TRACE{k};
 if strcmp(a.phase,'correction')
  summary.corrections=[summary.corrections; struct('lambda',a.lambda,'iteration',a.iteration,'success',a.ok,'residual',a.normF,'newton_iterations',a.iterations)];
 end
end
for k=1:numel(s.evidence.fixed)
 a=s.evidence.fixed{k}; p=a.result; ac=ext2int(p.ac); v=ac.bus(:,8).*exp(1j*pi/180*ac.bus(:,9));
 bal=norm(v.*conj(makeYbus(ac.baseMVA,ac.bus,ac.branch)*v)-makeSbus(ac.baseMVA,ac.bus,ac.gen),Inf);
 summary.max_fixed_ac_balance=max(summary.max_fixed_ac_balance,bal);
 summary.fixed_states=[summary.fixed_states; struct('lambda',a.lambda,'B',a.B,'vm5',p.ac.bus(p.ac.bus(:,1)==5,8),'success',p.success,'residual',p.convergence.max_mismatch,'ac_balance',bal)];
end
sens=[{struct('options',o,'result',r)} s.evidence.steps];
for k=1:numel(sens)
 a=sens{k}; p=a.result;
 summary.steps=[summary.steps; struct('step',a.options.cpf.step,'accepted',p.cpf.lam(end),'rejected',p.cpf.failure.lambda,'cause',p.cpf.termination.cause,'success',p.success)];
end
args=struct('base',d.decisions{end}.proposed_base,'target',d.decisions{end}.proposed_target,'mpopt',o,'lam',d.lambda,'x',d.x);
args.mpopt.vsc_mtdc.psse_aware=1;
sys=runcpf_vsc_mtdc('__cpf_system',args);
summary.candidate_jacobian_rcond=rcond(full(sys.J));
summary.candidate_full_residual=norm(sys.F,Inf);
summary.last_lambda_tangent=r.cpf.z(end,end);
% Independent fixed-state localization of the voltage-band edge, not a CPF
% target alteration or a stability/nose estimate.
lo=r.cpf.lam(end); hi=d.lambda; roots={};
for k=1:16
 lam=(lo+hi)/2; p=f; p.branch(:,1:13)=r.branch(:,1:13);
 p.bus(:,[3 4])=f.bus(:,[3 4])+lam*(t.bus(:,[3 4])-f.bus(:,[3 4]));
 p.bus(5,6)=15; p.psse.swshunt.num(:,sh.binit_col)=15;
 pf=runpf_vsc_mtdc(p,o); assert(pf.success);
 vm=pf.ac.bus(pf.ac.bus(:,1)==5,8);
 roots{end+1}=struct('input',p,'result',pf,'lambda',lam);
 if vm>=sh.vswlo-sh.vtol,lo=lam;else,hi=lam;end
end
summary.fixed_state_band_edge_bracket=[lo hi];
fid=fopen(fullfile(outdir,'summary.json'),'w');fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));fclose(fid);
save(fullfile(outdir,'summary.mat'),'summary','sys','roots','-v7.3');
disp(summary.fixed_state_band_edge_bracket);
end
