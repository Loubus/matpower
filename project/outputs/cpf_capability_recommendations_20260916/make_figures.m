function make_figures
% Explanatory figures from saved verified runs; no production rerun or edits.
out=fileparts(mfilename('fullpath')); src=fullfile(out,'..','ultc_swshunt_g2_150mw_20260916');
d=load(fullfile(src,'main_run.mat')); r=d.g150_r;
h=load(fullfile(src,'half_step_run.mat')); h=h.g150_hr;
j=load(fullfile(src,'coupled_boundary_probes.mat')); j=j.g150_joint;
fold=load(fullfile(src,'frozen_Q_folds.mat')); fold=fold.evidence;

f=fig([1100 650]); tiledlayout(1,2,'TileSpacing','compact');
nexttile; semilogy(j.history(:,1),j.history(:,2),'o-','LineWidth',2); hold on;
semilogy(j.fixed_Q_probe.history(:,1),j.fixed_Q_probe.history(:,2),'s-','LineWidth',2);
yline(1e-9,':'); grid on; xlabel('Newton update'); ylabel('Maximum residual (p.u.)');
title('Saved diagnostic at the same failed loading'); legend('Coupled current equation','Clipped fixed-Q equation','Location','best');
nexttile; hold on; P=19.8662321159; V=linspace(.94,.985,400); qi=sqrt((150*V).^2-P^2);
plot(V,qi,'LineWidth',2); yline(j.fixed_Q_probe.Q_order,'--','Clipped Q order','LineWidth',1.4);
scatter(j.Vpcc2,j.Q2,90,[.05 .5 .3],'filled');
xlabel('PCC voltage (p.u.)'); ylabel('Upper current-boundary Q (MVAr)'); grid on;
title('Q must move together with PCC voltage'); legend('Boundary, fixed P slice','Fixed-Q order','Coupled solution','Location','best');
savefigs(f,'coupled_solution');

f=fig([1200 660]); tiledlayout(1,2,'TileSpacing','compact');
nexttile; hold on;
for k=1:2, a=fold(k); plot(a.trace(:,2),a.trace(:,1),'LineWidth',2); [v,ix]=max(a.trace(:,2)); scatter(v,a.trace(ix,1),60,'k','filled','HandleVisibility','off'); end
xline(j.lambda,'--','Failed trial','LabelOrientation','horizontal'); grid on; xlim([1.2448 1.2453]); ylim([.666 .692]);
xlabel('Loading parameter \lambda'); ylabel('Bus 5 voltage (p.u.)'); title('Fixed-lambda correction loses its intersection');
legend('Before Q clipping','After Q clipping','Location','southwest');
nexttile; a=fold(1); plot(a.trace(:,2),a.trace(:,1),'LineWidth',2); hold on;
for v=[.687 .680 .674 .669]
    [~,ix]=min(abs(a.trace(:,1)-v)); scatter(a.trace(ix,2),a.trace(ix,1),55,[.1 .5 .4],'filled');
    yline(a.trace(ix,1),':','HandleVisibility','off');
end
xlim([1.2448 1.2453]); ylim([.666 .692]); grid on;
xlabel('Loading parameter \lambda'); ylabel('Bus 5 voltage (p.u.)'); title('Voltage parameterization follows the local turn');
legend('Same saved local branch','Solved samples','Location','southwest');
savefigs(f,'continuation');

