function evidence = t_vsc_directional_losses(outdir)
% Directional losses: independent formulas, derivatives, PF/CPF and persistence.
if nargin<1, outdir=tempname; end
if ~isfolder(outdir), mkdir(outdir); end
clear calc_vsc_losses vsc_loss_coefficients runpf_vsc_mtdc runpf_vsc_mtdc_unified runcpf_vsc_mtdc savecase
c=idx_vsc; b=case5_vsc_mtdc_beerten;
o=mpoption('verbose',0,'out.all',0); o.vsc_mtdc.method='unified';
checks=struct('name',{},'passed',{},'error',{});
d=b; d.vsc_loss=struct('c_positive',.08,'c_negative',.12);
P=[-40;0;40]; Q=[30;30;30]; U=ones(3,1);
[L,I]=calc_vsc_losses(100,P,Q,U,d.vsc,d);
expected=d.vsc(:,c.LOSS_A)+d.vsc(:,c.LOSS_B).*[.5;.3;.5]+[.12;.10;.08].*[.25;.09;.25];
ck('both_directions_and_zero_reactive_operation',max(abs(L-expected))<1e-13,max(abs(L-expected)));
ck('current_definition',max(abs(I-[.5;.3;.5]))<1e-13,max(abs(I-[.5;.3;.5])));
legacy=calc_vsc_losses(100,P,Q,U,b.vsc);
same=b; same.vsc_loss=struct('c_positive',b.vsc(:,c.LOSS_C),'c_negative',b.vsc(:,c.LOSS_C));
ck('equal_coefficients_exact_legacy_compatibility',isequal(legacy,calc_vsc_losses(100,P,Q,U,b.vsc,same)),0);
bad=d; bad.vsc_loss.c_negative=[.1 .2];
rejected=false; try, calc_vsc_losses(100,P,Q,U,b.vsc,bad); catch e, rejected=strcmp(e.identifier,'vsc_loss_coefficients:metadata'); end
ck('invalid_coefficient_shape_rejected',rejected,0);
bad=d; bad.vsc_loss.c_positive=NaN;
rejected=false; try, calc_vsc_losses(100,P,Q,U,b.vsc,bad); catch e, rejected=strcmp(e.identifier,'vsc_loss_coefficients:metadata'); end
ck('nonfinite_coefficients_rejected',rejected,0);

solutions=cell(2,2);
for direction=1:2
    f=d;
    if direction==2, f.vsc([1 3],c.PAC_SET)=[40;-35]; end
    for method=1:2
        om=o;
        if method==2, om.vsc_mtdc.method='sequential'; end
        r=runpf_vsc_mtdc(f,om); solutions{direction,method}=r;
        ck(sprintf('direction_%d_method_%d_success',direction,method),r.success,0);
        coeff=.12*ones(3,1); coeff(r.vsc(:,c.PCONV)>0)=.08;
        ii=hypot(r.vsc(:,c.PCONV),r.vsc(:,c.QCONV))./(100*r.vsc(:,c.VAC_INTERNAL));
        expected=f.vsc(:,c.LOSS_A)+f.vsc(:,c.LOSS_B).*ii+coeff.*ii.^2;
        err=max(abs(expected-r.vsc(:,c.PLOSS)));
        ck(sprintf('direction_%d_method_%d_independent_loss',direction,method),err<1e-6,err);
        err=max(abs(r.vsc(:,c.PCONV)+r.vsc(:,c.PDC)+r.vsc(:,c.PLOSS)));
        ck(sprintf('direction_%d_method_%d_power_balance',direction,method),err<2e-6,err);
    end
    err=max(abs(solutions{direction,1}.vsc(:,[c.PAC c.QAC c.PCONV c.PDC])- ...
        solutions{direction,2}.vsc(:,[c.PAC c.QAC c.PCONV c.PDC])),[],'all');
    ck(sprintf('direction_%d_solver_agreement',direction),err<2e-5,err);
end
legacy_result=runpf_vsc_mtdc(b,o);
equal_result=runpf_vsc_mtdc(same,o);
ck('equal_coefficients_identical_PF',isequal(legacy_result.vsc,equal_result.vsc),0);
% Station copper loss can reverse the sign between PCC and internal terminal.
near=d; near.vsc(1,c.PAC_SET)=-.001;
rn=runpf_vsc_mtdc(near,o);
ck('direction_selector_uses_internal_not_PCC_sign',rn.success && ...
    rn.vsc(1,c.PAC)<0 && rn.vsc(1,c.PCONV)>0,0);
ii=hypot(rn.vsc(1,c.PCONV),rn.vsc(1,c.QCONV))/(100*rn.vsc(1,c.VAC_INTERNAL));
err=abs(rn.vsc(1,c.PLOSS)-(near.vsc(1,c.LOSS_A)+near.vsc(1,c.LOSS_B)*ii+.08*ii^2));
ck('opposite_port_signs_select_positive_internal_coefficient',err<1e-9,err);

