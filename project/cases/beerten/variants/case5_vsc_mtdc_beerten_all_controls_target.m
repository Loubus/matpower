function mpc = case5_vsc_mtdc_beerten_all_controls_target
% case5_vsc_mtdc_beerten_all_controls_target - CPF target for all-controls case.
%
% Doubles the AC load of CASE5_VSC_MTDC_BEERTEN_ALL_CONTROLS, redispatches
% the non-slack generator, and schedules a small droop-converter HVDC
% contribution.
%
% See also case5_vsc_mtdc_beerten_all_controls, make_cpf_gen_dispatch_target,
% make_vsc_hvdc_dispatch_target.

%   MATPOWER

[~, ~, PD, QD] = idx_bus;

base = case5_vsc_mtdc_beerten_all_controls;
mpc = base;
mpc.bus(:, [PD QD]) = 2.0 * base.bus(:, [PD QD]);

gen_policy = struct( ...
    'policy',     'participation', ...
    'gen_buses',  6, ...
    'load_share', 1.0 );
mpc = make_cpf_gen_dispatch_target(base, mpc, gen_policy);

vsc_policy = struct( ...
    'policy',     'droop_scheduled', ...
    'hvdc_share', 0.02, ...
    'buses',      3, ...
    'weights',    1, ...
    'qac_buses',  [2; 5], ...
    'qac_delta',  [1; 2] );
[mpc, dispatch] = make_vsc_hvdc_dispatch_target(base, mpc, vsc_policy);
mpc.vsc_hvdc_dispatch = dispatch;
