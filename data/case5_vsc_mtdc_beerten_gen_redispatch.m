function mpc = case5_vsc_mtdc_beerten_gen_redispatch
% case5_vsc_mtdc_beerten_gen_redispatch - 5-bus Beerten CPF gen redispatch case.
%
% This case adds incremental CPF generator redispatch and active VSC/HVDC
% transfer policies to the original Beerten 5-bus VSC-MTDC case. It
% intentionally has no PSS/E ULTC or switched-shunt metadata.
%
% Lambda uses the relative-load convention:
%   P(lambda) = P0 * (1 + lambda)
%   Q(lambda) = Q0 * (1 + lambda)
%
% The in-service non-slack generator at bus 2 is scheduled to carry 70% of
% the accepted active-load increment. The slack generator at bus 1 then
% balances the remaining load increment and losses. The VSC/HVDC active
% transfer sends the bus-5 active-load share of each accepted load increment
% from bus 2 to bus 5 over the DC grid.
%
% See also case5_vsc_mtdc_beerten_gen_redispatch_target,
% run_case5_vsc_mtdc_beerten_gen_redispatch_pv_curves.

%   MATPOWER

mpc = case5_vsc_mtdc_beerten;

% Capability metadata is defined as apparent-power Smax data, but is
% inactive unless generator capability enforcement is enabled.
mpc.gen_capability.Smax = [5000 450];
mpc.vsc_capability.Smax = [150 300 150];

mpc.cpf_policies = struct();
mpc.cpf_policies.lambda_definition = 'relative_load_increase';
mpc.cpf_policies.load = struct( ...
    'policy',               'proportional_relative_increase', ...
    'load_increment_scale', 1.0, ...
    'formula',              'P(lambda)=P0*(1+lambda), Q(lambda)=Q0*(1+lambda)' );
mpc.cpf_policies.gen = struct( ...
    'policy',     'participation', ...
    'gen_buses',  2, ...
    'weights',    1, ...
    'load_share', 0.70 );
mpc.cpf_policies.hvdc = struct( ...
    'policy',               'pac_pair_transfer', ...
    'source_bus',           2, ...
    'sink_bus',             5, ...
    'gain_mw_per_mw_load',  60 / sum(mpc.bus(:, 3)) );
mpc.cpf_policies.vsc_capability = struct( ...
    'saturation_margin_fraction', 0.20 );