% Full analytic residual Jacobian, hard branches and continuous transition.
for width=[0 100]
    f=d; f.vsc_loss.transition_MW=width;
    ctx=runpf_vsc_mtdc_unified('__setup',f,o);
    x=ctx.x0; [~,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,x,[]);
    J=runpf_vsc_mtdc_unified('__jacobian',ctx,ev,[]); Jfd=zeros(size(J));
    for j=1:numel(x)
        h=1e-6; xp=x; xm=x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
        Jfd(:,j)=(runpf_vsc_mtdc_unified('__mismatch',ctx,xp,[])- ...
            runpf_vsc_mtdc_unified('__mismatch',ctx,xm,[]))/(2*h);
    end
    err=norm(J-Jfd,inf)/max(1,norm(Jfd,inf));
    ck(sprintf('analytic_jacobian_width_%g',width),err<2e-6,err);
end
f=d; f.vsc_loss.transition_MW=2;
for p=[-2 -1 0 1 2]
    pv=repmat(p,3,1); [~,der]=vsc_loss_coefficients(f.vsc,pv,f);
    fd=(vsc_loss_coefficients(f.vsc,pv+1e-6,f)-vsc_loss_coefficients(f.vsc,pv-1e-6,f))/2e-6;
    ck(sprintf('coefficient_derivative_P_%g',p),max(abs(fd-der))<2e-8,max(abs(fd-der)));
end

% Independent CPF solves at the same endpoint; crosses INTERNAL Pc=0 with Q!=0.
f=d; f.vsc_loss.transition_MW=2; f.vsc(1,c.PAC_SET)=-10;
t=f; t.vsc(1,c.PAC_SET)=10; t.bus(:,3:4)=1.05*t.bus(:,3:4);
oc=mpoption(o,'cpf.stop_at',1,'cpf.step',.1);
rc=runcpf_vsc_mtdc(f,t,oc); endpoint=runpf_vsc_mtdc(t,o);
ck('cpf_smooth_power_reversal_success',rc.success && endpoint.success,0);
pc=squeeze(rc.cpf.vsc(1,c.PCONV,:));
ck('cpf_actually_crossed_internal_power_zero',min(pc)<0 && max(pc)>0,0);
err=max(abs(rc.cpf.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS],end)-endpoint.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS])),[],'all');
ck('cpf_endpoint_matches_independent_PF',err<2e-5,err);
for j=1:size(rc.cpf.vsc,3)
    vr=rc.cpf.vsc(:,:,j);
    expected=calc_vsc_losses(100,vr(:,c.PCONV),vr(:,c.QCONV),vr(:,c.VAC_INTERNAL),f.vsc,f);
    err=max(abs(expected-vr(:,c.PLOSS)));
    ck(sprintf('cpf_loss_path_point_%d',j),err<2e-6,err);
end
bad=t; bad.vsc_loss.c_negative=.13;
rejected=false; try, runcpf_vsc_mtdc(f,bad,oc); catch e, rejected=contains(e.message,'directional loss data must match'); end
ck('cpf_changed_equipment_data_rejected',rejected,0);
ocs=oc; ocs.vsc_mtdc.method='sequential';
rcs=runcpf_vsc_mtdc(f,t,ocs);
ck('sequential_cpf_smooth_reversal_success',rcs.success,0);
pcs=squeeze(rcs.cpf.vsc(1,c.PCONV,:));
ck('sequential_cpf_crossed_internal_power_zero',min(pcs)<0 && max(pcs)>0,0);
err=max(abs(rcs.cpf.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS],end)-endpoint.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS])),[],'all');
ck('sequential_cpf_endpoint_matches_unified_PF',err<2e-5,err);
fn=fullfile(outdir,'directional_roundtrip.m'); savecase(fn,f); rt=loadcase(fn);
ck('directional_metadata_savecase_roundtrip',isequal(rt.vsc_loss,f.vsc_loss),0);
rtr=runpf_vsc_mtdc(rt,o); rr=runpf_vsc_mtdc(f,o);
err=max(abs(rtr.vsc(:)-rr.vsc(:)));
ck('roundtrip_solution',rtr.success && err<1e-9,err);

evidence=struct('checks',checks,'passed',sum([checks.passed]),'failed',sum(~[checks.passed]));
save(fullfile(outdir,'directional_regression.mat'),'evidence','solutions','rc','rcs','endpoint');
fid=fopen(fullfile(outdir,'directional_regression.json'),'w');
fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true)); fclose(fid);
fprintf('DIRECTIONAL_LOSS_TESTS: %d passed, %d failed\n',evidence.passed,evidence.failed);
assert(evidence.failed==0,'Directional-loss regression failed; inspect saved checks.');
    function ck(name,passed,error_value)
        checks(end+1)=struct('name',name,'passed',logical(passed),'error',error_value);
        if ~passed, fprintf('FAILED: %s, error=%g\n',name,error_value); end
    end
end
