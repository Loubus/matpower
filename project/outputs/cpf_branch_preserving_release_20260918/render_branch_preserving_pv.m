function summary=render_branch_preserving_pv
% Measured full-CPF attempt with local, continuous voltage-control release.
out=fileparts(mfilename('fullpath'));plotdir=fullfile(out,'all_pv_curves');
if ~isfolder(plotdir),mkdir(plotdir);end
on=load(fullfile(out,'verified/full_050_release1.mat'));
off=load(fullfile(out,'verified/full_050_release0.mat'));
r=on.result;s=off.result;c=idx_vsc;
assert(~any(strcmp({r.cpf.events.name},'VSC_CURRENT_RELEASE')));
assert(~r.cpf.termination.requested_endpoint_reached);
for field={'bus','gen','branch','vsc','busdc','branchdc'}
    name=field{1};assert(isequaln(r.cpf.(name),s.cpf.(name)), ...
        'Local restoration must preserve this constrained branch.');
end
P=reshape(sum(r.cpf.bus(:,3,:),1),1,[]);n=numel(P);
[peak,imax]=max(r.cpf.lam);Ppeak=P(imax);
ac=reshape(r.cpf.bus(:,8,:),size(r.bus,1),n);
station=zeros(6,n);stationnames=cell(6,1);
for j=1:3
    station(2*j-1,:)=reshape(r.cpf.vsc(j,c.VAC_FILTER,:),1,[]);
    station(2*j,:)=reshape(r.cpf.vsc(j,c.VAC_INTERNAL,:),1,[]);
    stationnames{2*j-1}=sprintf('VSC %d, PCC bus %d: filter',j,r.vsc(j,c.VSC_BUS));
    stationnames{2*j}=sprintf('VSC %d, PCC bus %d: internal',j,r.vsc(j,c.VSC_BUS));
end
dc=reshape(r.cpf.busdc(:,3,:),size(r.busdc,1),n);
roles={'AC slack';'VSC 1 PCC';'VSC 2 PCC';'Corridor / transformer'; ...
    'Growing load + VSC 3 PCC';'Generator 2';'Regulated auxiliary AC bus'};
f=figure('Visible','off','Color','w','Position',[30 30 1560 850]);guard=onCleanup(@()close(f));
tl=tiledlayout(f,2,4,'TileSpacing','compact','Padding','compact');
for j=1:7
    ax=nexttile(tl);phaseplot(ax,ac(j,:));ylim(ax,[.2 1.16]);
    yline(ax,on.base.bus(j,12),':','Color',[.65 .65 .65],'HandleVisibility','off');
    yline(ax,on.base.bus(j,13),':','Color',[.65 .65 .65],'HandleVisibility','off');
    title(ax,{sprintf('AC bus %d',r.bus(j,1)),roles{j}},'FontSize',11);
end
ax=nexttile(tl);axis(ax,'off');
text(ax,.02,.98,sprintf(['CORRECTED CONTINUATION\n\n' ...
    'First maximum: %.3f MW\n' ...
    'lambda = %.9f\n\n' ...
    'Voltage restorations: 0\n' ...
    'No artificial branch jump.\n\n' ...
    'Last accepted point: %.3f MW\n' ...
    'lambda = %.9f\n' ...
    'Converter capability stop.\n' ...
    'FULL endpoint NOT reached.\n\n' ...
    'Gray dotted: case VMIN / VMAX\n' ...
    '(operating criteria, not stop rules).'],Ppeak,peak,P(end),r.cpf.lam(end)), ...
    'Units','normalized','VerticalAlignment','top','FontSize',11,'Color',[.12 .12 .12]);
finish(tl,'All 7 AC-bus PV curves — branch-preserving restoration policy', ...
    'Measured FULL attempt, initial step 0.05 | Orange follows the lower branch | Common voltage scale');
exportgraphics(f,fullfile(plotdir,'all_ac_bus_pv.png'),'Resolution',150);
savefig(f,fullfile(plotdir,'all_ac_bus_pv.fig'));clear guard;

f=figure('Visible','off','Color','w','Position',[30 30 1500 990]);guard=onCleanup(@()close(f));
tl=tiledlayout(f,3,2,'TileSpacing','compact','Padding','compact');
for j=1:6
    ax=nexttile(tl);phaseplot(ax,station(j,:));ylim(ax,[.2 1.18]);
    title(ax,stationnames{j},'FontSize',12);
    if mod(j,2)==0
        yline(ax,on.o.vsc_mtdc.capability_vsc_vmax,':','Internal voltage ceiling', ...
            'Color',[.4 .4 .4],'HandleVisibility','off');
    end
