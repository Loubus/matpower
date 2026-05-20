function mpc = psse_twodc_update(mpc, state)
% psse_twodc_update - Applies PSS/E two-terminal DC state to an MPC.
% ::
%
%   MPC = MP.PSSE_TWODC_UPDATE(MPC, STATE)
%
% Updates ``mpc.dcline`` and equivalent bus reactive demand with the current
% two-terminal DC operating point and synchronizes ``mpc.psse.twodc`` with a
% diagnostic control report.
%
% See also mp.psse_twodc_control, mp.psse_twodc_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

c = idx_dcline;
[~, ~, ~, ~, ~, ~, ~, QD] = idx_bus;

idx = find(state.valid_dcline);
if ~isempty(idx)
    dcidx = state.dcline_idx(idx);
    mpc.dcline(dcidx, c.PF) = state.current_pf(idx);
    mpc.dcline(dcidx, c.PT) = state.current_pt(idx);
    mpc.dcline(dcidx, c.LOSS0) = state.current_loss(idx);
    mpc.dcline(dcidx, c.LOSS1) = 0;
    pmin = min(0.85 * state.current_pf(idx), 1.15 * state.current_pf(idx));
    pmax = max(0.85 * state.current_pf(idx), 1.15 * state.current_pf(idx));
    mpc.dcline(dcidx, c.PMIN) = pmin;
    mpc.dcline(dcidx, c.PMAX) = pmax;
end

nb = size(mpc.bus, 1);
prev_q_by_bus = previous_q_by_bus(mpc, state, nb);
q_by_bus = current_q_by_bus(state, nb);
mpc.bus(:, QD) = mpc.bus(:, QD) - prev_q_by_bus + q_by_bus;
[q_bus, q_bus_mvar] = current_q_by_bus_number(state);
state.q_bus = q_bus;
state.q_bus_mvar = q_bus_mvar;

mpc.psse.twodc.loss_mw = state.current_loss;
mpc.psse.twodc.qacr_mvar = state.qacr_mvar;
mpc.psse.twodc.qaci_mvar = state.qaci_mvar;
mpc.psse.twodc.apply_q = state.apply_q;
mpc.psse.twodc.q_bus = state.q_bus;
mpc.psse.twodc.q_bus_mvar = state.q_bus_mvar;
mpc.psse.twodc.control = mp.psse_twodc_report(state);

function q = previous_q_by_bus(mpc, state, nb)
q = zeros(nb, 1);
if isfield(mpc.psse.twodc, 'qacr_mvar') && ...
        length(mpc.psse.twodc.qacr_mvar) == state.n
    qacr = mpc.psse.twodc.qacr_mvar;
    if isfield(mpc.psse.twodc, 'apply_q') && ...
            length(mpc.psse.twodc.apply_q) == state.n
        qacr(~mpc.psse.twodc.apply_q) = 0;
    end
    q = q + accum_q(state.rect_bus_idx, qacr, nb);
end
if isfield(mpc.psse.twodc, 'qaci_mvar') && ...
        length(mpc.psse.twodc.qaci_mvar) == state.n
    qaci = mpc.psse.twodc.qaci_mvar;
    if isfield(mpc.psse.twodc, 'apply_q') && ...
            length(mpc.psse.twodc.apply_q) == state.n
        qaci(~mpc.psse.twodc.apply_q) = 0;
    end
    q = q + accum_q(state.inv_bus_idx, qaci, nb);
end

function q = current_q_by_bus(state, nb)
qacr = state.qacr_mvar;
qaci = state.qaci_mvar;
if isfield(state, 'apply_q')
    qacr(~state.apply_q) = 0;
    qaci(~state.apply_q) = 0;
end
q = accum_q(state.rect_bus_idx, qacr, nb) + ...
    accum_q(state.inv_bus_idx, qaci, nb);

function q = accum_q(bus_idx, qdc, nb)
idx = find(bus_idx > 0 & bus_idx <= nb & abs(qdc) > 0);
if isempty(idx)
    q = zeros(nb, 1);
else
    q = accumarray(bus_idx(idx), qdc(idx), [nb 1], @sum, 0);
end

function [bus, q] = current_q_by_bus_number(state)
qacr = state.qacr_mvar;
qaci = state.qaci_mvar;
if isfield(state, 'apply_q')
    qacr(~state.apply_q) = 0;
    qaci(~state.apply_q) = 0;
end
if isfield(state, 'rect_bus') && isfield(state, 'inv_bus')
    bus_all = [state.rect_bus(:); state.inv_bus(:)];
else
    bus_all = [state.rect_bus_idx(:); state.inv_bus_idx(:)];
end
q_all = [qacr(:); qaci(:)];
idx = find(bus_all > 0 & abs(q_all) > 0);
if isempty(idx)
    bus = zeros(0, 1);
    q = zeros(0, 1);
else
    [bus, ~, grp] = unique(bus_all(idx));
    q = accumarray(grp, q_all(idx), [], @sum, 0);
end
