function mpc = psse_facts_update(mpc, state)
% psse_facts_update - Applies PSS/E FACTS state to an MPC.
% ::
%
%   MPC = MP.PSSE_FACTS_UPDATE(MPC, STATE)
%
% Incrementally updates ``mpc.bus(:, QD)`` with the controlled STATCON
% reactive injection and synchronizes ``mpc.psse.facts`` with a diagnostic
% control report.
%
% See also mp.psse_facts_control, mp.psse_facts_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[~, ~, ~, ~, ~, ~, ~, QD, ~, BS] = idx_bus;

nb = size(mpc.bus, 1);
prev_q_by_bus = previous_q_by_bus(mpc, state, nb);
prev_b_by_bus = previous_b_by_bus(mpc, state, nb);
[q_by_bus, b_by_bus, qconst, b] = current_equiv_by_bus(mpc, state, nb);

mpc.bus(:, QD) = mpc.bus(:, QD) + prev_q_by_bus - q_by_bus;
mpc.bus(:, BS) = mpc.bus(:, BS) - prev_b_by_bus + b_by_bus;
mpc.psse.facts.qinj = state.current_q;
mpc.psse.facts.qconst_mvar = qconst;
mpc.psse.facts.b_mvar = b;
mpc.psse.facts.control = mp.psse_facts_report(state);

function q = previous_q_by_bus(mpc, state, nb)
q = zeros(nb, 1);
if isfield(mpc.psse.facts, 'qconst_mvar') && ...
        length(mpc.psse.facts.qconst_mvar) == state.n
    q = accum_q(state, mpc.psse.facts.qconst_mvar(:), nb, false);
elseif isfield(mpc.psse.facts, 'qinj') && ...
        length(mpc.psse.facts.qinj) == state.n
    q = accum_q(state, mpc.psse.facts.qinj(:), nb, false);
end

function b = previous_b_by_bus(mpc, state, nb)
b = zeros(nb, 1);
if isfield(mpc.psse.facts, 'b_mvar') && ...
        length(mpc.psse.facts.b_mvar) == state.n
    b = accum_q(state, mpc.psse.facts.b_mvar(:), nb, false);
end

function [q, b, qconst, bdev] = current_equiv_by_bus(mpc, state, nb)
[qconst, bdev] = facts_norton_equiv(mpc, state);
q = accum_q(state, qconst, nb, true);
b = accum_q(state, bdev, nb, true);

function [qconst, bdev] = facts_norton_equiv(mpc, state)
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
qinj = state.current_q(:);
qconst = qinj;
bdev = zeros(size(qinj));
if ~isfield(state, 'linx') || isempty(state.linx)
    return;
end
if ~isfield(state, 'solved_snapshot_mode') || ~state.solved_snapshot_mode
    return;
end
base = mpc.baseMVA;
linx = state.linx(:);
idx = find(state.active & state.bus_idx > 0 & ...
    state.bus_idx <= size(mpc.bus, 1) & linx > 0 & abs(qinj) > 0);
for kk = idx(:)'
    vi = NaN;
    if isfield(state, 'last_vi_final') && length(state.last_vi_final) >= kk
        vi = state.last_vi_final(kk);
    end
    if isnan(vi) || vi <= 0
        vi = mpc.bus(state.bus_idx(kk), VM);
    end
    if isnan(vi) || vi <= 0
        vi = 1;
    end
    x = linx(kk);
    e = vi + x * (qinj(kk) / base) / vi;
    dqdv = base * (e - 2 * vi) / x;
    bdev(kk) = dqdv / (2 * vi);
    qconst(kk) = qinj(kk) - bdev(kk) * vi ^ 2;
end

function q = accum_q(state, qinj, nb, active_only)
idx = state.bus_idx > 0 & state.bus_idx <= nb & abs(qinj) > 0;
if active_only
    idx = idx & state.active;
end
idx = find(idx);
if isempty(idx)
    q = zeros(nb, 1);
else
    q = accumarray(state.bus_idx(idx), qinj(idx), [nb 1], @sum, 0);
end
