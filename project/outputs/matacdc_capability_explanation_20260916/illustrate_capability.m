function illustrate_capability(project_root)
% Read-only author-case capability example. No network PF or case mutation.
out=fileparts(mfilename('fullpath'));
archive=fullfile(project_root,'outputs','beerten_validation_batch6_20260911','reference','MatACDC1.0');
% Isolate this dependency-free author routine, avoiding path/index collisions.
src=fileread(fullfile(archive,'convlim.m'));
src=strrep(src,'= convlim(', '= archived_convlim_probe(');
fid=fopen(fullfile(out,'archived_convlim_probe.m'),'w'); fprintf(fid,'%s',src); fclose(fid);
addpath(out);
zt=.0015+1j*.1121; zr=.0001+1j*.16428; yf=1j*.0887;
V=1; Imax=1.2; Umin=.9; Umax=1.1; Sb=100;
A=1+yf*zt; B=yf; D=1+zr*yf; E=zt+zr*A;
MI=-V^2*conj(B/A); RI=V*Imax/abs(A);
MU=-V^2*conj(D/E); RUmin=V*Umin/abs(E); RUmax=V*Umax/abs(E);
S=-.6-1j*.4; Is=conj(S/V); Ic=A*Is+B*V; Uc=D*V+E*Is;
[violation, Slimited]=archived_convlim_probe(S,V,Uc,zt,imag(yf),zr,Imax,Umax,Umin,1,.01,0);
Il=A*conj(Slimited/V)+B*V; Ul=D*V+E*conj(Slimited/V);
assert(violation==1 && abs(real(Slimited)-real(S))<1e-12);
assert(abs(abs(Ul)-Umin)<1e-8 && abs(Il)<Imax);
evidence=struct('PCC_voltage_pu',V,'current_limit_pu',Imax,'internal_voltage_min_pu',Umin, ...
    'internal_voltage_max_pu',Umax,'original_P_MW',real(S)*Sb,'original_Q_MVAr',imag(S)*Sb, ...
    'original_current_pu',abs(Ic),'original_internal_voltage_pu',abs(Uc),'violation_code',violation, ...
    'limited_P_MW',real(Slimited)*Sb,'limited_Q_MVAr',imag(Slimited)*Sb, ...
    'limited_current_pu',abs(Il),'limited_internal_voltage_pu',abs(Ul), ...
    'scope','One convlim call at fixed PCC voltage; not a limit-enforced network PF');
fid=fopen(fullfile(out,'evidence.json'),'w'); fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true)); fclose(fid);
save(fullfile(out,'evidence.mat'),'evidence','A','B','D','E','MI','RI','MU','RUmin','RUmax');
fig=figure('Visible','off','Theme','light','Color','w','Position',[100 100 1100 720]);
cleanup=onCleanup(@() close(fig));
ax=axes(fig); hold(ax,'on');
[P,Q]=meshgrid(linspace(-145,145,601),linspace(-145,100,601));
sp=(P+1j*Q)/Sb; i=A*conj(sp)/V+B*V; u=D*V+E*conj(sp)/V;
feasible=abs(i)<=Imax & abs(u)>=Umin & abs(u)<=Umax;
contourf(ax,P,Q,double(feasible),[.5 1.5],'LineStyle','none','HandleVisibility','off');
colormap(ax,[.81 .93 .88]);
theta=linspace(0,2*pi,1000);
circles=[MI;MU;MU]; radii=[RI;RUmin;RUmax]; colors=[.1 .35 .65;.8 .26 .1;.48 .24 .65];
for k=1:3
    z=(circles(k)+radii(k)*exp(1j*theta))*Sb;
    plot(ax,real(z),imag(z),'LineWidth',2,'Color',colors(k,:));
end
plot(ax,real(S)*Sb,imag(S)*Sb,'rx','LineWidth',2.5,'MarkerSize',12);
plot(ax,real(Slimited)*Sb,imag(Slimited)*Sb,'ko','LineWidth',2,'MarkerSize',8);
text(ax,-57,-44,'Original: (-60, -40)','FontSize',11,'Color',[.6 0 0]);
text(ax,-57,-29,sprintf('Q clipped to %.3f MVAr',imag(Slimited)*Sb),'FontSize',11);
plot(ax,[-60 -60],[-40 imag(Slimited)*Sb],'k--','HandleVisibility','off');
axis(ax,'equal'); xlim(ax,[-145 145]); ylim(ax,[-145 100]); grid(ax,'on');
xlabel(ax,'PCC active injection P_s (MW)'); ylabel(ax,'PCC reactive injection Q_s (MVAr)');
title(ax,{'Author MatACDC station capability at |U_s| = 1 pu', ...
    'Green: feasible intersection; current and voltage circles mapped to PCC'});
legend(ax,{'I_c = 1.2 pu','U_c = 0.9 pu','U_c = 1.1 pu','Original C1 point','Author convlim correction'}, ...
    'Location','southoutside','NumColumns',3);
exportgraphics(fig,fullfile(out,'capability.png'),'Resolution',160);
disp(jsonencode(evidence,PrettyPrint=true));
end
