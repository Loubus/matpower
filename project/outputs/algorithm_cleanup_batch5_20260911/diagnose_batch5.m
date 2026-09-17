function evidence=diagnose_batch5(outdir)
assert(~isfolder(outdir)); mkdir(outdir);
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
s=load(fullfile(root,'outputs','algorithm_cleanup_batch4_20260911','beerten_probe.mat'));
tr=load(fullfile(fileparts(mfilename('fullpath')),'trace_01','trace.mat'));
f=s.b4f; t=s.b4t; o=s.b4o; c=idx_vsc;
evidence=struct('fixture',f,'target',t,'options',o,'fixed',{{}},'sensitivity',{{}});
last=tr.b5tr; candidate=tr.B5TRACE{end};
lams=[last.cpf.lam(end) candidate.lambda .411 .42 .45];
sh=mp.psse_swshunt_states(f);
for lam=lams
 for B=[0 5 10 15]
  p=f; p.bus(:,[3 4])=f.bus(:,[3 4])+lam*(t.bus(:,[3 4])-f.bus(:,[3 4]));
  p.branch(:,1:13)=last.branch(:,1:13); p.bus(5,6)=sh.base_bs(5)+B;
  p.psse.swshunt.num(:,sh.binit_col)=B;
  % Explicit fixed-state diagnostic: direct full-equation PF, no automatic
  % tap/shunt settlement. Preserve all original electrical/limit options.
  r=runpf_vsc_mtdc(p,o);
  a=ext2int(r.ac); v=a.bus(:,8).*exp(1j*pi/180*a.bus(:,9));
  ac=norm(v.*conj(makeYbus(a.baseMVA,a.bus,a.branch)*v)-makeSbus(a.baseMVA,a.bus,a.gen),Inf);
  % Reconstruct state from the PF's saved state vector for Jacobian audit.
  item=struct('lambda',lam,'B',B,'input',p,'result',r,'ac_balance',ac);
  evidence.fixed{end+1}=item;
  fprintf('fixed lam=%.12g B=%g success=%d Vm5=%.12g residual=%.3g AC=%.3g\n',lam,B,r.success,r.ac.bus(r.ac.bus(:,1)==5,8),r.convergence.max_mismatch,ac);
 end
end
for step=[.1 .05 .025]
 op=mpoption(o,'cpf.step',step); r=runcpf_psse(f,t,op);
 evidence.sensitivity{end+1}=struct('options',op,'result',r);
 fprintf('step %.5g success=%d accepted=%.12g rejected=%.12g\n',step,r.success,r.cpf.lam(end),r.cpf.failure.lambda);
end
save(fullfile(outdir,'diagnosis.mat'),'evidence','candidate','-v7.3');
end
