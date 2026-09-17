function localize_g2_transition
% Case-specific independent event solve on the incoming PV branch.
% Uses full station equations; this is not a production CPF implementation.
out=fileparts(mfilename('fullpath')); root=fileparts(fileparts(out));
pa=fullfile(root,'outputs','cpf_solution_experiments_20260917','coupled_limit');
addpath(pa); clean=onCleanup(@()rmpath(pa)); %#ok<NASGU>
for step=[100 50]
 d=load(fullfile(out,sprintf('coupled_%03d.mat',step)));
 ck=d.result.cpf.guard_checkpoint;
 assert(~isempty(ck),'Expected a guarded generator transition.');
 ctx=ck.stage.ctx; sd=ck.stage.Sdelta; x=ck.x; lam=ck.lambda;
 baseMVA=ctx.mpc.baseMVA; g=6; qlim=112.5;
 [F,e]=exa_pf('__mismatch',ctx,x,ctx.Sbase+lam*sd);
 assert(norm(F,inf)<1e-7,'Independent frozen-branch model must reproduce checkpoint.');
 for it=1:20
    [H,J,dL,e,qrow]=eq(x,lam);
    if norm(H,inf)<1e-11,break;end
    dx=-[J dL;qrow 0]\H;
    x=x+dx(1:end-1);lam=lam+dx(end);
 end
 [H,J,dL,e,~]=eq(x,lam);
 assert(norm(H,inf)<1e-9,'G2 event root did not converge.');
 oldtan=null(full([J dL])); assert(size(oldtan,2)==1);
 if dot(oldtan,ck.z)<0,oldtan=-oldtan;end
 % Same event state, Q-limited equations. No finite lambda or Q jump.
 p=ctx.mpc; p.bus(:,3:4)=ck.stage.mpcb.bus(:,3:4)+lam*(ck.stage.mpct.bus(:,3:4)-ck.stage.mpcb.bus(:,3:4));
 p.bus(6,2)=1;p.gen(2,3)=qlim;
 nc=exa_pf('__setup',p,d.options); m=nc.model;
 xn=[e.Va(m.nonref);e.Vm(m.vm_vars);e.pac(m.pac_vars);e.vdc_bus(m.dc_var)];
 [Fn,en]=exa_pf('__mismatch',nc,xn,nc.Sbase);
 assert(norm(Fn,inf)<1e-8,'Event must solve both one-sided equation sets.');
 Jn=exa_pf('__jacobian',nc,en,[]);
 % Rebuild transfer on Q-limited equation set; only load varies here.
 pt=p;pt.bus(:,3:4)=pt.bus(:,3:4)+(ck.stage.mpct.bus(:,3:4)-ck.stage.mpcb.bus(:,3:4));
 ntc=exa_pf('__setup',pt,d.options); snd=ntc.Sbase-nc.Sbase;
 F1=exa_pf('__mismatch',nc,xn,nc.Sbase+snd); dLn=F1-Fn;
 newtan=null(full([Jn dLn]));assert(size(newtan,2)==1);
 oldkeys=keys(ctx);newkeys=keys(nc);zt=zeros(size(newtan));zt(end)=oldtan(end);
 [match,where]=ismember(newkeys,oldkeys);zt(find(match))=oldtan(where(match)); %#ok<FNDSB>
 if dot(newtan,zt)<0,newtan=-newtan;end
 v5old=numel(ctx.model.nonref)+find(ctx.model.vm_vars==5);
 v5new=numel(nc.model.nonref)+find(nc.model.vm_vars==5);
 qevent=imag(e.Scalc(g))*baseMVA+p.bus(g,4);
 ev=struct('step',step/1000,'lambda',lam,'P5_MW',p.bus(5,3),'V5',e.Vm(5),'V6',e.Vm(6), ...
    'Qg2',qevent,'PV_residual',norm(H,inf),'PQ_residual',norm(Fn,inf), ...
    'incoming_tlambda',oldtan(end),'outgoing_oriented_tlambda',newtan(end), ...
    'incoming_tV5',oldtan(v5old),'outgoing_oriented_tV5',newtan(v5new), ...
    'mapped_tangent_dot',dot(newtan,zt)/norm(zt), ...
    'PV_J_smallest_singular',min(svd(full(J))),'PQ_J_smallest_singular',min(svd(full(Jn))), ...
    'interpretation','One-sided tangent comparison at the same localized G2 limit; no dynamic stability certification');
 save(fullfile(out,sprintf('localized_event_%03d.mat',step)),'ev','ctx','nc','x','xn','lam','oldtan','newtan');
 fid=fopen(fullfile(out,sprintf('localized_event_%03d.json',step)),'w');fprintf(fid,'%s',jsonencode(ev,PrettyPrint=true));fclose(fid);disp(ev);
end
 function [H,J,dL,e,qrow]=eq(xx,ll)
    [ff,e]=exa_pf('__mismatch',ctx,xx,ctx.Sbase+ll*sd);
    J=exa_pf('__jacobian',ctx,e,[]);
    f1=exa_pf('__mismatch',ctx,xx,ctx.Sbase+(ll+1)*sd);dL=f1-ff;
    H=[ff;imag(e.Scalc(g))+ctx.mpc.bus(g,4)/baseMVA-qlim/baseMVA];
    [da,dm]=dSbus_dV(ctx.Ybus,e.V);
    qrow=[imag(da(g,ctx.model.nonref)) imag(dm(g,ctx.model.vm_vars)) zeros(1,numel(xx)-numel(ctx.model.nonref)-numel(ctx.model.vm_vars))];
 end
end
function out=keys(c)
m=c.model;out=["va:"+string(m.nonref(:));"vm:"+string(m.vm_vars(:));"pac:"+string(m.pac_vars(:));"dc:"+string(m.dc_var(:))];
end
