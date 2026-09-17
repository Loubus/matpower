function plot_diagnosis
% Display saved MATLAB calculations; arrows are local tangent illustrations.
out=fileparts(mfilename('fullpath')); root=fileparts(fileparts(out));
T=readtable(fullfile(root,'outputs','cpf_nose_comparison_20260917','coupled_current_100_trace.csv'));
d=load(fullfile(out,'localized_event_100.mat')); e=d.ev;
C=jsondecode(fileread(fullfile(out,'comparison.json')));
f=figure('Visible','off','Color','w','Theme','light','Position',[80 80 1450 700]);
tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
ax=nexttile; hold(ax,'on');
k=find(T.bus6_type==1,1); ix=max(1,k-5):k-1; jx=k:height(T);
plot(60+240*T.lambda(ix)-e.P5_MW,T.V5(ix),'-o','Color',[.1 .4 .7],'LineWidth',2,'MarkerSize',4,'DisplayName','Original trace: G2 controls voltage');
plot(60+240*T.lambda(jx)-e.P5_MW,T.V5(jx),'-o','Color',[.85 .35 .08],'LineWidth',2,'MarkerSize',4,'DisplayName','Original trace: G2 at Q limit');
plot(0,e.V5,'kp','MarkerFaceColor',[1 .8 .1],'MarkerSize',15,'DisplayName','Independently localized G2 limit');
plot(60+240*T.lambda(end)-e.P5_MW,T.V5(end),'ks','MarkerFaceColor','w','MarkerSize',9,'DisplayName','Previously reported smooth nose');
ds=.006;
quiver(0,e.V5,240*e.outgoing_oriented_tlambda*ds,e.outgoing_oriented_tV5*ds,0,'Color',[0 .5 .3],'LineWidth',2.4,'MaxHeadSize',.18,'DisplayName','Correct outgoing tangent (local)');
quiver(0,e.V5,-240*e.outgoing_oriented_tlambda*ds,-e.outgoing_oriented_tV5*ds,0,'Color',[.65 .12 .4],'LineWidth',2,'MaxHeadSize',.18,'DisplayName','Forced positive-lambda tangent');
text(-.16,.6905,{'Voltage rises because the tangent','is reversed after PV-to-PQ.'},'FontSize',12,'FontWeight','bold');
text(-.17,.6779,{'Continue forward:','both load and voltage fall'},'Color',[0 .45 .25],'FontSize',11);
xlim([-.19 .067]); ylim([.677 .692]); grid on;
xlabel('Bus 5 load relative to localized limit (MW)'); ylabel('Bus 5 voltage (p.u.)');
title({'Coupled current: what the upward segment means',sprintf('G2 limit: P_5 = %.6f MW, V_5 = %.6f p.u.',e.P5_MW,e.V5)});
legend('Location','southoutside','FontSize',9);
ax2=nexttile; hold(ax2,'on');
cc=lines(2); ids=[3 7]; labs={'Coupled current, initial step 0.1','Combined, initial step 0.1'};
for ii=1:2
 h=C(ids(ii)).history; width=abs([h.pre_control_lambda]-[h.last_lambda]);
 semilogy(1:numel(h),width,'-o','Color',cc(ii,:),'LineWidth',2,'DisplayName',labs{ii});
end
yline(1e-5,'--','Event tolerance','HandleVisibility','off');
set(ax2,'YScale','log'); grid on; xlabel('Rejected trial / rollback'); ylabel('Incoming trial interval in lambda');
title({'Guard detects the turn and refines the trial','The existing minimum step stops further refinement'});
legend('Location','southoutside','FontSize',10);
sgtitle(tl,'A control-limit turn can be missed even when Newton converges','FontSize',19,'FontWeight','bold');
exportgraphics(f,fullfile(out,'nose_skip_diagnosis.png'),'Resolution',180);
exportgraphics(f,fullfile(out,'nose_skip_diagnosis.pdf'),'ContentType','vector');
close(f);
end
