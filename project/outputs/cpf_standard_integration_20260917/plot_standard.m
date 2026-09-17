function plot_standard
out=fileparts(mfilename('fullpath'));root=fileparts(fileparts(out));
a=readtable(fullfile(root,'outputs','cpf_nose_comparison_20260917','coupled_current_100_trace.csv'));
b=readtable(fullfile(out,'final','full_100_trace.csv'));
c=readtable(fullfile(out,'final','full_050_trace.csv'));
e=jsondecode(fileread(fullfile(out,'final','nose_100.json')));
f=figure('Visible','off','Color','w','Theme','light','Position',[100 100 1250 620]);
t=tiledlayout(1,2,'TileSpacing','compact');
for panel=1:2
 nexttile;hold on;
 plot(b.lambda,b.V5,'-','LineWidth',2,'Color',[.1 .4 .7],'DisplayName','Standard FULL, step 0.10');
 plot(c.lambda,c.V5,'--','LineWidth',1.6,'Color',[.15 .6 .4],'DisplayName','Standard FULL, step 0.05');
 plot(a.lambda,a.V5,'-o','LineWidth',1.2,'MarkerSize',3,'Color',[.85 .35 .1],'DisplayName','Earlier coupled-current-only run');
 plot(e.lambda,e.V5,'kp','MarkerFaceColor',[1 .8 .15],'MarkerSize',13,'DisplayName','NOSE stop: localized limit-induced turn');
 xlabel('Loading parameter, lambda');ylabel('Bus 5 voltage (p.u.)');grid on;
 if panel==1
  title('FULL records the first maximum and continues');xlim([0 1.31]);ylim([.2 1.02]);
 else
  title('NOSE stops before the earlier upward excursion');xlim([1.2447 1.24605]);ylim([.678 .690]);
 end
end
lg=legend('Orientation','horizontal','FontSize',9);lg.Layout.Tile='south';
sgtitle(t,'Standard unified CPF: coupled current + augmented correction + tangent transport','FontSize',15);
exportgraphics(f,fullfile(out,'standard_pv.png'),'Resolution',180);
exportgraphics(f,fullfile(out,'standard_pv.pdf'),'ContentType','vector');close(f);
end
