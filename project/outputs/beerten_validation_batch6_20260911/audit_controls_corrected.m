function audit_controls_corrected(outdir)
% Reconstruct effective preparation as well as the physical control state.
s=load(fullfile(outdir,'scenario.mat'));f=s.base;
sh=mp.psse_swshunt_states(f);xf=mp.psse_xfmr_states(f);
names={'capability_step_100','capability_step_050','capability_step_025','unconstrained'};
all=struct();
for i=1:numel(names)
 name=names{i};
 if strcmp(name,'unconstrained')
  d=load('outputs/algorithm_cleanup_batch5_20260911/pqbrak_off_01/nose_03/nose.mat');o=d.options;
 else
  d=load(fullfile(outdir,[name '.mat']));o=d.o;
 end
 r=d.result; a=cell(1,numel(r.cpf.lam));
 for k=1:numel(a)
  p=f;p.bus=r.cpf.bus(:,:,k);p.gen=r.cpf.gen(:,:,k);p.branch=r.cpf.branch(:,1:13,k);p.vsc=r.cpf.vsc(:,1:29,k);
  p.psse.swshunt.num(:,sh.binit_col)=p.bus(5,6)-sh.base_bs(5);
  p.psse.xfmr.two.num(:,24)=p.branch(xf.branch_idx,9);
  p=mp.psse_prepare_case(p,o,'cpf');
  ctx=runpf_vsc_mtdc_unified('__setup',p,o);xx=r.cpf.x(:,k);xx=xx(isfinite(xx));
  [~,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,xx,[]);
  rr=runpf_vsc_mtdc_unified('__results',ctx,ev,p);
  [next,dec]=mp.psse_unified_control_update(p,rr.ac.bus);
  xs=mp.psse_xfmr_states(p);ss=mp.psse_swshunt_states(p);
  a{k}=struct('lambda',r.cpf.lam(k),'changed',dec.changed, ...
   'acceptance',mp.psse_unified_control_acceptance(dec,'saturate'), ...
   'xfmr_vtol',xs.vtol,'swshunt_vtol',ss.vtol,'V7',p.bus(7,8),'V5',p.bus(5,8), ...
   'tap',p.branch(9,9),'proposed_tap',next.branch(9,9), ...
   'legal_tap',min(abs(xs.states_tap{1}-p.branch(9,9)))<1e-9, ...
   'legal_shunt',ismember(p.bus(5,6),[0 5 10 15]),'shunt',p.bus(5,6), ...
   'locked',dec.xfmr_locked_count>0||dec.swshunt_locked_count>0);
 end
 all.(name)=a;
end
fid=fopen(fullfile(outdir,'control_audit_02.json'),'w');fprintf(fid,'%s',jsonencode(all));fclose(fid);
end
