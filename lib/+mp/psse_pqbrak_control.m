function [dm_next, state] = psse_pqbrak_control(task, ~, ~, dm, mpopt, mpx, state)
% psse_pqbrak_control - Applies PSS/E low-voltage constant MVA load scaling.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_PQBRAK_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Implements the opt-in PSS/E ``PQBRAK`` boundary condition for constant MVA
% loads below the configured voltage breakpoint. Each change updates the
% effective bus demand and rebuilds the MP-Core data model, so the scaled
% load is part of the AC balance solved by runpf_psse.
%
% See also mp.psse_pqbrak_prepare.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;

dm_next = [];
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'pqbrak') || ...
        ~isfield(dm.source.psse.pqbrak, 'enabled') || ...
        ~dm.source.psse.pqbrak.enabled
    state = [];
    return;
end

if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = initialize_state(dm.source);
end

if ~any(state.active)
    dm.source.psse.pqbrak.control = report_state(state);
    return;
end

state.iterations = state.iterations + 1;
if state.iterations > state.max_iter
    state.max_iter_reached = 1;
    state.changed_last = 0;
    dm.source.psse.pqbrak.control = report_state(state);
    return;
end

bus = dm.elements.bus;
vm = bus.tab.vm;
scale = ones(state.n, 1);
for kk = find(state.active)'
    bi = state.bus_idx(kk);
    if bi > 0 && bi <= length(vm)
        scale(kk) = low_voltage_scale(vm(bi), state.pqbrak);
        state.vact(kk) = vm(bi);
    end
end

pd = state.pd0 .* scale;
qd = state.qd0 .* scale;
changed = false;
mpc = dm.source;
for kk = find(state.active)'
    bi = state.bus_idx(kk);
    if bi > 0 && bi <= size(mpc.bus, 1)
        if abs(state.pd(kk) - pd(kk)) > state.tol || ...
                abs(state.qd(kk) - qd(kk)) > state.tol
            changed = true;
        end
        mpc.bus(bi, PD) = mpc.bus(bi, PD) - state.pd(kk) + pd(kk);
        mpc.bus(bi, QD) = mpc.bus(bi, QD) - state.qd(kk) + qd(kk);
    end
end

state.scale = scale;
state.pd = pd;
state.qd = qd;
state.changed_last = changed;
state.low_voltage = state.active & scale < 1 - eps;
mpc.psse.pqbrak.control = report_state(state);
mpc.psse.pqbrak.scale = scale;
mpc.psse.pqbrak.iterations = state.iterations;
mpc.psse.pqbrak.changed_last = changed;

if changed
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    dm.source = mpc;
end

function state = initialize_state(mpc)
pq = mpc.psse.pqbrak;
n = length(pq.bus_ext);
state = struct();
state.initialized = 1;
state.n = n;
state.pqbrak = pq.pqbrak;
state.iterations = 0;
state.max_iter_reached = 0;
state.changed_last = 0;
state.max_iter = psse_system_value(mpc, 'adjust', 'MXTPSS', 99);
if isnan(state.max_iter) || state.max_iter <= 0
    state.max_iter = 99;
end
state.tol = 1e-5;
state.bus_ext = pq.bus_ext(:);
state.bus_idx = psse_bus_map(mpc, state.bus_ext);
state.pd0 = pq.pd0(:);
state.qd0 = pq.qd0(:);
state.scale = ones(n, 1);
if isfield(pq, 'scale') && length(pq.scale) == n
    state.scale = pq.scale(:);
end
state.pd = state.pd0 .* state.scale;
state.qd = state.qd0 .* state.scale;
state.vact = NaN(n, 1);
state.active = state.bus_idx > 0 & (state.pd0 ~= 0 | state.qd0 ~= 0);
state.low_voltage = false(n, 1);

function idx = psse_bus_map(mpc, bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
idx = zeros(size(bus));
if isempty(bus)
    return;
end
if isfield(mpc, 'order') && isfield(mpc.order, 'state') && ...
        strcmp(mpc.order.state, 'i') && ...
        isfield(mpc.order, 'bus') && ...
        isfield(mpc.order.bus, 'e2i') && ~isempty(mpc.order.bus.e2i)
    e2i = mpc.order.bus.e2i;
else
    i2e = mpc.bus(:, BUS_I);
    if isempty(i2e)
        return;
    end
    e2i = sparse(i2e, ones(size(i2e)), 1:length(i2e), max(i2e), 1);
end
for kk = 1:length(bus)
    b = bus(kk);
    if ~isnan(b) && b > 0 && b <= size(e2i, 1)
        idx(kk) = full(e2i(b));
    end
end

function scale = low_voltage_scale(vm, pqbrak)
scale = ones(size(vm));
low = vm < pqbrak;
if any(low)
    x = max(min(vm(low) ./ pqbrak, 1), 0);
    scale(low) = 3 * x.^2 - 2 * x.^3;
end

function val = psse_system_value(mpc, section, key, default)
val = default;
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, section) && ...
        isfield(mpc.psse.system.(section), key)
    val = mpc.psse.system.(section).(key);
end

function s = report_state(state)
s = struct( ...
    'pqbrak', state.pqbrak, ...
    'bus_ext', state.bus_ext, ...
    'bus_idx', state.bus_idx, ...
    'pd0', state.pd0, ...
    'qd0', state.qd0, ...
    'pd', state.pd, ...
    'qd', state.qd, ...
    'scale', state.scale, ...
    'vact', state.vact, ...
    'low_voltage', state.low_voltage, ...
    'iterations', state.iterations, ...
    'changed_last', state.changed_last, ...
    'max_iter_reached', state.max_iter_reached ...
);
