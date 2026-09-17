function mpc = case5_vsc_mtdc_beerten_gen_redispatch_target
% case5_vsc_mtdc_beerten_gen_redispatch_target - CPF direction for gen redispatch.
%
% The target defines only the multiplicative load direction for
% CASE5_VSC_MTDC_BEERTEN_GEN_REDISPATCH. Generator and VSC/HVDC set points are
% left at their base values; CPF redispatch is handled incrementally from
% MPC.CPF_POLICIES on accepted CPF points.
%
% See also case5_vsc_mtdc_beerten_gen_redispatch,
% runcpf_vsc_mtdc.

%   MATPOWER

[~, ~, PD, QD] = idx_bus;

base = case5_vsc_mtdc_beerten_gen_redispatch;
mpc = base;

load_scale = 2.0;
mpc.bus(:, [PD QD]) = load_scale * base.bus(:, [PD QD]);
mpc.cpf_policies = base.cpf_policies;
