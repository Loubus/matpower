function plot_comparison(project_root)
% Same station and PCC voltage; compare constraints, not different case data.
out=fileparts(mfilename('fullpath'));
s=load(fullfile(project_root,'outputs','vsc_directional_losses_20260916','reference_and_phasors.mat'));
mpc=s.f; c=idx_vsc; row=mpc.vsc(1,:); V=1; Umin=.9;
params=vsc_capability_params(mpc,struct,1,1); Snom=params.Smax; Umax=params.Vmax;
Sb=mpc.baseMVA; Imax=Snom/Sb;
m=vsc_station_map(row,Sb,Snom);
[~,~,~,~,info]=vsc_capability_curve(-60,-40,Snom,V,row,'preservar_p',Umax,Sb);
zt=complex(row(c.TR_R),row(c.TR_X)); zr=complex(row(c.REACTOR_R),row(c.REACTOR_X)); yf=1j*row(c.FILTER_B);
% Independent author pi equivalent, as implemented in convlim.m 92--126.
zf=1/yf; z1=(zt*zr+zr*zf+zf*zt)/zr; z2=(zt*zr+zr*zf+zf*zt)/zf;
y1=1/z1; y2=1/z2;
MI=-V^2/conj(zf+zt)*Sb; RI=V*Imax/abs(1+yf*zt)*Sb;
MU=-V^2*conj(y1+y2)*Sb; RUmax=V*Umax*abs(y2)*Sb; RUmin=V*Umin*abs(y2)*Sb;
assert(abs(info.current_center-MI)<1e-10);
assert(abs(info.iMax-RI)<1e-10);
assert(abs(info.voltage_center-MU)<1e-10);
assert(abs(info.vRadius-RUmax)<1e-10);
[P,Q]=meshgrid(linspace(-135,135,1501),linspace(-125,65,1101));
Sp=P+1j*Q; withinI=abs(Sp-MI)<=RI; withinUmax=abs(Sp-MU)<=RUmax;
aboveUmin=abs(Sp-MU)>=RUmin; withinP=abs(P)<=Snom;
ours=withinI & withinUmax & withinP;
theirs=withinI & withinUmax & aboveUmin;
common=ours & theirs; onlyOurs=ours & ~theirs; onlyTheirs=theirs & ~ours;
% Verify the rendered mask's classification against the production evaluator.
checked=0;
for p=linspace(-130,130,27)
    for q=linspace(-120,60,25)
        [~,~,~,~,actual]=vsc_capability_curve(p,q,Snom,V,row,'preservar_p',Umax,Sb);
        expected=abs(complex(p,q)-MI)<=RI && abs(complex(p,q)-MU)<=RUmax && abs(p)<=Snom;
        assert(actual.inside_original==expected,'Mask/production capability disagreement.');
        checked=checked+1;
    end
end
% Constraint intersection vertices, retaining only feasible boundary crossings.
candidate=[circle_crossings(MI,RI,MU,RUmin),circle_crossings(MI,RI,MU,RUmax)];
matVertices=candidate(abs(candidate-MI)<=RI+1e-8 & abs(candidate-MU)<=RUmax+1e-8 & abs(candidate-MU)>=RUmin-1e-8);
pverts=[];
for p=[-Snom Snom]
    for k=1:2
        center=[MI MU]; radius=[RI RUmax];
        d=radius(k)^2-(p-real(center(k)))^2;
        if d>=0, pverts=[pverts,p+1j*(imag(center(k))+[-1 1]*sqrt(d))]; end %#ok<AGROW>
    end
end
candidate=[circle_crossings(MI,RI,MU,RUmax),pverts];
ourVertices=candidate(abs(candidate-MI)<=RI+1e-8 & abs(candidate-MU)<=RUmax+1e-8 & abs(real(candidate))<=Snom+1e-8);
allcandidate=[matVertices,ourVertices];
commonVertices=allcandidate(abs(allcandidate-MI)<=RI+1e-8 & abs(allcandidate-MU)<=RUmax+1e-8 & abs(allcandidate-MU)>=RUmin-1e-8 & abs(real(allcandidate))<=Snom+1e-8);

colors=struct('current',[.10 .32 .65],'upper',[.47 .22 .66],'lower',[.82 .24 .10], ...
    'ceiling',[.30 .35 .40],'common',[.67 .85 .78],'onlyOurs',[1 .83 .53],'onlyTheirs',[.85 .76 .94]);
