function plot_critical_bus
% Plot only previously accepted NOSE-mode points; never rerun the solver.
out=fileparts(mfilename('fullpath')); src=fileparts(out);
ids={'baseline','coupled_current','augmented_tangent','combined'};
names={'Baseline','Coupled current','Augmented + tangent transport','Combined'};
colors=[.00 .35 .70; .82 .30 .03; .00 .48 .30; .55 .20 .70];
styles={'-','--','-.',':'}; steps=[100 50]; runs=cell(4,2); rows={};
for j=1:2
    for k=1:4
        d=load(fullfile(src,sprintf('%s_%03d.mat',ids{k},steps(j))));
        r=d.result; ix=find(r.bus(:,1)==5); assert(isscalar(ix));
        p=squeeze(r.cpf.bus(ix,3,:)); v=squeeze(r.cpf.bus(ix,8,:));
        g=find(squeeze(r.cpf.bus(6,2,:))==1,1);
        [vm,imin]=min(r.bus(:,8));
        assert(r.bus(imin,1)==5,'Bus 5 is not minimum-voltage physical endpoint bus.');
        runs{k,j}=struct('p',p,'v',v,'lam',r.cpf.lam(:),'g',g,'nose',r.cpf.termination.nose_detected);
        rows(end+1,:)={names{k},steps(j)/1000,numel(v),p(end),v(end),r.bus(imin,1),vm,r.cpf.termination.cause}; %#ok<AGROW>
        assert(max(abs(p-(d.base.bus(ix,3)+r.cpf.lam(:)*(d.target.bus(ix,3)-d.base.bus(ix,3)))))<1e-6);
    end
end
T=cell2table(rows,'VariableNames',{'variant','step','points','end_P5_MW','end_V5_pu','minimum_voltage_bus','minimum_voltage_pu','stop_cause'});
writetable(T,fullfile(out,'plot_endpoints.csv'));
for zoom=[false true]
    f=figure('Visible','off','Color','w','Theme','light','Position',[60 60 1450 620]);
    tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    for j=1:2
        nexttile; hold on; hh=gobjects(4,1);
        for k=1:4
            d=runs{k,j}; hh(k)=plot(d.p,d.v,styles{k},'Color',colors(k,:),'LineWidth',2);
            if zoom, plot(d.p,d.v,'.','Color',colors(k,:),'MarkerSize',8,'HandleVisibility','off'); end
            if d.nose
                plot(d.p(end),d.v(end),'p','Color',colors(k,:),'MarkerFaceColor',colors(k,:),'MarkerSize',13,'HandleVisibility','off');
            else
                plot(d.p(end),d.v(end),'x','Color',colors(k,:),'LineWidth',2,'MarkerSize',10,'HandleVisibility','off');
            end
            if ~isempty(d.g)
                plot(d.p(d.g),d.v(d.g),'d','Color',colors(k,:),'MarkerFaceColor','w','LineWidth',1.5,'MarkerSize',8,'HandleVisibility','off');
            end
        end
        grid on; box on; xlabel('Bus 5 active demand P_5 (MW)'); ylabel('Bus 5 voltage V_5 (p.u.)');
        title(sprintf('Predictor step = %.2f',steps(j)/1000));
        if zoom
            xlim([356.5 359.4]); ylim([.645 .715]); legend(hh,names,'Location','southwest','FontSize',10);
        else
            xlim([55 367]); ylim([.20 1.02]); legend(hh,names,'Location','southwest','FontSize',10);
        end
        set(gca,'FontSize',12);
    end
    if zoom, title(tl,'Bus 5 P-V curves: detail around the turning region','FontSize',17); stem='pv_bus5_near_nose';
    else, title(tl,'Bus 5 P-V curves: all accepted points from NOSE-mode runs','FontSize',17); stem='pv_bus5_overview'; end
    subtitle(tl,'Star = detected local nose; diamond = first G2 PQ point; x = other termination. Lines join accepted samples.','FontSize',11);
    exportgraphics(f,fullfile(out,[stem '.png']),'Resolution',160);
    exportgraphics(f,fullfile(out,[stem '.pdf']),'ContentType','vector'); close(f);
end
% One panel per variant makes the step-size and branch-selection effects visible.
f=figure('Visible','off','Color','w','Theme','light','Position',[60 60 1300 850]);
tl=tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
for k=1:4
    nexttile; hold on; hh=gobjects(2,1);
    for j=1:2
        d=runs{k,j}; sty='-'; if j==2, sty='--'; end
        hh(j)=plot(d.p,d.v,sty,'Color',colors(k,:),'LineWidth',1.8);
        plot(d.p,d.v,'.','Color',colors(k,:),'MarkerSize',7,'HandleVisibility','off');
        if d.nose, plot(d.p(end),d.v(end),'p','Color',colors(k,:),'MarkerFaceColor',colors(k,:),'MarkerSize',12,'HandleVisibility','off'); end
        if ~isempty(d.g), plot(d.p(d.g),d.v(d.g),'d','Color',colors(k,:),'MarkerFaceColor','w','MarkerSize',8,'HandleVisibility','off'); end
    end
    xlim([356.5 359.4]); ylim([.645 .715]); grid on; box on;
    xlabel('Bus 5 active demand (MW)'); ylabel('Bus 5 voltage (p.u.)'); title(names{k});
    legend(hh,{'Step 0.10','Step 0.05'},'Location','southwest'); set(gca,'FontSize',11);
end
title(tl,'Step-size comparison for each formulation','FontSize',17);
subtitle(tl,'Accepted samples only. Stars are detected local noses; diamonds mark G2 changing to PQ.','FontSize',11);
exportgraphics(f,fullfile(out,'pv_bus5_by_case.png'),'Resolution',150);
exportgraphics(f,fullfile(out,'pv_bus5_by_case.pdf'),'ContentType','vector'); close(f);
fprintf('Verified bus 5 has the lowest endpoint voltage among physical buses in all eight runs.\n');
fprintf('Bus-5 demand: P5 = %.12g + %.12g * lambda MW.\n',demand_base(src),demand_delta(src));
end
function p=demand_base(src)
d=load(fullfile(src,'baseline_100.mat'),'base'); p=d.base.bus(d.base.bus(:,1)==5,3);
end
function p=demand_delta(src)
d=load(fullfile(src,'baseline_100.mat'),'base','target'); ix=d.base.bus(:,1)==5; p=d.target.bus(ix,3)-d.base.bus(ix,3);
end
