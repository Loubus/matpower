function evidence=run_event_pf_followup
out=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(fileparts(out)));
s=load(fullfile(root,'outputs','algorithm_cleanup_batch4_20260911','beerten_probe.mat'));
c=idx_vsc; sh=mp.psse_swshunt_states(s.b4f);
evidence=struct('base',s.b4f,'target',s.b4t,'options',s.b4o,'runs',{{}});
summary=struct([]);
for lam=[s.b4r.cpf.lam(end) s.b4r.cpf.failure.lambda]
 for scenario=1:3
  p=s.b4f;
  p.bus(:,[3 4])=s.b4f.bus(:,[3 4])+lam*(s.b4t.bus(:,[3 4])-s.b4f.bus(:,[3 4]));
  if scenario==1
   label='automatic_from_original'; solver=@runpf_psse;
  elseif scenario==2
   label='fixed_original_controls'; solver=@runpf_vsc_mtdc;
  else
   label='fixed_saturated_shunt'; solver=@runpf_vsc_mtdc;
   p.branch(:,1:13)=s.b4r.branch(:,1:13);
   p.bus(5,6)=sh.base_bs(5)+15;
   p.psse.swshunt.num(:,sh.binit_col)=15;
  end
  r=[]; failure=''; started=tic;
  logtext=evalc('try; r=solver(p,s.b4o); catch err; failure=getReport(err,''extended'',''hyperlinks'',''off''); disp(failure); end');
  item=struct('lambda',lam,'scenario',label,'input',p,'result',r,'exception',failure,'seconds',toc(started),'log',logtext);
  a=struct('lambda',lam,'scenario',label,'exception',failure);
  if isempty(failure)
   ac=ext2int(r.ac); v=ac.bus(:,8).*exp(1j*pi/180*ac.bus(:,9));
   acbal=norm(v.*conj(makeYbus(ac.baseMVA,ac.bus,ac.branch)*v)-makeSbus(ac.baseMVA,ac.bus,ac.gen),Inf);
   [~,dcrows]=ismember(r.vsc(:,c.BUSDC),r.busdc(:,1));
   dc=norm(r.busdc(:,3).*(makeGdc(r.busdc,r.branchdc)*r.busdc(:,3))-accumarray(dcrows,r.vsc(:,c.PDC),[size(r.busdc,1) 1])/p.baseMVA,Inf);
   conv=max(abs(sum(r.vsc(:,[c.PAC c.PDC c.PLOSS]),2)))/p.baseMVA;
   a.success=r.success; a.convergence=r.convergence;
   a.vm5=r.ac.bus(r.ac.bus(:,1)==5,8); a.B=r.ac.bus(r.ac.bus(:,1)==5,6);
   a.tap=r.branch(9,9); a.ac_balance=acbal; a.dc_balance=dc; a.converter_balance=conv;
   a.capability=check_capability_limits(r);
  end
  evidence.runs{end+1}=item;
  if isempty(summary),summary=a;else,summary(end+1)=a;end
  fprintf('%s lambda=%.15g\n',label,lam);disp(a);
 end
end
save(fullfile(out,'results.mat'),'evidence','summary','-v7.3');
fid=fopen(fullfile(out,'summary.json'),'w');fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));fclose(fid);
end