end
finish(tl,'All 6 converter filter/internal AC-node PV curves', ...
    'Corrected policy: no remote restoration | PCC voltages appear in the AC-bus figure');
exportgraphics(f,fullfile(plotdir,'all_station_node_pv.png'),'Resolution',150);
savefig(f,fullfile(plotdir,'all_station_node_pv.fig'));clear guard;

f=figure('Visible','off','Color','w','Position',[30 30 1500 490]);guard=onCleanup(@()close(f));
tl=tiledlayout(f,1,3,'TileSpacing','compact','Padding','compact');
lo=min(dc(:));hi=max(dc(:));pad=max(.002,(hi-lo)*.12);
for j=1:3
    ax=nexttile(tl);phaseplot(ax,dc(j,:));ylim(ax,[lo-pad hi+pad]);
    title(ax,sprintf('DC bus %d',r.busdc(j,1)),'FontSize',12);
end
finish(tl,'All 3 DC-bus voltage versus demand curves', ...
    'Same measured path | Shared magnified DC scale | DC bus 3 retains voltage control');
exportgraphics(f,fullfile(plotdir,'all_dc_bus_pv.png'),'Resolution',150);
savefig(f,fullfile(plotdir,'all_dc_bus_pv.fig'));clear guard;

names=[compose('AC_bus_%d_pu',r.bus(:,1)); ...
    reshape([compose('VSC%d_filter_pu',1:3);compose('VSC%d_internal_pu',1:3)],[],1); ...
    compose('DC_bus_%d_pu',r.busdc(:,1))];
phase=repmat("increasing_demand",n,1);phase(imax+1:end)="lower_branch_decreasing_demand";
T=array2table([ac;station;dc]','VariableNames',cellstr(names));
T=addvars(T,(1:n)',r.cpf.lam(:),P(:),phase,'Before',1, ...
    'NewVariableNames',{'accepted_index','lambda','total_demand_MW','phase'});
writetable(T,fullfile(plotdir,'all_voltage_traces.csv'));
summary=struct('source','verified/full_050_release1.mat','accepted_points',n, ...
    'peak_lambda',peak,'peak_demand_MW',Ppeak,'last_lambda',r.cpf.lam(end), ...
    'last_demand_MW',P(end),'last_V5_pu',ac(5,end),'release_count',0, ...
    'policy_on_off_physical_traces_identical',true,'termination',r.cpf.termination);
fid=fopen(fullfile(plotdir,'summary.json'),'w');fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true));fclose(fid);
disp(summary);
    function phaseplot(ax,y)
        hold(ax,'on');
        plot(ax,P(1:imax),y(1:imax),'-','Color',[.02 .37 .72],'LineWidth',2, ...
            'DisplayName','Increasing demand');
        plot(ax,P(imax:end),y(imax:end),'-','Color',[.86 .43 .05],'LineWidth',2, ...
            'DisplayName','After maximum: decreasing demand');
        plot(ax,P(imax),y(imax),'d','Color',[.12 .12 .12],'MarkerFaceColor',[.12 .12 .12], ...
            'MarkerSize',5,'DisplayName','First loading maximum');
        plot(ax,P(end),y(end),'x','Color',[.75 .13 .18],'LineWidth',2,'MarkerSize',8, ...
            'DisplayName','Last accepted point (capability stop)');
        grid(ax,'on');xlim(ax,[160 480]);
        set(ax,'Color','w','XColor',[.15 .15 .15],'YColor',[.15 .15 .15], ...
            'GridColor',[.6 .6 .6],'FontSize',10);
    end
    function finish(layout,heading,subheading)
        title(layout,{heading;subheading},'FontSize',15,'Color',[.1 .1 .1]);
        xlabel(layout,'Total scheduled AC demand (MW)   |   P = 165 + 240 lambda', ...
            'Color',[.1 .1 .1],'FontSize',12);
        ylabel(layout,'Voltage magnitude (p.u.)','Color',[.1 .1 .1],'FontSize',12);
        aa=findall(layout,'Type','axes');usable=aa(arrayfun(@(z)numel(findobj(z,'Type','line'))>=4,aa));
        lg=legend(usable(end),'NumColumns',2,'FontSize',11,'Color','w', ...
            'TextColor',[.1 .1 .1],'EdgeColor',[.8 .8 .8]);lg.Layout.Tile='south';
        set(findall(layout,'Type','text'),'Color',[.1 .1 .1]);
    end
end
