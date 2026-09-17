function [checks,results] = t_beerten_capability_batch6(quiet,outdir)
% Equipment and full-model control handoff after genuine Beerten limits.
if nargin<1,quiet=0;end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<2,outdir=tempname(fullfile(root,'outputs'));end
assert(~isfolder(outdir),'Use a fresh output directory');mkdir(outdir);
s=load(fullfile(root,'outputs/algorithm_cleanup_batch4_20260911/beerten_probe.mat'));
f=s.b4f;t=s.b4t;
o=mpoption(s.b4o,'cpf.stop_at','NOSE','exp.psse_pqbrak',0, ...
 'vsc_mtdc.psse_control_limit','saturate','vsc_mtdc.capability_enforce',1, ...
 'vsc_mtdc.capability_gen_enforce',1,'cpf.enforce_q_lims',1);
checks=struct('id',{},'passed',{});results=cell(1,2);
sh=mp.psse_swshunt_states(f);xf=mp.psse_xfmr_states(f);c=idx_vsc;
steps=[.1 .025];
for j=1:2
 opt=mpoption(o,'cpf.step',steps(j));r=runcpf_psse(f,t,opt);results{j}=r;
 check(sprintf('step%d_limit_is_not_nose',j),strcmp(r.cpf.termination.cause,'vsc_capability_limit') && ...
  ~r.cpf.termination.nose_detected && ~r.cpf.termination.requested_endpoint_reached);
 check(sprintf('step%d_genuine_switches',j),any(strcmp({r.cpf.events.name},'GEN_CAPABILITY')) && ...
  any(strcmp({r.cpf.events.name},'VSC_CAPABILITY')) && ~any(contains({r.cpf.events.name},'FREEZE')));
 for k=1:numel(r.cpf.lam)
  p=f;p.bus=r.cpf.bus(:,:,k);p.gen=r.cpf.gen(:,:,k);p.branch=r.cpf.branch(:,1:13,k);p.vsc=r.cpf.vsc(:,:,k);
  p.psse.swshunt.num(:,sh.binit_col)=p.bus(5,6)-sh.base_bs(5);
  p.psse.xfmr.two.num(:,24)=p.branch(xf.branch_idx,9);
  p=mp.psse_prepare_case(p,opt,'cpf');
  ctx=runpf_vsc_mtdc_unified('__setup',p,opt);xx=r.cpf.x(:,k);xx=xx(isfinite(xx));
  [F,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,xx,[]);full=runpf_vsc_mtdc_unified('__results',ctx,ev,p);
  [~,decision]=mp.psse_unified_control_update(p,full.ac.bus);
  accept=mp.psse_unified_control_acceptance(decision,'saturate');
  tag=sprintf('step%d_point%d_',j,k);
  check([tag 'settled_after_capability'],accept.accepted && ~decision.changed);
  check([tag 'equations'],norm(F,Inf)<1e-8);
  [~,~,~,~,gi]=gen_capability_curve(p.gen(2,2),p.gen(2,3),f.gen(2,7),2);
  va=check_vsc_capability(p);
  check([tag 'original_non_slack_capabilities'],gi.projection_norm<=1e-8 && all([va.elements.margin]>=-1e-8));
  check([tag 'constant_load_and_original_station'],max(abs(p.bus(:,3:4)-f.bus(:,3:4)-r.cpf.lam(k)*(t.bus(:,3:4)-f.bus(:,3:4))),[],'all')<1e-10 && ...
   isequal(p.vsc(:,c.LOSS_A:c.REACTOR_RATE_C),f.vsc(:,c.LOSS_A:c.REACTOR_RATE_C)));
 end
end
check('step_terminal_loading_agreement',abs(results{1}.cpf.lam(end)-results{2}.cpf.lam(end))<o.cpf.target_lam_tol);
check('original_slack_curve_conflict_visible',results{1}.cpf.gen(1,2,1)>.8*f.gen(1,7));
save(fullfile(outdir,'evidence.mat'),'checks','results','o','f','t','-v7.3');
fid=fopen(fullfile(outdir,'checks.json'),'w');fprintf(fid,'%s',jsonencode(checks));fclose(fid);
t_begin(numel(checks),quiet);for k=1:numel(checks),t_ok(checks(k).passed,checks(k).id);end;t_end;
 function check(id,passed)
  checks(end+1)=struct('id',id,'passed',logical(passed));
 end
end