V=0.96724425260156655; S=150; epsilon=.001;
rho=linspace(0,.995,501); P=rho*S*V; Q=sqrt((S*V)^2-P.^2);
Qclip=(1-epsilon)*Q; R=sqrt(P.^2+Qclip.^2)/(S*V); reserveQ=1-R;
Qphysical=sqrt(max(0,((1-epsilon)*S*V)^2-P.^2)); Qphysical(rho>1-epsilon)=NaN;
f=fig([1200 650]); tiledlayout(1,2,'TileSpacing','compact');
nexttile; plot(rho,100*reserveQ,'LineWidth',2); hold on; yline(100*epsilon,'--','Specified current reserve');
grid on; xlabel('Active-power fraction P / (V I_{max})'); ylabel('Actual current reserve (%)'); title('A 0.1% Q cut gives a P-dependent current reserve');
nexttile; plot(P,Q-Qclip,'LineWidth',2); hold on; plot(P,Q-Qphysical,'--','LineWidth',2);
xlabel('PCC P (MW)'); ylabel('Reduction from exact Q boundary (MVAr)'); grid on;
title('At fixed PCC voltage: different physical constraints'); legend('0.1% Q cut','0.1% current reserve','Location','northwest');
savefigs(f,'reserve_comparison');

f=fig([1250 760]); tiledlayout(2,2,'TileSpacing','compact');
nexttile; plot(r.cpf.lam,squeeze(r.cpf.gen(2,3,:)),'LineWidth',1.6); hold on;
plot(h.cpf.lam,squeeze(h.cpf.gen(2,3,:)),'--','LineWidth',1.6); yline(112.5,':');
xlim([1.19 1.247]); ylim([90 114]); grid on; xlabel('\lambda'); ylabel('Generator 2 Q (MVAr)'); title('Generator PV to Q-limited transition'); legend('Step 0.10','Step 0.05','Limit','Location','northwest');
nexttile; plot(r.cpf.lam,squeeze(r.cpf.vsc(2,31,:)),'LineWidth',1.6); hold on;
plot(h.cpf.lam,squeeze(h.cpf.vsc(2,31,:)),'--','LineWidth',1.6); xlim([1.19 1.247]); grid on; xlabel('\lambda'); ylabel('VSC 2 Q (MVAr)'); title('VSC limits depend on the resulting voltage');
nexttile; stairs(r.cpf.lam,squeeze(r.cpf.branch(9,9,:)),'LineWidth',1.6); hold on;
stairs(h.cpf.lam,squeeze(h.cpf.branch(9,9,:)),'--','LineWidth',1.6); xlim([1.19 1.247]); grid on; xlabel('\lambda'); ylabel('ULTC tap'); title('Discrete taps change the electrical equations');
nexttile; plot(r.cpf.lam,squeeze(r.cpf.bus(5,8,:)),'LineWidth',1.6); hold on;
plot(h.cpf.lam,squeeze(h.cpf.bus(5,8,:)),'--','LineWidth',1.6); xlim([1.19 1.247]); grid on; xlabel('\lambda'); ylabel('Bus 5 voltage (p.u.)'); title('Mode history matters near the endpoint');
savefigs(f,'control_interaction');

f=fig([1200 650]); tiledlayout(1,2,'TileSpacing','compact');
nexttile; plot(1:numel(r.cpf.lam),r.cpf.lam,'LineWidth',1.8); grid on; xlabel('Accepted point index'); ylabel('\lambda'); title('129 accepted points; a local maximum is followed');
xlim([35 129]); ylim([1.24495 1.2452]);
nexttile; plot(1:size(r.cpf.z,2),r.cpf.z(end,:),'LineWidth',1.8); yline(0,'--'); grid on;
xlim([42 65]); ylim([-.0025 .0025]); xlabel('Accepted point index'); ylabel('Loading tangent component'); title('Tangent sign change is evidence of a turn');
savefigs(f,'event_reporting');