fig=figure('Visible','off','Theme','light','Color','w','Position',[50 70 1850 730]);
cleanup=onCleanup(@() close(fig));
layout=tiledlayout(fig,1,3,'TileSpacing','compact','Padding','compact');
titles={'Our implementation','Author MatACDC','Overlay: both feasible regions'};
for k=1:3
    ax=nexttile(layout); hold(ax,'on');
    if k==1
        fillmask(ax,P,Q,ours,colors.common); limits(ax,MI,RI,MU,RUmax,RUmin,Snom,colors,true,false);
        vertices=ourVertices;
    elseif k==2
        fillmask(ax,P,Q,theirs,colors.common); limits(ax,MI,RI,MU,RUmax,RUmin,Snom,colors,false,true);
        vertices=matVertices;
    else
        fillmask(ax,P,Q,common,colors.common); fillmask(ax,P,Q,onlyOurs,colors.onlyOurs); fillmask(ax,P,Q,onlyTheirs,colors.onlyTheirs);
        limits(ax,MI,RI,MU,RUmax,RUmin,Snom,colors,true,true); vertices=commonVertices;
    end
    plot(ax,real(vertices),imag(vertices),'ko','MarkerFaceColor','w','MarkerSize',5,'HandleVisibility','off');
    plot(ax,-60,-40,'kx','LineWidth',2,'MarkerSize',10,'HandleVisibility','off');
    text(ax,-55,-45,'C1','FontWeight','bold');
    axis(ax,'equal'); xlim(ax,[-135 135]); ylim(ax,[-125 65]); grid(ax,'on');
    xticks(ax,-120:60:120); yticks(ax,-120:30:60);
    xlabel(ax,'PCC P (MW)'); ylabel(ax,'PCC Q (MVAr)'); title(ax,titles{k});
end
title(layout,{'Capability comparison using IDENTICAL author station parameters', ...
    '|U_{PCC}| = 1 pu; I_{max} = 1.2 pu on 100 MVA; U_{max} = 1.1 pu; MatACDC U_{min} = 0.9 pu'},'FontSize',16);
lg=legend(ax,{'Current limit (shared)','Upper voltage (shared)','Our P ceiling: +/-120 MW','MatACDC lower voltage'}, ...
    'Orientation','horizontal'); lg.Layout.Tile='south';
exportgraphics(fig,fullfile(out,'comparison.png'),'Resolution',180);
exportgraphics(fig,fullfile(out,'comparison.pdf'),'ContentType','vector');
clear cleanup;

fig=figure('Visible','off','Theme','light','Color','w','Position',[100 100 1180 840]);
cleanup=onCleanup(@() close(fig)); ax=axes(fig); hold(ax,'on');
h1=fillmask(ax,P,Q,common,colors.common); h2=fillmask(ax,P,Q,onlyOurs,colors.onlyOurs); h3=fillmask(ax,P,Q,onlyTheirs,colors.onlyTheirs);
limits(ax,MI,RI,MU,RUmax,RUmin,Snom,colors,true,true);
plot(ax,real(commonVertices),imag(commonVertices),'ko','MarkerFaceColor','w','MarkerSize',6,'HandleVisibility','off');
hp=plot(ax,-60,-40,'kx','LineWidth',2.5,'MarkerSize',12);
text(ax,-56,-46,'C1: (-60, -40)','FontWeight','bold');
text(ax,-70,-80,'Allowed by ours; below MatACDC U_{min}','FontSize',11);
text(ax,-45,0,'Allowed by BOTH','FontSize',13,'FontWeight','bold');
axis(ax,'equal'); xlim(ax,[-135 135]); ylim(ax,[-125 65]); grid(ax,'on');
xlabel(ax,'PCC active injection P (MW)'); ylabel(ax,'PCC reactive injection Q (MVAr)');
title(ax,{'Overlay and intersection of all constraints','Same station, same |U_{PCC}| = 1 pu; circles = physical limits, vertical dashed lines = our P ceiling'});
legend(ax,[h1 h2 h3 hp],{'Common feasible region','Our region only','MatACDC region only (thin edge strips)','Original C1 point'}, ...
    'Location','southoutside','NumColumns',2);
exportgraphics(fig,fullfile(out,'overlay.png'),'Resolution',180);
exportgraphics(fig,fullfile(out,'overlay.pdf'),'ContentType','vector');
clear cleanup;

