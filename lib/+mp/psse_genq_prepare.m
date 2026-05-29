function mpc = psse_genq_prepare(mpc, mode)
% psse_genq_prepare - Prepares PSS/E generator Q control before ext2int.
% ::
%
%   MPC = MP.PSSE_GENQ_PREPARE(MPC)
%   MPC = MP.PSSE_GENQ_PREPARE(MPC, MODE)
%
% Applies the opt-in pre-processing needed before MATPOWER's ext2int()
% conversion for cases that preserve PSS/E GENERATOR DATA metadata in
% ``mpc.psse.genq``. It keeps the original voltage schedules and Q limits in
% metadata, fixes the internal Q limits to the current QG, and converts
% remote-regulating or already-limited generator buses to PQ unless the bus
% is a swing bus or another local generator on the same bus still regulates.
%
% See also mp.psse_genq_states, mp.psse_genq_control.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 2 || isempty(mode)
    mode = 'fixed_q';
end

if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'genq') || ...
        isempty(mpc.psse.genq.num)
    return;
end

[PQ, ~, REF, ~, ~, BUS_TYPE] = idx_bus;
[~, ~, QG, QMAX, QMIN, VG] = idx_gen;

state = mp.psse_genq_states(mpc);
gq = mpc.psse.genq;
n = state.n;

if ~isfield(gq, 'original_vs') || length(gq.original_vs) ~= n
    gq.original_vs = state.vs;
end
if ~isfield(gq, 'original_qmax') || length(gq.original_qmax) ~= n
    gq.original_qmax = state.qmax;
end
if ~isfield(gq, 'original_qmin') || length(gq.original_qmin) ~= n
    gq.original_qmin = state.qmin;
end
if ~isfield(gq, 'original_bus_type') || length(gq.original_bus_type) ~= n
    gq.original_bus_type = state.base_bus_type;
end

if strcmpi(mode, 'deferred')
    mpc = restore_deferred_prepare(mpc, state, gq);
    return;
end

mapped = find(state.gen_idx > 0);
if ~isempty(mapped)
    gi = state.gen_idx(mapped);
    q = mpc.gen(gi, QG);
    q(isnan(q)) = state.current_q(mapped(isnan(q)));
    mpc.gen(gi, QMAX) = q;
    mpc.gen(gi, QMIN) = q;
    mpc.gen(gi, VG) = state.vs(mapped);
end

pq_candidate = state.active & (state.remote | state.limited) & ...
    ~state.swing & state.bus_idx > 0;
bus_list = unique(state.bus_idx(pq_candidate));
prepared_pq = false(n, 1);
for kk = 1:length(bus_list)
    b = bus_list(kk);
    if mpc.bus(b, BUS_TYPE) == REF
        continue;
    end
    at_bus = state.active & state.bus_idx == b;
    local_reg = at_bus & state.local & ~state.limited & ~state.swing;
    if any(local_reg)
        continue;
    end
    mpc.bus(b, BUS_TYPE) = PQ;
    prepared_pq(at_bus & pq_candidate) = true;
end

gq.prepared = 1;
gq.prepare_mode = 'fixed_q';
gq.prepare_deferred = 0;
gq.prepared_pq = prepared_pq;
gq.prepared_q = state.current_q;
mpc.psse.genq = gq;

function mpc = restore_deferred_prepare(mpc, state, gq)
% Restore RAW Q limits/bus types when fixed-Q bootstrap is too fragile.

[~, PV, REF, ~, ~, BUS_TYPE] = idx_bus;
[~, ~, QG, QMAX, QMIN, VG] = idx_gen;

mapped = find(state.gen_idx > 0);
for kk = mapped(:)'
    gi = state.gen_idx(kk);
    mpc.gen(gi, QMAX) = gq.original_qmax(kk);
    mpc.gen(gi, QMIN) = gq.original_qmin(kk);
    mpc.gen(gi, VG) = state.vs(kk);
    if isnan(mpc.gen(gi, QG))
        mpc.gen(gi, QG) = state.current_q(kk);
    end
end

bus_list = unique(state.bus_idx(state.active & state.bus_idx > 0));
for jj = 1:length(bus_list)
    b = bus_list(jj);
    if b <= 0 || b > size(mpc.bus, 1)
        continue;
    end
    at_bus = state.active & state.bus_idx == b;
    if any(state.swing(at_bus)) || any(gq.original_bus_type(at_bus) == REF)
        mpc.bus(b, BUS_TYPE) = REF;
    elseif any(gq.original_bus_type(at_bus) == PV)
        mpc.bus(b, BUS_TYPE) = PV;
    else
        mpc.bus(b, BUS_TYPE) = gq.original_bus_type(find(at_bus, 1));
    end
end

gq.prepared = 1;
gq.prepare_mode = 'deferred';
gq.prepare_deferred = 1;
gq.prepared_pq = false(state.n, 1);
gq.prepared_q = state.current_q;
mpc.psse.genq = gq;
