function mpc = case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt_target
% case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt_target - CPF direction with PSS/E controls.
%
% The target defines only the multiplicative load direction for
% CASE5_VSC_MTDC_BEERTEN_GEN_REDISPATCH_ULTC_SWSHUNT. Generator, VSC/HVDC,
% ULTC and switched-shunt behavior is handled by accepted-point policy and
% active-set logic during CPF.
%
% See also case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt,
% runcpf_psse.

%   MATPOWER

[~, ~, PD, QD] = idx_bus;

base = case5_vsc_mtdc_beerten_gen_redispatch_ultc_swshunt;
mpc = base;

load_scale = 2.0;
mpc.bus(:, [PD QD]) = load_scale * base.bus(:, [PD QD]);
mpc.cpf_policies = base.cpf_policies;

