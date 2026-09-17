function mpc = psse_pqbrak_prepare(mpc, mpopt)
% psse_pqbrak_prepare - Preserve PSS/E constant MVA load data for PQBRAK.
% ::
%
%   MPC = MP.PSSE_PQBRAK_PREPARE(MPC, MPOPT)
%
% Disabled globally by default. Explicit exp.psse_pqbrak = 1 opts in.
% Disabling a prepared cache restores only its scaled native-load component;
% other equivalent demands are preserved. RAW thresholds remain unchanged.
%
% Preserves the converted constant MVA bus load as the nominal load used by
% PSS/E's low-voltage load characteristic below the solution-parameter
% breakpoint ``GENERAL.PQBRAK``. The model is only used by runpf_psse and is
% applied as the load component of bus demand, leaving other controls free to
% add their own equivalent demand.
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

enabled = nargin >= 2 && isfield(mpopt, 'exp') && ...
    isfield(mpopt.exp, 'psse_pqbrak') && logical(mpopt.exp.psse_pqbrak);
pqbrak = mp.psse_system_value(mpc, 'general', 'PQBRAK', 0.7);
enabled = enabled && isfinite(pqbrak) && pqbrak > 0;
if ~enabled
    if isfield(mpc.psse, 'pqbrak')
        old = mpc.psse.pqbrak;
        if all(isfield(old, {'bus_ext', 'pd0', 'qd0', 'scale'}))
            [found, loc] = ismember(mpc.bus(:, BUS_I), old.bus_ext);
            idx = loc(found);
            mpc.bus(found, PD) = mpc.bus(found, PD) + old.pd0(idx) .* (1-old.scale(idx));
            mpc.bus(found, QD) = mpc.bus(found, QD) + old.qd0(idx) .* (1-old.scale(idx));
        end
    end
    mpc.psse.pqbrak = struct('enabled', 0, 'pqbrak', 0, ...
        'disabled_reason', 'exp.psse_pqbrak_off_or_invalid_threshold', ...
        'bus_ext', mpc.bus(:, BUS_I), 'pd0', mpc.bus(:, PD), ...
        'qd0', mpc.bus(:, QD), 'scale', ones(size(mpc.bus,1),1), ...
        'iterations', 0, 'changed_last', 0);
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

scale = mp.psse_pqbrak_scale(mpc.bus(:, VM), pqbrak);
mpc.bus(:, PD) = mpc.psse.pqbrak.pd0(:) .* scale;
mpc.bus(:, QD) = mpc.psse.pqbrak.qd0(:) .* scale;
mpc.psse.pqbrak.scale = scale;
