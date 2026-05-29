function [vm, state] = psse_twodc_ac_vm(mpc, state, vm, mpopt)
% psse_twodc_ac_vm - Estimates AC voltages for PSS/E TWODC controls.
% ::
%
%   [VM, STATE] = MP.PSSE_TWODC_AC_VM(MPC, STATE, VM, MPOPT)
%
% Computes converter-bus AC voltages with active DC terminals represented as
% fixed PQ injections. If the auxiliary solve is unavailable, the input
% voltage vector is left unchanged and STATE records the fallback reason.
%
% See also mp.psse_twodc_control, mp.psse_twodc_lcc_states.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[PQ, ~, REF, ~, ~, BUS_TYPE, PD] = idx_bus;
c = idx_dcline;

state.ac_pf_success = 0;
state.ac_pf_status = 'not_run';
state.ac_pf_message = '';
idx = find(state.valid_dcline & state.active);
if isempty(idx)
    return;
end

state.ac_pf_status = 'fallback';
try
    mpc_aux = mpc;
    original_ng = [];
    if isfield(mpc_aux, 'order')
        if isfield(mpc_aux.order, 'ext') && isfield(mpc_aux.order.ext, 'gen')
            original_ng = size(mpc_aux.order.ext.gen, 1);
        end
        mpc_aux = rmfield(mpc_aux, 'order');
    end

    dcidx = state.dcline_idx(idx);
    if isfield(mpc_aux, 'gen') && ~isempty(mpc_aux.gen)
        if ~isempty(original_ng) && size(mpc_aux.gen, 1) > original_ng
            keep = true(size(mpc_aux.gen, 1), 1);
            keep(original_ng+1:end) = false;
        else
            [GEN_BUS, PG, ~, ~, ~, ~, ~, ~, PMAX, PMIN] = idx_gen;
            term_bus = unique([state.rect_bus_idx(idx); state.inv_bus_idx(idx)]);
            keep = ~(ismember(mpc_aux.gen(:, GEN_BUS), term_bus) & ...
                mpc_aux.gen(:, PG) ~= 0 & mpc_aux.gen(:, PMIN) <= 0 & ...
                mpc_aux.gen(:, PMAX) <= 0);
        end
        if any(~keep)
            mpc_aux.gen = mpc_aux.gen(keep, :);
            if isfield(mpc_aux, 'gencost') && ...
                    size(mpc_aux.gencost, 1) == length(keep)
                mpc_aux.gencost = mpc_aux.gencost(keep, :);
            end
        end
    end
    mpc_aux.dcline(dcidx, c.BR_STATUS) = 0;
    for kk = 1:length(idx)
        k = idx(kk);
        rb = state.rect_bus_idx(k);
        ib = state.inv_bus_idx(k);
        if rb <= 0 || rb > size(mpc_aux.bus, 1) || ...
                ib <= 0 || ib > size(mpc_aux.bus, 1)
            continue;
        end
        if ~isfield(state, 'pq_model') || ~state.pq_model(k)
            mpc_aux.bus(rb, PD) = mpc_aux.bus(rb, PD) + state.current_pf(k);
            mpc_aux.bus(ib, PD) = mpc_aux.bus(ib, PD) - state.current_pt(k);
        end
        if mpc_aux.bus(rb, BUS_TYPE) ~= REF
            mpc_aux.bus(rb, BUS_TYPE) = PQ;
        end
        if mpc_aux.bus(ib, BUS_TYPE) ~= REF
            mpc_aux.bus(ib, BUS_TYPE) = PQ;
        end
    end

    auxopt = mpoption(mpopt, 'verbose', 0, 'out.all', 0);
    r = runpf(mpc_aux, auxopt);
    if isstruct(r) && isfield(r, 'success') && r.success && ...
            size(r.bus, 1) == length(vm)
        [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
        vm = r.bus(:, VM);
        state.ac_pf_success = 1;
        state.ac_pf_status = 'success';
    end
catch err
    % Keep solved MATPOWER voltages when the auxiliary PQ solve is not
    % available, e.g. for islands that require the active dcline model.
    state.ac_pf_status = 'error';
    state.ac_pf_message = err.message;
end
