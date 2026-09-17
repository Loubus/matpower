function diagnose_projected_turn(suffix)
if nargin<1,suffix='';end
out=fileparts(mfilename('fullpath'));d=load(fullfile(out,['instrumented' suffix '.mat']));ck=d.nt_r.cpf.pj_checkpoint;
ctx=ck.stage.ctx;sd=ck.stage.Sdelta;x0=ck.x;lam0=ck.lambda;z0=ck.z;
c=idx_vsc;k=2;Imax=1.5;
[F,~,~,~]=eq(x0,lam0);assert(norm(F,inf)<1e-8,'Frozen branch must match checkpoint.');
% Locate the current boundary on the incoming, fixed-Q network branch.
x=x0;lam=lam0;
for it=1:15
 [F,e,J,dL]=eq(x,lam);[g,dg]=current(e);
 H=[F;g];if norm(H,inf)<1e-11,break;end
 dx=-[J dL;dg 0]\H;x=x+dx(1:end-1);lam=lam+dx(end);
end
[F,e,J,dL]=eq(x,lam);[g,~]=current(e);ze=direction(J,dL);
assert(norm([F;g],inf)<1e-9,'Current-boundary solve failed.');
event=point(x,lam,e,ze,norm(F,inf));event.current_equation_residual=g;
% A smooth fold of these fixed-Q equations may lie beyond the current bound.
[~,~,~,za]=arc(0);hhi=.002;[~,~,~,zb]=arc(hhi);
while zb(end)>0 && hhi<.064
 hhi=2*hhi;[~,~,~,zb]=arc(hhi);
end
assert(za(end)>0 && zb(end)<0,'Expected local smooth-fold bracket.');
h=fzero(@fold_function,[0 hhi],optimset('TolX',1e-11));
[xf,lf,ef,zf]=arc(h);[Ff,~,~,~]=eq(xf,lf);fold=point(xf,lf,ef,zf,norm(Ff,inf));
% Save the actual settled outgoing state from the vanishing-step trial.
[Fn,en]=runpf_vsc_mtdc_unified('__mismatch',ck.new_ctx,ck.new_x, ...
 ck.new_ctx.Sbase+ck.new_lambda*ck.new_sd);
post=point(ck.new_x,ck.new_lambda,en,ck.new_z,norm(Fn,inf));
post.Q2_set=ck.candidate.vsc(2,c.QAC_SET);post.Q2=ck.candidate.vsc(2,c.QAC);
post.delta_Q2=post.Q2-ck.last.vsc(2,c.QAC);
post.delta_lambda=post.lambda-event.lambda;
summary=struct('incoming_boundary',event,'frozen_Q_smooth_fold',fold,'projected_outgoing',post, ...
 'Q_before',ck.last.vsc(2,c.QAC),'Q_projection_fraction',-post.delta_Q2/ck.last.vsc(2,c.QAC));
fid=fopen(fullfile(out,['diagnosis' suffix '.json']),'w');fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true));fclose(fid);
save(fullfile(out,['diagnosis' suffix '.mat']),'summary','event','fold','post','x','lam','xf','lf','h');disp(summary);
fprintf('BOUNDARY lambda %.12f V5 %.12f I %.12f tlam %.12g\n',event.lambda,event.V5,event.I2_over_limit,event.tlambda);
fprintf('FROZEN-Q FOLD lambda %.12f V5 %.12f I %.12f tlam %.12g\n',fold.lambda,fold.V5,fold.I2_over_limit,fold.tlambda);
fprintf('JUMP lambda %.12f V5 %.12f I %.12f dQ %.12f tlam %.12g\n',post.lambda,post.V5,post.I2_over_limit,post.delta_Q2,post.tlambda);
 function [F,e,J,dL]=eq(xx,ll)
  [F,e]=runpf_vsc_mtdc_unified('__mismatch',ctx,xx,ctx.Sbase+ll*sd);
  J=runpf_vsc_mtdc_unified('__jacobian',ctx,e,[]);
  F1=runpf_vsc_mtdc_unified('__mismatch',ctx,xx,ctx.Sbase+(ll+1)*sd);dL=F1-F;
 end
 function [g,dg]=current(e)
  m=ctx.model;nva=numel(m.nonref);nvm=numel(m.vm_vars);nx=numel(x0);
  [da,dm]=dSbus_dV(ctx.Ybus,e.V);row=m.map.internal(k);
  dq=[imag(da(row,m.nonref)) imag(dm(row,m.vm_vars)) zeros(1,nx-nva-nvm)]*ctx.mpc.baseMVA;
  dp=zeros(1,nx);dp(nva+nvm+find(m.pac_vars==k))=1;
  du=zeros(1,nx);du(nva+find(m.vm_vars==row))=1;U=e.Vm(row);B=ctx.mpc.baseMVA;
  g=(e.iac(k)/Imax)^2-1;
  dg=2*(e.pac(k)*dp+e.qac(k)*dq)/(B*U*Imax)^2-2*e.iac(k)^2/(U*Imax^2)*du;
 end
 function z=direction(J,dL)
  z=null(full([J dL]));assert(size(z,2)==1);if dot(z,z0)<0,z=-z;end
 end
 function [xx,ll,e,z]=arc(hh)
  y=[x0;lam0]+hh*z0;
  for n=1:20
   [ff,ee,jj,dl]=eq(y(1:end-1),y(end));H=[ff;z0'*(y-[x0;lam0])-hh];
   if norm(H,inf)<1e-11,break;end
   y=y-[jj dl;z0']\H;
  end
  assert(norm(H,inf)<1e-9,'Arc solve failed');xx=y(1:end-1);ll=y(end);e=ee;z=direction(jj,dl);
 end
 function val=fold_function(hh)
  [~,~,~,zz]=arc(hh);val=zz(end);
 end
 function p=point(xx,ll,e,zz,res)
  p=struct('lambda',ll,'V5',e.Vm(5),'I2_over_limit',e.iac(2)/Imax,'tlambda',zz(end), ...
   'residual',res,'state_dimension',numel(xx));
 end
end
