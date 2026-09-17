function export_evidence
% Fresh five-bus numerical evidence; does not modify case files.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
out=fileparts(mfilename('fullpath'));
s=load(fullfile(out,'station_regression.mat'));
c=idx_vsc; b=s.b; r=s.solutions{1};
data=struct('case','case5_vsc_mtdc_beerten','success',r.success, ...
    'iterations',r.iterations,'mismatch',r.convergence.max_mismatch, ...
    'baseMVA',r.baseMVA,'bus',r.bus,'gen',r.gen,'vsc',r.vsc, ...
    'power_port','PCC','regression',s.evidence);
refIbase=100/(sqrt(3)*345);
data.reference_loss_coeff_own_pu=[1.103 .887*refIbase 2.885*refIbase^2 4.371*refIbase^2];
data.reference_dc_equivalent_300kv=[.052 .052 .073]*(345/300)^2/2;
data.local_dc_resistance_ohm=b.branchdc(:,3)*300^2/100;
data.table=array2table(r.vsc(:,[c.VSC_BUS c.PAC c.QAC c.PCONV c.QCONV c.PDC c.PLOSS c.VAC_PCC c.VAC_INTERNAL]), ...
    'VariableNames',{'PCC','P_PCC_MW','Q_PCC_MVAr','P_internal_MW','Q_internal_MVAr','P_DC_MW','bridge_loss_MW','U_PCC_pu','U_internal_pu'});
writetable(data.table,fullfile(out,'five_bus_results.csv'));
data=rmfield(data,'table');
fid=fopen(fullfile(out,'five_bus_results.json'),'w');fprintf(fid,'%s',jsonencode(data,PrettyPrint=true));fclose(fid);
% Full model boundary curves and actual C2 points. The filtered scenario is
% a test perturbation, explicitly not a replacement production case.
fig=figure('Visible','off','Position',[100 100 1250 540],'Color','w');
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
for j=1:2
    rr=s.solutions{j}; row=rr.vsc(2,:); V=row(c.VAC_PCC); Snom=150;
    m=vsc_station_map(row,rr.baseMVA,Snom); th=linspace(0,2*pi,721);
    si=conj((exp(1j*th)-m.B*V)*V/m.A)*Snom;
    su=conj((1.15*exp(1j*th)-m.D*V)*V/m.E)*Snom;
    ax=nexttile; hold on; grid on; box on;
    set(ax,'Color','w','XColor',[.1 .16 .2],'YColor',[.1 .16 .2], ...
        'GridColor',[.5 .6 .65],'FontSize',11);
    plot(real(si),imag(si),'Color',[.1 .45 .75],'LineWidth',2,'DisplayName','Converter current limit');
    plot(real(su),imag(su),'Color',[.85 .35 .15],'LineWidth',2,'DisplayName','Internal voltage limit');
    plot(real(Snom*V*exp(1j*th)),imag(Snom*V*exp(1j*th)),'--','Color',[.5 .5 .5], ...
        'DisplayName','PCC-current circle (ignores filter)');
    plot(row(c.PAC),row(c.QAC),'ko','MarkerFaceColor',[.1 .7 .5], ...
        'MarkerSize',8,'DisplayName','Solved C2 PCC point');
    xline(-Snom,':','HandleVisibility','off');xline(Snom,':','HandleVisibility','off');
    xlim([-180 180]); ylim([-190 170]);axis square;
    xlabel('P at PCC (MW)','Color',[.1 .16 .2]);ylabel('Q at PCC (MVAr)','Color',[.1 .16 .2]);
    if j==1
        title('Five-bus replication: no filter','Color','k','FontSize',13);
        text(-175,163,'Voltage ceiling above view','Color',[.65 .25 .05],'FontSize',9);
    else
        title('Filtered test: G_f=0.002, B_f=0.0887','Color','k','FontSize',13);
    end
    legend('Location','southoutside','FontSize',9,'Color','w','TextColor',[.1 .16 .2]);
end
sgtitle('One formulation: Snom=150 MVA, Uc,max=1.15 pu','Color','k','FontSize',15);
exportgraphics(fig,fullfile(out,'capability_comparison.png'),'Resolution',150);
exportgraphics(fig,fullfile(out,'capability_comparison.pdf'),'ContentType','vector');close(fig);
fprintf('Fresh report data and capability plots saved in %s\n',out);
end
