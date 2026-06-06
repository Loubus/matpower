function mpc = case5_vsc_mtdc_beerten_droop_target
% case5_vsc_mtdc_beerten_droop_target - CPF target for VSC droop example.
%
% The target doubles the AC loads and schedules a small HVDC active-power
% support to share the loading increase with the AC grid. At lambda = 1:
%   - total active load increment is 165 MW;
%   - the HVDC schedule covers 2% of that increment, i.e. 3.3 MW;
%   - bus 3 receives 30% of the HVDC support;
%   - bus 5 receives 70% of the HVDC support.
%
% The active support is applied by making the droop Pdc set points at buses 3
% and 5 more negative, which increases AC-side active injection after losses.
%
% See also case5_vsc_mtdc_beerten_droop, runcpf_vsc_mtdc.

%   MATPOWER

[~, ~, PD, QD] = idx_bus;

base = case5_vsc_mtdc_beerten_droop;
mpc = base;

load_scale = 2.0;
mpc.bus(:, [PD QD]) = load_scale * base.bus(:, [PD QD]);

policy = struct( ...
    'policy',       'droop_scheduled', ...
    'hvdc_share',   0.02, ...
    'buses',        [3; 5], ...
    'weights',      [0.30; 0.70], ...
    'qac_buses',    [2; 5], ...
    'qac_delta',    [1; 2] );

[mpc, dispatch] = make_vsc_hvdc_dispatch_target(base, mpc, policy);
mpc.vsc_hvdc_dispatch = dispatch;
