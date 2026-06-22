function mpc = case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit
% case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit - CPF direction
% case for the Beerten paper-mode VSC case with PSS/E controls.
%
% This is not a generation or HVDC final target. It defines only the loading
% direction used by CPF. The normalization is the usual CPF convention
% P(lambda)=P0*(1+lambda), Q(lambda)=Q0*(1+lambda), so lambda is the
% relative load increase over the base case. Generator and HVDC redispatch
% are applied incrementally by RUNCpf_VSC_MTDC from MPC.CPF_POLICIES using
% d_lambda between accepted CPF points.
%
% The load direction and incremental redespacho policies are formalized in
% MPC.CPF_POLICIES on the base case and copied here for traceability.
%
% See also case5_vsc_mtdc_beerten_paper_controls_cap_explicit,
% runcpf_vsc_mtdc, run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve.

%   MATPOWER

%%-----  User configuration and policy definitions  -----%%
[~, ~, PD, QD] = idx_bus;

cfg = struct();
cfg.profile = 'beerten_paper_modes_cpf_direction_with_formal_dispatch';
cfg.load_increment_scale = 1.00;
cfg.load_scale = 1 + cfg.load_increment_scale;
cfg.full_pv_curve_mpopt = struct( ...
    'cpf_stop_at',    'NOSE', ...
    'cpf_step',       0.05, ...
    'cpf_step_max',   0.05, ...
    'cpf_adapt_step', 0, ...
    'cpf_max_lam',    20, ...
    'capability_enforce', 1, ...
    'capability_max_it', 10 );

%%-----  Build target load direction only  -----%%
base = case5_vsc_mtdc_beerten_paper_controls_cap_explicit;
mpc = base;
mpc.explicit_options.cpf_direction = cfg;
mpc.cpf_policies = base.cpf_policies;

%% AC loading direction.
mpc.bus(:, [PD QD]) = cfg.load_scale * base.bus(:, [PD QD]);
