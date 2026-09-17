function evidence = t_vsc_pcc_station(outdir)
% Port migration and independent full-station physics regression.
if nargin<1, outdir=tempname; end
if ~isfolder(outdir), mkdir(outdir); end
clear runpf_vsc_mtdc runpf_vsc_mtdc_unified runcpf_vsc_mtdc idx_vsc
c=idx_vsc; o=mpoption('verbose',0,'out.all',0);
b=case5_vsc_mtdc_beerten;
checks=struct('name',{},'passed',{},'error',{}); solutions=cell(1,5);
for scenario=1:5
    f=b;
    if scenario==2 || scenario==3
        f.vsc(:,[c.TR_R c.TR_X c.FILTER_G c.FILTER_B c.REACTOR_R c.REACTOR_X]) = ...
            repmat([.0015 .1121 .002 .0887 .0001 .16428],3,1);
    end
    if scenario==3
        f.vsc(:,[c.TR_B c.REACTOR_B c.TR_SHIFT])=repmat([.013 .017 8],3,1);
    elseif scenario==4
        f.vsc(3,c.AC_MODE)=c.VSC_AC_PV; f.vsc(3,c.VAC_SET)=1.01;
    elseif scenario==5
        f.vsc(1,c.AC_MODE)=c.VSC_AC_Q; f.vsc(1,c.DC_MODE)=c.VSC_DC_DROOP;
        f.vsc(1,c.KDROOP)=35;
    end
    r=runpf_vsc_mtdc(f,o); solutions{scenario}=r;
    ck(sprintf('s%d_unified_success',scenario),r.success,0);
    os=o; os.vsc_mtdc.method='sequential';
    % Filtered high-impedance fixed-point iteration needs more than the
    % default 20 iterations; keep electrical tolerances unchanged.
    if scenario==2 || scenario==3, os.vsc_mtdc.max_it=100; end
    rs=runpf_vsc_mtdc(f,os);
    ck(sprintf('s%d_sequential_success',scenario),rs.success,0);
    err=max(abs(r.vsc(:,[c.PAC c.QAC c.PCONV c.QCONV c.PDC])- ...
        rs.vsc(:,[c.PAC c.QAC c.PCONV c.QCONV c.PDC])),[],'all');
    ck(sprintf('s%d_methods_agree',scenario),err<2e-5,err);
    for k=1:3
        v=r.vsc(k,:); tr=r.ac.branch(v(c.TR_BRANCH),:); rr=r.ac.branch(v(c.REACTOR_BRANCH),:);
        % Independent readings from explicit branch flows and bus phasors.
        err=max(abs(v([c.PAC c.QAC])+tr([14 15])));
        ck(sprintf('s%d_c%d_pcc_port',scenario,k),err<1e-9,err);
        err=max(abs(v([c.PCONV c.QCONV])-rr([16 17])));
        ck(sprintf('s%d_c%d_internal_port',scenario,k),err<1e-6,err);
        err=abs(v(c.PCONV)+v(c.PDC)+v(c.PLOSS));
        ck(sprintf('s%d_c%d_bridge_balance',scenario,k),err<1e-6,err);
        pfix=any(f.vsc(k,c.AC_MODE)==[c.VSC_AC_PQ c.VSC_AC_PV]);
        qfix=any(f.vsc(k,c.AC_MODE)==[c.VSC_AC_PQ c.VSC_AC_Q]);
        if pfix, err=abs(v(c.PAC)-f.vsc(k,c.PAC_SET)); ck(sprintf('s%d_c%d_P_order',scenario,k),err<1e-6,err); end
        if qfix, err=abs(v(c.QAC)-f.vsc(k,c.QAC_SET)); ck(sprintf('s%d_c%d_Q_order',scenario,k),err<1e-6,err); end
        m=vsc_station_map(v,r.baseMVA,r.baseMVA);
        ip=find(r.ac.bus(:,1)==v(c.VSC_BUS)); ii=find(r.ac.bus(:,1)==v(c.INTERNAL_BUS));
        us=r.ac.bus(ip,8)*exp(1j*pi/180*r.ac.bus(ip,9));
        uc=r.ac.bus(ii,8)*exp(1j*pi/180*r.ac.bus(ii,9));
        is=conj(complex(v(c.PAC),v(c.QAC))/r.baseMVA/us);
        ic=conj(complex(rr(16),rr(17))/r.baseMVA/uc);
        err=max(abs([m.D*us+m.E*is-uc,m.B*us+m.A*is-ic]));
        ck(sprintf('s%d_c%d_map_vs_network',scenario,k),err<1e-8,err);
        [~,~,~,~,ci]=vsc_capability_curve(v(c.PAC),v(c.QAC),150,abs(us),v,'preservar_p',1.15,r.baseMVA);
        err=max(abs([ci.converter_current_pu-abs(ic)*r.baseMVA/150, ci.converter_voltage_pu-abs(uc)]));
        ck(sprintf('s%d_c%d_capability_vs_network',scenario,k),err<1e-8,err);
        filterloss=f.vsc(k,c.FILTER_G)*r.baseMVA*v(c.VAC_FILTER)^2;
        err=abs(v(c.PCONV)-v(c.PAC)-sum(tr([14 16]))-sum(rr([14 16]))-filterloss);
        ck(sprintf('s%d_c%d_station_balance',scenario,k),err<1e-6,err);
    end
    ctx=runpf_vsc_mtdc_unified('__setup',f,o);
    x=ctx.x0; [~,ev]=runpf_vsc_mtdc_unified('__mismatch',ctx,x,[]);
    J=runpf_vsc_mtdc_unified('__jacobian',ctx,ev,[]); Jfd=zeros(size(J));
    for j=1:numel(x)
        h=1e-6*max(1,abs(x(j))); xp=x; xm=x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
        Jfd(:,j)=(runpf_vsc_mtdc_unified('__mismatch',ctx,xp,[])- ...
            runpf_vsc_mtdc_unified('__mismatch',ctx,xm,[]))/(2*h);
    end
    err=max(abs(J-Jfd)./max(1,abs(Jfd)),[],'all');
    ck(sprintf('s%d_analytic_jacobian',scenario),err<2e-6,err);
