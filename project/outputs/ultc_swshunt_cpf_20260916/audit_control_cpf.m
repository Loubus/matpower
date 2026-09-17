function audit_control_cpf
% Independent physical residuals and accepted-state controls; no case edits.
out=fileparts(mfilename('fullpath'));
d=load(fullfile(out,'full_run.mat'));
if ~isfile(fullfile(out,'half_step_run.mat'))
    options=mpoption(d.options,'cpf.step',d.options.cpf.step/2,'verbose',0);
    lastwarn(''); tt=tic;
    [result,success]=runcpf_psse(d.base,d.target,options);
    elapsed=toc(tt); [last_warning,last_warning_id]=lastwarn;
    save(fullfile(out,'half_step_run.mat'),'result','success','elapsed','options','last_warning','last_warning_id','-v7.3');
end
h=load(fullfile(out,'half_step_run.mat'));
[main,main_summary]=audit(d.result,d.base,d.options);
[half,half_summary]=audit(h.result,d.base,h.options);
writetable(main,fullfile(out,'accepted_trace.csv'));
writetable(half,fullfile(out,'half_step_trace.csv'));
summary=struct('main',main_summary,'half_step',half_summary, ...
    'half_step_last_warning',h.last_warning,'lambda_endpoint_difference',half.lambda(end)-main.lambda(end));
fid=fopen(fullfile(out,'audit.json'),'w'); fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true)); fclose(fid);
fid=fopen(fullfile(out,'events.json'),'w'); fprintf(fid,'%s',jsonencode(d.result.cpf.events,PrettyPrint=true)); fclose(fid);
disp(jsonencode(summary,PrettyPrint=true));
f=figure('Visible','off','Position',[50 50 1600 1120],'Color','w','Theme','light');
tiledlayout(3,2,'TileSpacing','compact','Padding','compact');
nexttile; plot(main.lambda,[main.V5 main.V7 main.V3],'LineWidth',1.6); hold on;
plot(half.lambda,half.V5,'--','Color',[.2 .2 .2]); yline(.95,':'); ylim([.64 1.025]);
legend('Bus 5','Bus 7 (ULTC)','Bus 3 (VSC 2)','Bus 5: half step','Location','southwest');
ylabel('Voltage (p.u.)'); title('Accepted voltage trace: no nose reached'); grid on;
nexttile; stairs(main.lambda,main.tap9,'LineWidth',1.6); hold on;
stairs(half.lambda,half.tap9,'--','LineWidth',1.1); ylim([.9 1.04]);
ylabel('Tap ratio, branch 4-7'); title('ULTC: discrete downward taps restore bus 7'); grid on;
legend('Original step 0.10','Half step 0.05','Location','southwest');
nexttile; stairs(main.lambda,main.B5,'LineWidth',1.6); hold on; plot(main.lambda,main.Qshunt5,'LineWidth',1.6);
ylabel('MVAr'); title('Shunt saturates; delivered Q falls with V squared'); legend('Nominal B at 1 p.u.','Delivered B V^2','Location','best'); grid on;
nexttile; plot(main.lambda,[main.Pg1 main.Pg2 main.Pg2_requested],'LineWidth',1.6);
ylabel('MW'); title('Generator 2 clamps at 80 MW; slack supplies balance'); legend('Slack at bus 1','Generator at bus 6','Requested bus 6 schedule','Location','northwest'); grid on;
nexttile; plot(main.lambda,[main.Qg2 main.Qc2],'LineWidth',1.6); hold on;
idx=find(main.C2mode==1,1); xline(main.lambda(idx),'--','VSC 2 V to Q');
ylabel('MVAr'); title('Reactive limits change the control modes'); legend('Generator 2','VSC 2 (PCC)','Location','northwest'); grid on;
nexttile; plot(main.lambda,[main.Ic1 main.Ic2 main.Ic3],'LineWidth',1.6); hold on; yline(1,'--','Current limit');
ylabel('Converter current / limit'); title('Full-station capability: VSC 2 reaches current limit'); legend('VSC 1','VSC 2','VSC 3','Location','west'); grid on;
ax=findall(f,'Type','axes'); for k=1:numel(ax), xlabel(ax(k),'Loading parameter lambda'); ax(k).FontSize=10; end
sgtitle(sprintf('Constant-P/Q non-slack dispatch | FULL requested | accepted endpoint %.6f',main.lambda(end)),'FontWeight','bold','FontSize',14);
exportgraphics(f,fullfile(out,'control_cpf.png'),'Resolution',150); close(f);
end

