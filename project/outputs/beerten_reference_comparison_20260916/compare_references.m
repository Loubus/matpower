function compare_references(project_root)
% Reproducible read-only case comparison. Writes only to this new output folder.
out = fileparts(mfilename('fullpath'));
c = idx_vsc;
opt = mpoption('verbose', 0, 'out.all', 0);
opt.vsc_mtdc.method = 'unified';
opt.vsc_mtdc.capability_enforce = false;
opt.vsc_mtdc.capability_pf_enforce = false;
local_case = case5_vsc_mtdc_beerten;
lastwarn('');
[local_result, local_success] = runpf_vsc_mtdc(local_case, opt);
[local_warning, local_warning_id] = lastwarn;
assert(local_success, 'Current local base PF did not converge.');

% Load the author input files without adding conflicting solver/index paths.
refroot = fullfile(project_root, 'outputs', 'beerten_validation_batch6_20260911');
caseacpath = fullfile(refroot, 'reference', 'MatACDC1.0', 'Cases', 'PowerflowAC');
casedcpath = fullfile(refroot, 'reference', 'MatACDC1.0', 'Cases', 'PowerflowDC');
addpath(caseacpath, casedcpath);
path_cleanup = onCleanup(@() rmpath(caseacpath, casedcpath));
[baseMVA, bus, gen, branch] = case5_stagg;
[baseMVAac, baseMVAdc, pol, busdc, convdc, branchdc] = case5_stagg_MTDCslack;
assert(baseMVA == baseMVAac && baseMVAac == baseMVAdc);
assert(all(bus(:, 10) == convdc(1, 12)) && all(busdc(:, 6) == convdc(1, 12)));
translated_case = struct('version', '2', 'baseMVA', baseMVA, 'bus', bus);
translated_case.gen = zeros(size(gen,1), 21);
translated_case.gen(:,1:size(gen,2)) = gen;
translated_case.branch = zeros(size(branch,1), 13);
translated_case.branch(:,1:size(branch,2)) = branch;
translated_case.branch(:,12:13) = repmat([-360 360], size(branch,1), 1);
translated_case.busdc = [busdc(:,1), ones(3,1), busdc(:,5:6)];
% Author DC equation multiplies conductance by pol; ours uses total conductance.
translated_case.branchdc = [branchdc(:,1:2), branchdc(:,3)/pol, branchdc(:,9)];
v = zeros(3,29);
v(:,c.VSC_BUS) = busdc(:,2);
v(:,c.BUSDC) = convdc(:,1);
v(:,c.VSC_STATUS) = convdc(:,16);
v(:,c.AC_MODE) = [c.VSC_AC_PQ; c.VSC_AC_V; c.VSC_AC_PQ];
v(:,c.DC_MODE) = [c.VSC_DC_PDC; c.VSC_DC_VDC; c.VSC_DC_PDC];
v(:,c.PAC_SET) = convdc(:,4);
v(:,c.QAC_SET) = convdc(:,5);
v(:,c.VAC_SET) = convdc(:,6);
v(:,c.VDC_SET) = busdc(:,5);
v(:,c.TR_R:c.TR_X) = convdc(:,7:8);
v(:,c.FILTER_B) = convdc(:,9);
v(:,c.REACTOR_R:c.REACTOR_X) = convdc(:,10:11);
ibase_kA = baseMVA ./ (sqrt(3)*convdc(:,12));
v(:,c.LOSS_A) = convdc(:,17);
v(:,c.LOSS_B) = convdc(:,18).*ibase_kA;
% Match actual archived calclossac.m: Pc<0 uses LossCinv, Pc>0 LossCrec.
% Local input has one C per station; this translation applies to this base point.
loss_c_column = [20;19;19];
v(:,c.LOSS_C) = convdc(sub2ind(size(convdc),(1:3)',loss_c_column)).*ibase_kA.^2;
translated_case.vsc = v;
translated_case.vsc_capability = struct('Snom',baseMVA*convdc(:,15), ...
    'VconvMax',convdc(:,13));
clear path_cleanup;
lastwarn('');
[translated_result, translated_success] = runpf_vsc_mtdc(translated_case,opt);
[translated_warning, translated_warning_id] = lastwarn;
assert(translated_success, 'Translated author-case PF did not converge.');
assert(isequal(sign(translated_result.vsc(:,c.PCONV)),[-1;1;1]), ...
    'Fixed loss coefficients require the documented base-point directions.');
author = jsondecode(fileread(fullfile(refroot,'author_reference.json')));
assert(author.success == 1, 'Archived author reference did not converge.');

paper_bus = [1 1.060 0; 2 1 -2.39; 3 1 -3.90; 4 .996 -4.27; 5 .991 -4.15];
% PCC bus, Uc, angle Uc, Ps, Qs, station Ploss, station Qloss, bridge loss, paper Pdc, Vdc.
paper_conv = [2 .984 -3.760 -60 -40 .05 2.08 1.36 -58.59 1.008; ...
    3 1.003 -3.431 20.68 7.17 0 .19 1.15 21.84 1; ...
    5 .993 -3.340 35 5 .01 .51 1.19 36.21 .998];
local_conv = conv_table(local_result,c);
translated_conv = conv_table(translated_result,c);
author_conv = [busdc(:,2), author.dc.convdc(:,25:26), author.dc.convdc(:,4:5), ...
    author.dc.convdc(:,27)-author.dc.convdc(:,4), ...
    author.dc.convdc(:,28)-author.dc.convdc(:,5), ...
    author.dc.convdc(:,29),author.dc.busdc(:,4:5)];
metrics = struct;
metrics.local_vs_paper = struct('max_bus_vm_pu',max(abs(local_result.bus(:,8)-paper_bus(:,2))), ...
    'max_bus_va_deg',max(abs(local_result.bus(:,9)-paper_bus(:,3))), ...
    'max_converter_absolute_errors',max(abs(local_conv(:,2:end)-paper_conv(:,2:end)),[],1));
metrics.translated_vs_author = struct( ...
    'max_bus_vm_pu',max(abs(translated_result.bus(:,8)-author.ac.bus(:,8))), ...
    'max_bus_va_deg',max(abs(translated_result.bus(:,9)-author.ac.bus(:,9))), ...
    'max_gen_pg_MW',max(abs(translated_result.gen(:,2)-author.ac.gen(:,2))), ...
    'max_gen_qg_MVAr',max(abs(translated_result.gen(:,3)-author.ac.gen(:,3))), ...
    'max_ac_branch_power_MVA_components',max(abs(translated_result.branch(:,14:17)-author.ac.branch(:,14:17)),[],'all'), ...
    'max_converter_absolute_errors',max(abs(translated_conv(:,2:end)-author_conv(:,2:end)),[],1), ...
    'max_internal_p_MW',max(abs(translated_result.vsc(:,c.PCONV)-author.dc.convdc(:,27))), ...
    'max_internal_q_MVAr',max(abs(translated_result.vsc(:,c.QCONV)-author.dc.convdc(:,28))));
payload = struct('local_success',local_success,'translated_success',translated_success, ...
    'author_archived_success',author.success,'author_reference_is_archived',true, ...
    'local_iterations',local_result.iterations,'translated_iterations',translated_result.iterations, ...
    'local_warning',local_warning,'local_warning_id',local_warning_id, ...
    'translated_warning',translated_warning,'translated_warning_id',translated_warning_id, ...
    'capability_limits_enforced',false,'metrics',metrics, ...
    'paper_bus',paper_bus,'local_bus',local_result.bus(:,[1 8 9]), ...
    'author_bus',author.ac.bus(:,[1 8 9]),'translated_bus',translated_result.bus(:,[1 8 9]), ...
    'converter_columns',{{'PCCbus','Uc_pu','Uc_angle_deg','Ppcc_MW','Qpcc_MVAr', ...
    'station_Ploss_MW','station_Qnet_consumption_MVAr','bridge_loss_MW','Pdc_paper_sign_MW','Vdc_pu'}}, ...
    'paper_converters',paper_conv,'local_converters',local_conv, ...
    'author_converters',author_conv,'translated_converters',translated_conv);
save(fullfile(out,'comparison.mat'),'payload','local_case','local_result','translated_case','translated_result','author','opt');
fid = fopen(fullfile(out,'comparison.json'),'w');
file_cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s',jsonencode(payload,PrettyPrint=true));
clear file_cleanup;
writetable(array2table(local_conv,'VariableNames',payload.converter_columns),fullfile(out,'local_converters.csv'));
writetable(array2table(translated_conv,'VariableNames',payload.converter_columns),fullfile(out,'translated_converters.csv'));
assert(metrics.translated_vs_author.max_bus_vm_pu < 1e-8);
assert(metrics.translated_vs_author.max_bus_va_deg < 1e-6);
assert(metrics.translated_vs_author.max_gen_pg_MW < 1e-5);
assert(metrics.translated_vs_author.max_gen_qg_MVAr < 1e-5);
assert(all(metrics.translated_vs_author.max_converter_absolute_errors < 1e-5));
fig = figure('Visible','off','Color','w','Theme','light','Position',[100 100 1400 560]);
fig_cleanup = onCleanup(@() close(fig));
layout = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
colors = [.28 .35 .43; .0 .40 .68; .86 .40 .13];
ax = nexttile(layout);
bar(ax,[paper_conv(:,2),local_conv(:,2),translated_conv(:,2)]);
colororder(ax,colors);
xticklabels(ax,{'C1 / PCC 2','C2 / PCC 3','C3 / PCC 5'});
ylabel(ax,'Internal converter voltage (pu)');
ylim(ax,[.85 1.04]); grid(ax,'on');
title(ax,'Similar grid voltages can hide station differences','FontSize',12);
yline(ax,.9,'--','MatACDC minimum (unenforced)','LabelHorizontalAlignment','left');
ax = nexttile(layout);
bar(ax,[paper_conv(:,8),local_conv(:,8),translated_conv(:,8)]);
colororder(ax,colors);
xticklabels(ax,{'C1 / PCC 2','C2 / PCC 3','C3 / PCC 5'});
ylabel(ax,'Converter bridge losses (MW)');
ylim(ax,[0 1.5]); grid(ax,'on');
title(ax,'Loss models distinguish the references','FontSize',12);
lgd = legend(ax,{'2010 paper (rounded)','Current local case','Translated author MatACDC case'}, ...
    'Orientation','horizontal');
lgd.Layout.Tile = 'south';
exportgraphics(fig,fullfile(out,'comparison.png'),'Resolution',160);
disp(jsonencode(payload,PrettyPrint=true));
end

function table = conv_table(r,c)
[~, internal_rows] = ismember(r.vsc(:,c.INTERNAL_BUS),r.ac.bus(:,1));
table = [r.vsc(:,c.VSC_BUS),r.vsc(:,c.VAC_INTERNAL),r.ac.bus(internal_rows,9), ...
    r.vsc(:,[c.PAC c.QAC]),r.vsc(:,c.PCONV)-r.vsc(:,c.PAC), ...
    r.vsc(:,c.QCONV)-r.vsc(:,c.QAC),r.vsc(:,c.PLOSS),-r.vsc(:,c.PDC),r.vsc(:,c.VDC)];
end
