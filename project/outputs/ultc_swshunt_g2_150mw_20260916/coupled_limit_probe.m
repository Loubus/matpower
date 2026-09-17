function evidence=coupled_limit_probe(failure,seed,baseMVA,label)
% Diagnostic only: solve the same full station/network with |Ic2|=Imax,
% replacing the fixed-Q2 equation. No production solver/case is modified.
p=failure.base; t=failure.target; lam=failure.lambda;
p.bus(:,3:4)=p.bus(:,3:4)+lam*(t.bus(:,3:4)-p.bus(:,3:4));
p.gen(:,2:3)=p.gen(:,2:3)+lam*(t.gen(:,2:3)-p.gen(:,2:3));
p.vsc(:,6:11)=p.vsc(:,6:11)+lam*(t.vsc(:,6:11)-p.vsc(:,6:11));
opt=failure.options; opt.vsc_mtdc.psse_aware=0;
ctx=runpf_vsc_mtdc_unified('__setup',p,opt);
row=numel(ctx.model.nonref)+find(ctx.model.qeq==ctx.model.map.internal(2));
assert(isscalar(row)); imax=150/baseMVA;
x=seed; history=[];
for it=0:59
    [F,e]=equations(x); nf=norm(F,inf);
    history(end+1,:)=[it nf e.Vm(ctx.model.map.pcc(2)) e.qs(2) e.iac(2)/imax]; %#ok<AGROW>
    if nf<1e-9, break; end
    J=runpf_vsc_mtdc_unified('__jacobian',ctx,e,[]);
    for j=1:numel(x)
        h=1e-6*max(1,abs(x(j))); xp=x; xm=x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
        fp=equations(xp); fm=equations(xm); J(row,j)=(fp(row)-fm(row))/(2*h);
    end
    dx=-J\F; accepted=false;
    for ls=0:14
        xt=x+dx/(2^ls); ft=equations(xt);
        if norm(ft,inf)<nf, x=xt; accepted=true; break; end
    end
    if ~accepted, break; end
end
[F,e]=equations(x);
rr=runpf_vsc_mtdc_unified('__results',ctx,e,[]);
[~,br]=ismember(p.bus(:,1),rr.ac.bus(:,1));
rr.bus=rr.ac.bus(br,:); rr.gen=rr.ac.gen(1:size(p.gen,1),:);
rr.branch=rr.ac.branch(1:size(p.branch,1),:);
cap=check_vsc_capability(rr);
[~,controls]=mp.psse_unified_control_update(rr,rr.bus);
acceptance=mp.psse_unified_control_acceptance(controls,'saturate');
evidence=struct('label',label,'lambda',lam,'success',norm(F,inf)<1e-9,'residual',norm(F,inf), ...
    'V5',e.Vm(5),'Vpcc2',e.Vm(ctx.model.map.pcc(2)),'Q2',e.qs(2),'P2',e.ps(2), ...
    'I2_ratio',e.iac(2)/imax,'history',history,'x',x,'point',p, ...
    'converter_audit',cap,'control_acceptance',acceptance,'result',rr);
% Frozen-Q diagnostic at the projected order: same starting state and Newton
% method, but keep the actual fixed-Q equation. This is not a CPF rerun.
xf=seed; f_history=[];
for it=0:59
    [F,ef]=runpf_vsc_mtdc_unified('__mismatch',ctx,xf,[]); nf=norm(F,inf);
    f_history(end+1,:)=[it nf]; %#ok<AGROW>
    if nf<1e-9 || isempty(ef), break; end
    J=runpf_vsc_mtdc_unified('__jacobian',ctx,ef,[]); dx=-J\F; accepted=false;
    for ls=0:14
        xt=xf+dx/(2^ls); ft=runpf_vsc_mtdc_unified('__mismatch',ctx,xt,[]);
        if norm(ft,inf)<nf, xf=xt; accepted=true; break; end
    end
    if ~accepted, break; end
end
evidence.fixed_Q_probe=struct('Q_order',p.vsc(2,7),'success',nf<1e-9,'residual',nf,'history',f_history);

    function [F,e]=equations(xx)
        [F,e]=runpf_vsc_mtdc_unified('__mismatch',ctx,xx,[]);
        if ~isempty(e), F(row)=e.iac(2)^2-imax^2; end
    end
end