function [T,s]=audit(r,base,options)
c=idx_vsc; n=numel(r.cpf.lam); a=zeros(n,32);
for k=1:n
    b=r.cpf.bus(:,:,k); g=r.cpf.gen(:,:,k); br=r.cpf.branch(:,:,k); v=r.cpf.vsc(:,:,k);
    bd=r.cpf.busdc(:,:,k); brd=r.cpf.branchdc(:,:,k);
    ac=struct('version','2','baseMVA',base.baseMVA,'bus',b,'gen',g,'branch',br); ac=ext2int(ac);
    U=ac.bus(:,8).*exp(1j*pi/180*ac.bus(:,9)); Y=makeYbus(ac.baseMVA,ac.bus,ac.branch);
    S=makeSbus(ac.baseMVA,ac.bus,ac.gen);
    for j=1:size(v,1)
        row=find(ac.order.bus.i2e==v(j,c.VSC_BUS));
        S(row)=S(row)+complex(v(j,c.PAC),v(j,c.QAC))/base.baseMVA;
    end
    acerr=max(abs(U.*conj(Y*U)-S))*base.baseMVA;
    G=makeGdc(bd,brd); Pdc=zeros(size(bd,1),1);
    for j=1:size(v,1), row=find(bd(:,1)==v(j,c.BUSDC)); Pdc(row)=Pdc(row)+v(j,c.PDC); end
    dcerr=max(abs(bd(:,3).*(G*bd(:,3))*base.baseMVA-Pdc));
    bridge=max(abs(v(:,c.PCONV)+v(:,c.PDC)+v(:,c.PLOSS)));
    cap=check_vsc_capability(struct('version','2','baseMVA',base.baseMVA,'bus',b,'gen',g,'branch',br,'vsc',v),struct('vmax',options.vsc_mtdc.capability_vsc_vmax));
    currents=zeros(1,3); verr=0; ierr=0; serr=0; loss_err=0;
    for j=1:3
        e=cap.elements(j); m=vsc_station_map(v(j,:),base.baseMVA,e.Smax);
        us=v(j,c.VAC_PCC); is=conj(complex(v(j,c.PAC),v(j,c.QAC))/e.Smax/us);
        uc=m.D*us+m.E*is; ic=m.B*us+m.A*is;
        currents(j)=hypot(v(j,c.PCONV),v(j,c.QCONV))/v(j,c.VAC_INTERNAL)/e.Smax;
        verr=max(verr,abs(abs(uc)-v(j,c.VAC_INTERNAL)));
        ierr=max(ierr,abs(abs(ic)-currents(j)));
        serr=max(serr,abs(uc*conj(ic)*e.Smax-complex(v(j,c.PCONV),v(j,c.QCONV))));
        sysI=currents(j)*e.Smax/base.baseMVA;
        loss_err=max(loss_err,abs(v(j,c.PLOSS)-(v(j,c.LOSS_A)+v(j,c.LOSS_B)*sysI+v(j,c.LOSS_C)*sysI^2)));
    end
    lam=r.cpf.lam(k); sched=max(abs(v([1 3],[c.PAC c.QAC])-base.vsc([1 3],[c.PAC_SET c.QAC_SET])),[],'all');
    a(k,:)=[lam b(5,8) b(7,8) b(3,8) br(9,9) b(5,6) b(5,6)*b(5,8)^2 g(1,2) g(2,2) 40+240*lam g(2,3) v(2,c.QAC) v(2,c.AC_MODE) v(2,c.VDC) currents v(:,c.VAC_INTERNAL)' acerr dcerr bridge verr ierr serr loss_err sched min([cap.elements.margin]) b(6,2) b(5,3) b(5,4)];
end
T=array2table(a,'VariableNames',{'lambda','V5','V7','V3','tap9','B5','Qshunt5','Pg1','Pg2','Pg2_requested','Qg2','Qc2','C2mode','C2Vdc','Ic1','Ic2','Ic3','Uc1','Uc2','Uc3','AC_error_MVA','DC_error_MW','bridge_error_MW','station_U_error_pu','station_I_error_pu','station_S_error_MVA','loss_error_MW','PQ_schedule_error','cap_margin_MVA','bus6_type','Pload5','Qload5'});
change=find([true; abs(diff(T.tap9))>1e-8 | abs(diff(T.B5))>1e-8 | diff(T.C2mode)~=0 | diff(T.bus6_type)~=0]);
xs=mp.psse_xfmr_states(r); ss=mp.psse_swshunt_states(r);
checks=struct('ac_balance',max(T.AC_error_MVA)<1e-5,'dc_balance',max(T.DC_error_MW)<1e-5, ...
    'bridge_balance',max(T.bridge_error_MW)<1e-5,'station_phasor_match',max(T.station_S_error_MVA)<1e-7, ...
    'loss_match',max(T.loss_error_MW)<1e-8,'constant_PCC_PQ',max(T.PQ_schedule_error)<1e-5, ...
    'Vdc_preserved',max(abs(T.C2Vdc-1))<1e-9,'current_limits',max(a(:,15:17),[],'all')<=1+1e-8, ...
    'internal_upper_voltage_limit',max(a(:,18:20),[],'all')<=1.15+1e-8, ...
    'ULTC_settled',all(T.V7>=.95-xs.vtol & T.V7<=1.03+xs.vtol), ...
    'ULTC_range',all(T.tap9>=.9 & T.tap9<=1.1), ...
    'ULTC_grid',max(abs((T.tap9-.9)/(.2/9)-round((T.tap9-.9)/(.2/9))))<1e-8, ...
    'shunt_range_grid',all(T.B5>=0 & T.B5<=15 & abs(T.B5/5-round(T.B5/5))<1e-8), ...
    'shunt_in_band_or_at_bound',all((T.V5>=.95-ss.vtol & T.V5<=1.03+ss.vtol) | (T.V5<.95 & T.B5==15)), ...
    'no_accepted_tap_reversal',all(diff(T.tap9)<=1e-8),'no_accepted_shunt_reversal',all(diff(T.B5)>=-1e-8));
s=struct('success',r.success,'points',n,'termination',r.cpf.termination,'endpoint',table2struct(T(end,:)), ...
    'checks',checks,'checks_passed',sum(structfun(@double,checks)),'checks_total',numel(fieldnames(checks)), ...
    'ULTC_tolerance_pu',xs.vtol,'shunt_tolerance_pu',ss.vtol, ...
    'max_residuals',table2struct(varfun(@max,T(:,21:28))), ...
    'max_C2Vdc_error',max(abs(T.C2Vdc-1)), ...
    'max_current_ratio',max(a(:,15:17),[],'all'),'max_internal_voltage',max(a(:,18:20),[],'all'), ...
    'minimum_capability_margin_MVA',min(T.cap_margin_MVA), ...
    'max_tap_grid_error',max(abs((T.tap9-.9)/(.2/9)-round((T.tap9-.9)/(.2/9)))), ...
    'max_shunt_grid_error',max(abs(T.B5/5-round(T.B5/5))), ...
    'control_transitions',table2struct(T(change,{'lambda','V5','V7','tap9','B5','C2mode','bus6_type'})), ...
    'generator_P_clamp_first_accepted_lambda',T.lambda(find(abs(T.Pg2-80)<1e-6,1)));
end
