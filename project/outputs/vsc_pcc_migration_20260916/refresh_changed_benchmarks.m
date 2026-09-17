function refresh_changed_benchmarks
out=fileparts(mfilename('fullpath'));o=mpoption('verbose',0,'out.all',0);
b=case5_vsc_mtdc_beerten;t=b;t.bus(:,3:4)=2*b.bus(:,3:4);
on=mpoption(o,'cpf.stop_at','NOSE','cpf.step',.1,'cpf.step_max',.25,'cpf.adapt_step',1);
on.vsc_mtdc.cpf_max_lam=20;on.vsc_mtdc.cpf_max_it=120;
rn=cell(1,2);nose=zeros(1,2);singular=zeros(1,2);residual=zeros(1,2);
for k=1:2
    if k==2
        on.cpf.step=.05;on.cpf.step_max=.125;
        % Half-size continuation steps require twice the accepted-step budget.
        on.vsc_mtdc.cpf_max_it=240;
    end
    rn{k}=runcpf_psse(b,t,on);r=rn{k};nose(k)=r.cpf.max_lam;
    assert(r.cpf.termination.nose_detected && r.cpf.termination.requested_endpoint_reached, ...
        'Configured-stop success alone is not a located nose');
    f=b;f.bus=r.bus;f.gen=r.gen;f.branch=r.branch(:,1:13);f.vsc=r.vsc;
    ctx=runpf_vsc_mtdc_unified('__setup',f,on);x=r.cpf.x(:,end);x=x(isfinite(x));
    [F,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,x,[]);
    J=runpf_vsc_mtdc_unified('__jacobian',ctx,ev,[]);
    sv=svd(J);singular(k)=sv(end)/sv(1);residual(k)=norm(F,Inf);
    fprintf('NOSE%d success=%d lambda=%.12f residual=%g singular_ratio=%g\n',k,r.success,nose(k),residual(k),singular(k));
end
f=case5_vsc_mtdc_beerten_ultc_swshunt;g=f;g.bus(:,3:4)=2*f.bus(:,3:4);
op=mpoption(o,'cpf.stop_at','FULL','cpf.step',.05,'cpf.step_min',1e-4,'cpf.step_max',.15, ...
    'cpf.adapt_step',1,'cpf.parameterization',3);
op.vsc_mtdc.cpf_max_lam=20;op.vsc_mtdc.cpf_max_it=260;op.vsc_mtdc.psse_control_max_it=60;
op.vsc_mtdc.psse_control_limit='stop';
rp=runcpf_psse(f,g,op);
fprintf('CONTROL success=%d lambda=%.12f shunt=%g tap=%.12f\n',rp.success,rp.cpf.max_lam,rp.bus(5,6),rp.branch(rp.psse.xfmr.two.branch_idx,9));
% Fresh PF on either side of the located control boundary.
ok=zeros(1,2); shift=[-1e-4 1e-4];
for k=1:2
    test=f;test.bus(:,3:4)=f.bus(:,3:4)*(1+rp.cpf.max_lam+shift(k));
    trial=runpf_psse(test,op);ok(k)=trial.success;
end
summary=struct('nose_lambda',nose,'nose_step_agreement',abs(diff(nose)), ...
    'nose_residual',residual,'nose_singular_ratio',singular, ...
    'nose_is_hardware_margin',false,'control_lambda',rp.cpf.max_lam, ...
    'control_shunt',rp.bus(5,6),'control_tap',rp.branch(rp.psse.xfmr.two.branch_idx,9), ...
    'control_pf_below_above',ok);
fid=fopen(fullfile(out,'changed_benchmarks.json'),'w');fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true));fclose(fid);
save(fullfile(out,'changed_benchmarks.mat'),'rn','rp','summary');
disp(summary);
assert(all([rn{1}.success rn{2}.success]) && abs(diff(nose))<1e-6 && all(residual<1e-8));
assert(rp.success && isequal(ok,[1 0]),'Control boundary failed fresh PF bracketing');
end