end
% Zero and near-zero station elements: independent ideal limiting equations.
row=b.vsc(2,:); row([c.TR_R c.TR_X c.FILTER_G c.FILTER_B c.REACTOR_R c.REACTOR_X c.TR_B c.REACTOR_B c.TR_SHIFT])=0;
for z=[0 1e-14 1e-8 .0001]
    row(c.TR_X)=z; row(c.REACTOR_X)=z;
    [sat,p,q,~,ci]=vsc_capability_curve(90,90,100,1,row,'preservar_p',1.15,100);
    ck(sprintf('zero_limit_%g',z),sat && ci.inside_final && abs(p-90)<1e-9 && abs(hypot(p,q)-100)<1e-7,abs(hypot(p,q)-100));
end
% Both branches ideal but nonzero filter: converter current includes filter.
row(c.TR_X)=0; row(c.REACTOR_X)=0; row(c.FILTER_B)=.2;
[sat,~,~,~,ci]=vsc_capability_curve(0,110,100,1,row,'preservar_p',1.15,100);
ck('ideal_filter_current_offset',~sat && abs(ci.converter_current_pu-.9)<1e-12,abs(ci.converter_current_pu-.9));
% Origin outside voltage disk: radial feasibility is an interval, not [0,a].
row(c.FILTER_B)=0; row(c.REACTOR_X)=.2;
[sat,~,~,~,ci]=vsc_capability_curve(0,-200,100,1.2,row,'radial',1.15,100);
ck('radial_origin_outside',sat && ci.inside_final && ci.radial_scale>0,0);
% No impedance means a fixed internal voltage: report an empty region.
row(c.REACTOR_X)=0; caught=false;
try, vsc_capability_curve(0,0,100,1.2,row,'preservar_p',1.15,100);
catch ME, caught=contains(ME.identifier,'infeasible'); end
ck('ideal_voltage_infeasible',caught,0);
% Independent current and voltage boundary samples, with a filter and R.
row=solutions{3}.vsc(1,:); m=vsc_station_map(row,100,150); V=1.01;
errI=0; errV=0;
for th=linspace(0,2*pi,121)
    sp=conj((exp(1j*th)-m.B*V)*V/m.A);
    errI=max(errI,abs(abs(m.A*conj(sp)/V+m.B*V)-1));
    sp=conj((1.15*exp(1j*th)-m.D*V)*V/m.E);
    errV=max(errV,abs(abs(m.E*conj(sp)/V+m.D*V)-1.15));
end
ck('current_boundary_physics',errI<1e-12,errI); ck('voltage_boundary_physics',errV<1e-12,errV);
% CPF with pure five-bus data, constant PCC orders and changing load.
t=b; t.bus(5,3:4)=t.bus(5,3:4)+[240 40];
oc=mpoption(o,'cpf.stop_at',.2,'cpf.step',.05);
rc=runcpf_vsc_mtdc(b,t,oc);
ck('cpf_success',rc.success,0);
err=max(abs(rc.cpf.vsc([1 3],c.PAC,:)-b.vsc([1 3],c.PAC_SET)),[],'all');
ck('cpf_PCC_P_orders',err<1e-6,err);
err=max(abs(rc.cpf.vsc([1 3],c.QAC,:)-b.vsc([1 3],c.QAC_SET)),[],'all');
ck('cpf_PCC_Q_orders',err<1e-6,err);
ck('cpf_dc_reference_retained',all(rc.cpf.vsc(2,c.DC_MODE,:)==c.VSC_DC_VDC,'all'),0);
evidence=struct('checks',checks,'passed',all([checks.passed]));
save(fullfile(outdir,'station_regression.mat'),'evidence','solutions','rc','b','t');
fid=fopen(fullfile(outdir,'station_regression.json'),'w'); fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true)); fclose(fid);
fprintf('PCC/STATION: %d/%d checks passed\n',sum([checks.passed]),numel(checks));
disp(checks(~[checks.passed]));
assert(evidence.passed,'PCC/station regression failed');
    function ck(name,passed,err)
        checks(end+1)=struct('name',name,'passed',logical(passed),'error',err);
    end
end
