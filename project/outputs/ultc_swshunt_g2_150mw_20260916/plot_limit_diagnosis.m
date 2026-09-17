function plot_limit_diagnosis
out=fileparts(mfilename('fullpath')); d=load(fullfile(out,'main_run.mat')); r=d.g150_r;
old=load(fullfile(out,'..','ultc_swshunt_cpf_20260916','full_run.mat'));
h=load(fullfile(out,'half_step_run.mat')); h=h.g150_hr;
j=load(fullfile(out,'instrumented_run.mat')); j=j.g150_journal;
jo=load(fullfile(out,'old_instrumented_run.mat')); jo=jo.g150_oldjournal;
b=load(fullfile(out,'coupled_boundary_probes.mat'));
f=figure('Visible','off','Color','w','Theme','light','Position',[30 30 1400 1000]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile; hold on; colors=[.6 .65 .7; .1 .4 .7];
for z=1:2
    sn=[100 187.5]; sn=sn(z); [~,~,~,~,info]=gen_capability_curve(0,0,sn,2); c=info.curve;
    p=linspace(0,c.PB,300); q0=(c.QA^2-c.PB^2-c.QB^2)/(2*(c.QA-c.QB)); rad=c.QA-q0;
    qu=sqrt(rad^2-p.^2)+q0; ql=c.QE*ones(size(p)); idx=p>c.PD; ql(idx)=c.QD+(p(idx)-c.PD)*(c.QC-c.QD)/(c.PC-c.PD);
    fill([p fliplr(p)],[qu fliplr(ql)],colors(z,:),'FaceAlpha',.12,'EdgeColor',colors(z,:),'LineWidth',1.5);
end
plot(squeeze(r.cpf.gen(2,2,:)),squeeze(r.cpf.gen(2,3,:)),'Color',[.8 .25 .1],'LineWidth',2);
scatter(150,112.5,60,[.8 .25 .1],'filled'); xlim([-5 170]); ylim([-95 170]); grid on;
xlabel('Generator 2 P (MW)'); ylabel('Generator 2 Q (MVAr)'); title('Generator 2: resized thermal capability');
legend('Previous: 80 MW maximum','New: 150 MW maximum','Accepted dispatch','Final point','Location','northwest');
nexttile; plot(old.result.cpf.lam,squeeze(old.result.cpf.bus(5,8,:)),'Color',[.5 .5 .5],'LineWidth',1.5); hold on;
plot(r.cpf.lam,squeeze(r.cpf.bus(5,8,:)),'LineWidth',1.8); plot(h.cpf.lam,squeeze(h.cpf.bus(5,8,:)),'--','LineWidth',1.4);
xlabel('Loading parameter \lambda'); ylabel('Bus 5 voltage (p.u.)'); title('More generation delays the difficult region'); grid on;
legend('Previous 80 MW','150 MW, step 0.10','150 MW, step 0.05','Location','southwest');
nexttile; hold on; P=linspace(-160,160,1000); V=r.vsc(2,34); X=sum(r.vsc(2,[16 25])); sn=150;
qi=sqrt(max(0,(sn*V)^2-P.^2)); qi(abs(P)>sn*V)=NaN;
qv=-100*V^2/X+sqrt((100*V*1.15/X)^2-P.^2);
valid=isfinite(qi); fill([P(valid) fliplr(P(valid))],[qi(valid) -fliplr(qi(valid))],[.7 .9 .8],'FaceAlpha',.65,'EdgeColor','none');
plot(P,qi,'Color',[.05 .45 .3],'LineWidth',2); plot(P,-qi,'Color',[.05 .45 .3],'LineWidth',2,'HandleVisibility','off');
plot(P,qv,'Color',[.6 .25 .7],'LineWidth',2); xline(-150,'--','HandleVisibility','off'); xline(150,'--','HandleVisibility','off');
plot(squeeze(r.cpf.vsc(2,30,:)),squeeze(r.cpf.vsc(2,31,:)),'Color',[.8 .25 .1],'LineWidth',1.8);
scatter(r.vsc(2,30),r.vsc(2,31),60,[.8 .25 .1],'filled','HandleVisibility','off');
ylim([-170 500]); xlim([-170 170]); grid on;
xlabel('VSC 2 PCC P (MW)'); ylabel('VSC 2 PCC Q (MVAr)'); title(sprintf('Final PCC capability at V = %.5f p.u.',V));
legend('Intersection of implemented limits','Current boundary','Internal-voltage upper boundary','Operating trajectory (changing V)','Location','northwest');
nexttile; hold on; tail=max(1,numel(r.cpf.lam)-115):numel(r.cpf.lam);
plot(r.cpf.lam(tail),squeeze(r.cpf.bus(5,8,tail)),'-','LineWidth',2); [lm,ix]=max(r.cpf.lam);
scatter(lm,r.cpf.bus(5,8,ix),60,'k','filled'); scatter(r.cpf.lam(end),r.bus(5,8),65,[.8 .25 .1],'filled');
scatter(b.g150_joint.lambda,b.g150_joint.V5,65,[.05 .6 .3],'s','filled');
xlabel('Loading parameter \lambda'); ylabel('Bus 5 voltage (p.u.)'); title('FULL trace turns back before the failed Q update'); grid on;
xlim([1.24504 1.24518]); ylim([.672 .684]);
legend('Accepted fixed-Q branch','Sampled maximum','Last accepted point','Coupled current-limit solution','Location','best');
sgtitle('150 MW generator study: capability geometry and continuation','FontSize',16,'FontWeight','bold');
exportgraphics(f,fullfile(out,'capability_overview.png'),'Resolution',155); close(f);

% Resolve the original failed trial, keeping only its last repeated sequence.
last=jo.rows{end}; rows={};
for k=1:numel(jo.rows)
    rr=jo.rows{k};
    if rr.k==last.k && strcmp(rr.kind,'before'), rows{end+1}=rr; end %#ok<AGROW>
end
f=figure('Visible','off','Color','w','Theme','light','Position',[30 30 1450 850]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile; hold on; colors=lines(numel(rows)); P=linspace(19.80,19.94,200);
for k=1:numel(rows)
    rr=rows{k}; V=rr.vsc(2,34); plot(P,sqrt((150*V)^2-P.^2),'Color',colors(k,:),'LineWidth',1.5,'DisplayName',sprintf('Current boundary: V=%.6f',V));
    scatter(rr.vsc(2,30),rr.vsc(2,31),55,colors(k,:),'filled','HandleVisibility','off');
end
scatter(b.g150_oldjoint.P2,b.g150_oldjoint.Q2,80,'k','s','filled','DisplayName','Coupled exact boundary solution');
xlabel('PCC P (MW)'); ylabel('PCC Q (MVAr)'); title('Old endpoint: each Q cut shrinks the current circle'); grid on; legend('Location','best');
nexttile; vals=zeros(numel(rows),4);
for k=1:numel(rows)
    rr=rows{k}; vals(k,:)=[rr.vsc(2,31) sqrt((150*rr.vsc(2,34))^2-rr.vsc(2,30)^2) rr.report.Q_saturated(1) rr.vsc(2,34)];
end
plot(1:numel(rows),vals(:,1:3),'o-','LineWidth',1.6); xticks(1:numel(rows));
xlabel('Clip / re-solve iteration'); ylabel('MVAr'); title('Old failed trial at \lambda = 1.159993955'); grid on;
legend('Solved Q before clipping','Exact boundary at current voltage','Next fixed Q (0.1% inward)','Location','southwest');
nexttile; rr=j.rows{end}; P=rr.vsc(2,30); V=rr.vsc(2,34); Q=rr.vsc(2,31); qi=sqrt((150*V)^2-P^2);
bar(categorical({'Before clipping','Exact limit at old V','Next fixed Q','Coupled solution'}),[Q qi rr.report.Q_saturated b.g150_joint.Q2],'FaceColor',[.15 .45 .7]);
ylim([143.54 143.76]); ylabel('MVAr'); title('New failed trial: a finite Q reduction near the fold'); grid on;
nexttile; semilogy(b.g150_joint.history(:,1),b.g150_joint.history(:,2),'o-','LineWidth',1.6); hold on;
semilogy(b.g150_joint.fixed_Q_probe.history(:,1),b.g150_joint.fixed_Q_probe.history(:,2),'s-','LineWidth',1.6);
yline(1e-9,':','Diagnostic tolerance'); xlabel('Diagnostic Newton iteration'); ylabel('Maximum equation residual (p.u.)');
title('Same failed lambda: coupled current equation converges'); grid on;
legend('Coupled current-limit equations','Projected fixed-Q equations','Location','best');
sgtitle('Why clipping Q and re-solving can fail near the endpoint','FontSize',16,'FontWeight','bold');
exportgraphics(f,fullfile(out,'failure_mechanism.png'),'Resolution',155); close(f);

f=figure('Visible','off','Color','w','Theme','light','Position',[20 20 1350 620]); ax=axes(f,'Position',[0 0 1 1]); axis(ax,'off');
eq={ '$P_{G,\max}=0.8S_N=150\ \mathrm{MW},\quad S_N=187.5\ \mathrm{MVA},\quad Q_B=0.6S_N=112.5\ \mathrm{MVAr}$', ...
 '$P_s^2+Q_s^2\leq(150V_s)^2,\qquad Q_{I,\max}=\sqrt{(150V_s)^2-P_s^2}$', ...
 '$P_s^2+\left(Q_s+\frac{100V_s^2}{X}\right)^2\leq\left(\frac{100V_sU_{c,\max}}{X}\right)^2,\qquad X=0.0393,\ U_{c,\max}=1.15$', ...
 '$Q_{n+1}^{\mathrm{order}}=0.999\sqrt{(150V_{s,n})^2-P_{s,n}^2}$', ...
 '$F_{\mathrm{network+station}}(x,\lambda)=0,\qquad |I_c(x)|^2-I_{c,\max}^2=0$'};
for k=1:numel(eq), text(.03,1-k*.18,eq{k},'Interpreter','latex','FontSize',20); end
exportgraphics(f,fullfile(out,'equations.svg'),'ContentType','vector','BackgroundColor','white');
exportgraphics(f,fullfile(out,'equations.png'),'Resolution',150,'BackgroundColor','white'); close(f);

% Machine-readable diagnostic summary and final-iteration table.
summary=struct('new_last_lambda',r.cpf.lam(end),'new_sampled_max_lambda',lm,'new_max_index',ix, ...
    'negative_lambda_steps',nnz(diff(r.cpf.lam)<0),'raw_nose_detected',r.cpf.termination.nose_detected, ...
    'half_last_lambda',h.cpf.lam(end),'half_cause',h.cpf.termination.cause, ...
    'new_failed_candidate',rr.lambda,'new_candidate_P',P,'new_candidate_V',V,'new_candidate_Q',Q, ...
    'new_exact_Q_bound_at_candidate_V',qi,'new_projected_Q',rr.report.Q_saturated, ...
    'joint',strip(b.g150_joint),'old_joint',strip(b.g150_oldjoint),'old_iterations',vals);
fid=fopen(fullfile(out,'diagnosis.json'),'w'); fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true)); fclose(fid);
disp(jsonencode(summary,PrettyPrint=true));
end
function s=strip(s)
s=rmfield(s,{'x','point','result','converter_audit'});
end