% Zoom the small MatACDC-only region caused by our additional active ceiling.
[Pz,Qz]=meshgrid(linspace(118,122,801),linspace(-10,25,701));
Sz=Pz+1j*Qz;
authorZ=abs(Sz-MI)<=RI & abs(Sz-MU)<=RUmax & abs(Sz-MU)>=RUmin;
commonZ=authorZ & abs(Pz)<=Snom; onlyTheirsZ=authorZ & abs(Pz)>Snom;
fig=figure('Visible','off','Theme','light','Color','w','Position',[100 100 850 600]);
cleanup=onCleanup(@() close(fig)); ax=axes(fig); hold(ax,'on');
fillmask(ax,Pz,Qz,commonZ,colors.common); fillmask(ax,Pz,Qz,onlyTheirsZ,colors.onlyTheirs);
limits(ax,MI,RI,MU,RUmax,RUmin,Snom,colors,true,true);
xlim(ax,[118 122]); ylim(ax,[-10 25]); grid(ax,'on');
xlabel(ax,'PCC P (MW)'); ylabel(ax,'PCC Q (MVAr)');
title(ax,{'Detail of the additional P ceiling','Purple strip: MatACDC accepts it; our |P| <= 120 MW ceiling excludes it'});
exportgraphics(fig,fullfile(out,'active_ceiling_zoom.png'),'Resolution',170);
clear cleanup;

evidence=struct('scope','C1 author station at fixed PCC voltage; capability geometry, not enforcement policies', ...
    'V_pu',V,'baseMVA',Sb,'Snom_MVA',Snom,'Imax_system_pu',Imax,'Umax_pu',Umax,'Umin_MatACDC_pu',Umin, ...
    'production_classification_checks',checked,'current_center_MW_MVAr',[real(MI) imag(MI)],'current_radius_MVA',RI, ...
    'voltage_center_MW_MVAr',[real(MU) imag(MU)],'voltage_max_radius_MVA',RUmax,'voltage_min_radius_MVA',RUmin, ...
    'original_C1_inside_ours',info.inside_original,'original_C1_inside_MatACDC',abs(complex(-60,-40)-MU)>=RUmin, ...
    'our_vertices_MW_MVAr',[real(ourVertices(:)) imag(ourVertices(:))], ...
    'MatACDC_vertices_MW_MVAr',[real(matVertices(:)) imag(matVertices(:))], ...
    'common_vertices_MW_MVAr',[real(commonVertices(:)) imag(commonVertices(:))]);
fid=fopen(fullfile(out,'evidence.json'),'w'); fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true)); fclose(fid);
save(fullfile(out,'evidence.mat'),'evidence','mpc','P','Q','ours','theirs','common','onlyOurs','onlyTheirs');
disp(jsonencode(evidence,PrettyPrint=true));
end

function h=fillmask(ax,P,Q,mask,color)
% Patch one grid-based region without changing the axes-wide colormap.
[~,h]=contourf(ax,P,Q,double(mask),[.5 .5],'LineStyle','none','FaceColor',color);
h.HandleVisibility='off';
end

function limits(ax,MI,RI,MU,RUmax,RUmin,Pmax,colors,includeP,includeMin)
t=linspace(0,2*pi,1501);
z=MI+RI*exp(1j*t); plot(ax,real(z),imag(z),'Color',colors.current,'LineWidth',1.8);
z=MU+RUmax*exp(1j*t); plot(ax,real(z),imag(z),'Color',colors.upper,'LineWidth',1.8);
if includeP
    xline(ax,Pmax,'--','Color',colors.ceiling,'LineWidth',1.3);
    xline(ax,-Pmax,'--','Color',colors.ceiling,'LineWidth',1.3,'HandleVisibility','off');
end
if includeMin
    z=MU+RUmin*exp(1j*t); plot(ax,real(z),imag(z),'Color',colors.lower,'LineWidth',1.8);
end
end

function z=circle_crossings(c1,r1,c2,r2)
d=abs(c2-c1);
if d>r1+r2 || d<abs(r1-r2) || d==0, z=[]; return; end
a=(r1^2-r2^2+d^2)/(2*d); h=sqrt(max(0,r1^2-a^2));
u=(c2-c1)/d; mid=c1+a*u; z=[mid+1j*h*u,mid-1j*h*u];
end
