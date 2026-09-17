function mpc = case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt
% case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt - 5-bus redispatch case with PSS/E controls.
%
% This study case extends CASE5_VSC_MTDC_BEERTEN_GEN_REDISPATCH with one
% PSS/E-style load-side ULTC transformer and one switched shunt. It keeps the
% same incremental CPF load, generator redispatch, HVDC redispatch, generator
% capability, and VSC capability policies as the no-control redispatch case.
%
% The PSS/E control metadata is copied from
% CASE5_VSC_MTDC_BEERTEN_ULTC_SWSHUNT:
%   - the original bus-4 load is moved behind a 4-7 ULTC transformer;
%   - bus 5 has a local discrete switched shunt.
%
% See also case5_vsc_mtdc_beerten_gen_redispatch,
% case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt_target,
% case5_vsc_mtdc_beerten_ultc_swshunt, runcpf_psse.

%   MATPOWER

[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;

mpc = case5_vsc_mtdc_beerten_gen_redispatch;
ctrl = case5_vsc_mtdc_beerten_ultc_swshunt;

%% Move bus-4 load behind auxiliary load bus 7, matching the reference case.
bus7 = ctrl.bus(ctrl.bus(:, 1) == 7, :);
mpc.bus(mpc.bus(:, 1) == 4, [PD QD]) = 0;
mpc.bus = [mpc.bus; bus7];

%% Add the load-side ULTC branch 4-7 from the reference case.
xf_branch = ctrl.branch(ctrl.psse.xfmr.two.branch_idx, :);
mpc.branch = [mpc.branch; xf_branch];

%% Copy PSS/E ULTC and switched-shunt metadata, then remap branch_idx.
mpc.psse = ctrl.psse;
mpc.psse.xfmr.two.branch_idx = size(mpc.branch, 1);