eq={
 {'map',{'$s_s=(P_s+jQ_s)/S_N,\quad i_s=\overline{s_s/u_s}$', '$i_c=A i_s+B u_s,\qquad u_c=D u_s+E i_s$', '$g_I=|i_c|^2/I_{\lim}^2-1\leq0,\quad g_U=|u_c|^2/U_{\max}^2-1\leq0$'}}, ...
 {'row',{'$\mathrm{Normal:}\quad |u_s|-V_{\mathrm{set}}=0\quad\mathrm{or}\quad Q_s-Q_{\mathrm{set}}=0$', '$\mathrm{Current\ limited:}\quad g_I(x)=0\qquad\mathrm{(replace\ one\ control\ equation)}$', '$V_{dc}-V_{dc,\mathrm{set}}=0,\qquad P_{\mathrm{conv}}+P_{dc}+P_{\mathrm{loss}}=0$'}}, ...
 {'jacobian',{'$d i_c=A\left(\frac{d\overline{s_s}}{\overline{u_s}}-\frac{\overline{s_s}\,d\overline{u_s}}{\overline{u_s}^{\,2}}\right)+B\,du_s$', '$d g_I=\frac{2\,\mathrm{Re}\{\overline{i_c}\,d i_c\}}{I_{\lim}^{\,2}}$', '$d u_c=D\,du_s+E\,d i_s,\qquad d g_U=\frac{2\,\mathrm{Re}\{\overline{u_c}\,d u_c\}}{U_{\max}^{\,2}}$'}}, ...
 {'cpf',{'$F_a(x,\lambda)=0,\qquad p=t_x^T(x-x_k)+t_\lambda(\lambda-\lambda_k)-\Delta s=0$', '$\left[\begin{array}{cc}F_{a,x}&F_{a,\lambda}\\t_x^T&t_\lambda\end{array}\right]\left[\begin{array}{c}\Delta x\\\Delta\lambda\end{array}\right]=-\left[\begin{array}{c}F_a\\p\end{array}\right]$', '$F_{a,x}t_x+F_{a,\lambda}t_\lambda=0,\qquad\|t\|=1$'}}, ...
 {'reserve',{'$I_{\lim}=(1-\epsilon_I)I_{\max},\qquad |i_c|^2-I_{\lim}^2=0$', '$Q_I=\sqrt{[(1-\epsilon_I)K]^2-P^2},\qquad K=150V_s$', '$Q_{\mathrm{clip}}=(1-\epsilon_Q)\sqrt{K^2-P^2},\quad\frac{I_{\mathrm{clip}}}{I_{\max}}=\sqrt{\rho^2+(1-\epsilon_Q)^2(1-\rho^2)},\quad\rho=P/K$'}}, ...
 {'active',{'$\mathrm{Generator\ PV:}\quad V_G-V_G^{\mathrm{set}}=0$', '$\mathrm{Generator\ Q\ limit:}\quad Q_G-Q_G^{\max}(P_G)=0$', '$\|F_a\|_\infty\leq\tau_F,\quad g_{\mathrm{inactive}}\leq\tau_g,\quad |g_{\mathrm{active}}|\leq\tau_g$'}}};
for k=1:numel(eq)
    entry=eq{k}; lines=entry{2}; f=fig([1500 430]); axes('Position',[0 0 1 1]); axis off;
    for n=1:numel(lines), text(.025,1-n*.27,lines{n},'Interpreter','latex','FontSize',20); end
    exportgraphics(f,fullfile(out,['eq_' entry{1} '.svg']),'ContentType','vector','BackgroundColor','white');
    exportgraphics(f,fullfile(out,['eq_' entry{1} '.png']),'Resolution',110,'BackgroundColor','white'); close(f);
end
rho0=19.866214718760027/(150*V); actual=1-sqrt(rho0^2+(1-epsilon)^2*(1-rho0^2));
summary=struct('source_folder',src,'fixed_voltage',V,'Q_cut_fraction',epsilon,'current_reserve_at_saved_P_percent',100*actual, ...
    'current_reserve_at_rho_0_8_percent',100*(1-sqrt(.8^2+(1-epsilon)^2*(1-.8^2))), ...
    'current_reserve_at_rho_0_99_percent',100*(1-sqrt(.99^2+(1-epsilon)^2*(1-.99^2))));
fid=fopen(fullfile(out,'new_calculations.json'),'w'); fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true)); fclose(fid); disp(summary);
    function f=fig(sz), f=figure('Visible','off','Color','w','Theme','light','Position',[40 40 sz]); end
    function savefigs(f,name), exportgraphics(f,fullfile(out,[name '.png']),'Resolution',145); close(f); end
end
