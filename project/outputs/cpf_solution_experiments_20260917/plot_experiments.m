function plot_experiments
% Actual saved CPF traces; no synthetic power-flow samples.
out=fileparts(mfilename('fullpath'));
old=load(fullfile(out,'..','ultc_swshunt_g2_150mw_20260916','main_run.mat'));
a=load(fullfile(out,'coupled_limit','step_100.mat'));
b=load(fullfile(out,'continuation_limit','all_controls','step_100.mat'));
rr={old.g150_r,a.r,b.result}; names={'Baseline','A: coupled current only','B: augmented + tangent transport'};
combined=fullfile(out,'coupled_limit','combined_all_controls','step_100.mat');
if isfile(combined)
    ab=load(combined); if isfield(ab,'r'), rr{end+1}=ab.r; else, rr{end+1}=ab.result; end
    names{end+1}='A+B: combined + tangent transport';
end
colors=[.00 .35 .65; .8 .3 .05; .0 .5 .3; .5 .2 .7]; styles={'-','--','-.',':'}; c=idx_vsc;
f=figure('Visible','off','Color','w','Theme','light','Position',[70 70 1300 820]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
for k=1:numel(rr), r=rr{k}; plot(r.cpf.lam,squeeze(r.cpf.bus(5,8,:)),styles{k},'Color',colors(k,:),'LineWidth',1.8); end
grid on; xlabel('Loading parameter \lambda'); ylabel('Bus 5 voltage (p.u.)'); title('Whole accepted trace: direction and branch matter');
legend(names,'Location','southwest','FontSize',10);
nexttile; hold on;
for k=1:numel(rr)
    r=rr{k}; plot(r.cpf.lam,squeeze(r.cpf.bus(5,8,:)),styles{k},'Color',colors(k,:),'LineWidth',1.8);
    ix=find(squeeze(r.cpf.bus(6,2,:))==1,1);
    if ~isempty(ix), scatter(r.cpf.lam(ix),r.cpf.bus(5,8,ix),65,colors(k,:),'filled','HandleVisibility','off'); end
end
xlim([1.235 1.248]); ylim([.64 .72]); grid on;
xlabel('\lambda'); ylabel('Bus 5 voltage (p.u.)'); title('Near the turn; dots = first accepted G2 PQ point');
nexttile; hold on;
for k=1:numel(rr), r=rr{k}; v=r.cpf.vsc; ic=squeeze(hypot(v(2,c.PCONV,:),v(2,c.QCONV,:))./v(2,c.VAC_INTERNAL,:))/150; plot(r.cpf.lam,ic,styles{k},'Color',colors(k,:),'LineWidth',1.8); end
yline(1,'k:','Current rating'); grid on; xlabel('\lambda'); ylabel('VSC 2 internal current / rating'); title('A follows the current equality after activation');
nexttile; hold on;
for k=1:numel(rr), r=rr{k}; v=r.cpf.vsc; ic=squeeze(hypot(v(3,c.PCONV,:),v(3,c.QCONV,:))./v(3,c.VAC_INTERNAL,:))/150; plot(r.cpf.lam,ic,styles{k},'Color',colors(k,:),'LineWidth',1.8); end
yline(1,'k:','Current rating'); grid on; xlabel('\lambda'); ylabel('VSC 3 internal current / rating'); title('Another converter binds on the low-voltage branch');
exportgraphics(f,fullfile(out,'comparison.png'),'Resolution',160); close(f);

f=figure('Visible','off','Color','w','Theme','light','Position',[70 70 1300 780]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
for pane=1:4
    nexttile; hold on;
    for k=1:numel(rr)
        r=rr{k};
        if pane==1, y=squeeze(r.cpf.bus(5,8,:));
        elseif pane==2, y=squeeze(r.cpf.vsc(2,c.VAC_PCC,:));
        elseif pane==3, y=squeeze(r.cpf.branch(9,9,:));
        else, y=squeeze(r.cpf.gen(2,3,:)); end
        plot(0:numel(y)-1,y,styles{k},'Color',colors(k,:),'LineWidth',1.8);
    end
    xlabel('Accepted continuation step'); grid on;
    if pane==1, ylabel('Bus 5 voltage (p.u.)'); title('A-only reverses voltage direction after G2 transition'); legend(names,'Location','best','FontSize',9);
    elseif pane==2, ylabel('VSC 2 PCC voltage (p.u.)'); title('Held current mode versus original voltage request'); yline(1,'k:','Original V request');
    elseif pane==3, ylabel('ULTC tap'); title('A lower tap bound can leave voltage below target'); yline(.9,'k:','Minimum tap');
    else, ylabel('Generator 2 Q (MVAr)'); title('Generator capability remains unchanged'); yline(112.5,'k:','Upper corner'); end
end
exportgraphics(f,fullfile(out,'control_histories.png'),'Resolution',160); close(f);

lo=load(fullfile(out,'coupled_limit','combined','step_100.mat'));
fixed=load(combined);
f=figure('Visible','off','Color','w','Theme','light','Position',[70 70 1250 550]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;
plot(0:numel(lo.r.cpf.lam)-1,squeeze(lo.r.cpf.bus(5,8,:)),'--','LineWidth',1.6); hold on;
plot(0:numel(fixed.r.cpf.lam)-1,squeeze(fixed.r.cpf.bus(5,8,:)),'LineWidth',2);
grid on; xlabel('Accepted continuation step'); ylabel('Bus 5 voltage (p.u.)');
title('Preserving direction removes numerical retracing');
legend('A+B: tap-only tangent resets','A+B: all-event tangent transport','Location','best');
nexttile;
stairs(0:numel(lo.r.cpf.lam)-1,squeeze(lo.r.cpf.branch(9,9,:)),'--','LineWidth',1.6); hold on;
stairs(0:numel(fixed.r.cpf.lam)-1,squeeze(fixed.r.cpf.branch(9,9,:)),'LineWidth',2);
yline(.9,'k:','Lower tap bound'); grid on; xlabel('Accepted continuation step'); ylabel('ULTC tap');
title('Repeated tap reversals are numerical trace loops');
exportgraphics(f,fullfile(out,'orientation_fix.png'),'Resolution',160); close(f);

d=load(fullfile(out,'continuation_limit','diagnostic_step_100.mat'));
jj=d.journal; lastk=jj{end}.candidate_index; rows={};
for k=1:numel(jj), if jj{k}.candidate_index==lastk, rows{end+1}=jj{k}; end; end %#ok<AGROW>
% Use only last failed attempt's sequence, after last negative restart in
% lambda_before ordering is not robust; preserve complete log for report.
save(fullfile(out,'plot_sources.mat'),'names','lastk');
fprintf('Exported comparison.png and control_histories.png from saved results.\n');
end
