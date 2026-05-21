function mpc = psse_pqbrak_prepare(mpc)
% psse_pqbrak_prepare - Preserve PSS/E constant MVA load data for PQBRAK.
% ::
%
%   MPC = MP.PSSE_PQBRAK_PREPARE(MPC)
%
% Preserves the converted constant MVA bus load as the nominal load used by
% PSS/E's low-voltage load characteristic below the solution-parameter
% breakpoint ``GENERAL.PQBRAK``. The model is only used by runpf_psse.
%
% See also mp.psse_pqbrak_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, BUS_I, ~, PD, QD, ~, ~, ~, VM] = idx_bus;

if ~isfield(mpc, 'psse') || isempty(mpc.bus)
    return;
end

%% Keep the low-voltage load boundary condition out of LCC workflows here.
%% Two-terminal DC behavior is covered by its own opt-in controller.
if isfield(mpc.psse, 'twodc') && isfield(mpc.psse.twodc, 'num') && ...
        ~isempty(mpc.psse.twodc.num)
    return;
end

pqbrak = psse_system_value(mpc, 'general', 'PQBRAK', 0.7);
if isnan(pqbrak) || pqbrak <= 0
    return;
end

nb = size(mpc.bus, 1);
if ~isfield(mpc.psse, 'pqbrak') || ...
        ~isfield(mpc.psse.pqbrak, 'bus_ext') || ...
        length(mpc.psse.pqbrak.bus_ext) ~= nb
    mpc.psse.pqbrak = struct( ...
        'enabled', 1, ...
        'pqbrak', pqbrak, ...
        'bus_ext', mpc.bus(:, BUS_I), ...
        'pd0', mpc.bus(:, PD), ...
        'qd0', mpc.bus(:, QD), ...
        'scale', ones(nb, 1), ...
        'iterations', 0, ...
        'changed_last', 0 ...
    );
else
    mpc.psse.pqbrak.enabled = 1;
    mpc.psse.pqbrak.pqbrak = pqbrak;
end

scale = low_voltage_scale(mpc.bus(:, VM), pqbrak);
mpc.bus(:, PD) = mpc.psse.pqbrak.pd0(:) .* scale;
mpc.bus(:, QD) = mpc.psse.pqbrak.qd0(:) .* scale;
mpc.psse.pqbrak.scale = scale;

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end

function scale = low_voltage_scale(vm, pqbrak)
scale = ones(size(vm));
low = vm < pqbrak;
if any(low)
    x = max(min(vm(low) ./ pqbrak, 1), 0);
    scale(low) = 3 * x.^2 - 2 * x.^3;
end
