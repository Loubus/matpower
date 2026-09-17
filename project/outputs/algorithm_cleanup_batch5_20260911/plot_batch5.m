function plot_batch5
out=fileparts(mfilename('fullpath'));
s=jsondecode(fileread(fullfile(out,'analysis_final_02','summary.json')));
f=figure('Visible','off','Position',[100 100 1250 480]);
tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
a=nexttile; hold(a,'on');
colors=[.42 .47 .52;.35 .47 .58;.20 .45 .60;.03 .42 .40];
for k=1:4
 B=5*(k-1); rows=[s.fixed_states.B]==B; data=s.fixed_states(rows);
 plot(a,[data.lambda],[data.vm5],'o-','Color',colors(k,:),'DisplayName',sprintf('B = %g MVAr',B));
end
yline(a,.94999,'--','Color',[.71 .32 .23],'DisplayName','Lower band edge with tolerance');
xlabel(a,'Loading parameter lambda'); ylabel(a,'Bus 5 voltage (pu)');
title(a,'Full-equation PF with explicit shunt states');
legend(a,'Location','southwest'); ylim(a,[.928 .952]); grid(a,'on');
a=nexttile; hold(a,'on');
plot(a,[s.last_lambda s.candidate_lambda],[s.last_vm5 s.candidate_vm5],'-','Color',colors(4,:),'HandleVisibility','off');
plot(a,s.last_lambda,s.last_vm5,'o','MarkerSize',8,'MarkerFaceColor',colors(4,:),'Color',colors(4,:),'DisplayName','Last accepted CPF point');
plot(a,s.candidate_lambda,s.candidate_vm5,'x','MarkerSize',10,'LineWidth',2,'Color',[.71 .32 .23],'DisplayName','Solved, control-rejected candidate');
yline(a,.94999,'--','Color',[.71 .32 .23],'DisplayName','Lower band edge with tolerance');
xlabel(a,'Loading parameter lambda');ylabel(a,'Bus 5 voltage (pu)');
title(a,'Automatic control: B already at 15 MVAr');
xlim(a,[s.last_lambda-.000025 s.candidate_lambda+.000025]);ylim(a,[.94998 .950018]);
ytickformat(a,'%.6f');xticks(a,[.41055 .41060 .41065 .41070]);xtickformat(a,'%.5f');legend(a,'Location','northeast');grid(a,'on');
sgtitle(f,'Beerten control-band termination: the electrical solve converges','Color','k');
set(f,'Color','w');
set(findall(f,'Type','axes'),'Color','w','XColor','k','YColor','k','GridColor',[.75 .75 .75]);
set(findall(f,'Type','text'),'Color','k');
set(findall(f,'Type','legend'),'Color','w','TextColor','k','EdgeColor',[.65 .65 .65]);
set(findall(f,'Type','line'),'LineWidth',1.3);
exportgraphics(f,fullfile(out,'event_diagnostic.png'),'Resolution',190,'BackgroundColor','white');
close(f);
end
