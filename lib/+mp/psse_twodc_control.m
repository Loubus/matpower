function [dm_next, state] = psse_twodc_control(task, ~, nm, dm, mpopt, mpx, state)
% psse_twodc_control - Executes PSS/E two-terminal DC control.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_TWODC_CONTROL(TASK, MM, NM, DM, MPOPT, MPX, STATE)
%
% Applies the opt-in PSS/E two-terminal LCC model for preserved
% ``MDC = 1`` and ``MDC = 2`` records. The control uses solved AC bus
% voltages to compute non-capacitor-commutated converter voltages, current,
% losses, and reactive demand, then updates the MATPOWER ``dcline``
% equivalent.
%
% See also mp.task_pf_psse, mp.psse_twodc_states, mp.psse_twodc_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

dm_next = [];
if nargin < 7
    state = [];
end

%% no preserved PSS/E two-terminal DC metadata, no PSS/E DC control
if ~isfield(dm.source, 'psse') || ~isfield(dm.source.psse, 'twodc') || ...
        isempty(dm.source.psse.twodc.num) || ~isfield(dm.source, 'dcline')
    state = [];
    return;
end

%% initialize control state from preserved RAW metadata
if isempty(state) || ~isstruct(state) || ~isfield(state, 'initialized') || ...
        ~state.initialized
    state = mp.psse_twodc_states(dm.source);
end

%% keep reporting synchronized even when DC control is disabled
if ~state.enabled || ~any(state.supported)
    dm.source = mp.psse_twodc_update(dm.source, state);
    return;
end

%% stop after the PSS/E tap/shunt/DC adjustment iteration limit
if solved_snapshot_mode(state)
    if state.iterations >= state.max_iter
        state.max_iter_reached = 1;
        state.changed_last = 0;
        dm.source = mp.psse_twodc_update(dm.source, state);
        return;
    end
else
    state.iterations = state.iterations + 1;
    if state.iterations > state.max_iter
        state.max_iter_reached = 1;
        state.changed_last = 0;
        dm.source = mp.psse_twodc_update(dm.source, state);
        return;
    end
end

bus = dm.elements.bus;
vm = bus.tab.vm;
if ~isempty(nm) && isobject(nm) && isprop(nm, 'soln') && ...
        isfield(nm.soln, 'v') && ...
        length(nm.soln.v) == length(vm)
    vm = abs(nm.soln.v);
end
state0 = state;
if solved_snapshot_mode(state) || ~twodc_coupled_voltage_enabled(mpopt)
    [vm, state] = mp.psse_twodc_ac_vm(dm.source, state, vm, mpopt);
else
    state.ac_pf_success = 0;
    state.ac_pf_status = 'coupled_solution';
    state.ac_pf_message = '';
end
state = mp.psse_twodc_lcc_states(state, vm);

ctrl_tol = 1e-8;
q_changed = state.apply_q & (abs(state.next_qacr - state.qacr_mvar) > ctrl_tol | ...
    abs(state.next_qaci - state.qaci_mvar) > ctrl_tol);
changed = any(abs(state.next_pf - state.current_pf) > ctrl_tol | ...
    abs(state.next_pt - state.current_pt) > ctrl_tol | ...
    q_changed);
if changed
    prev_pf = state.current_pf;
    prev_pt = state.current_pt;
    prev_qacr = state.qacr_mvar;
    prev_qaci = state.qaci_mvar;
    state.current_pf = state.next_pf;
    state.current_pt = state.next_pt;
    state.current_loss = state.next_loss;
    state.qacr_mvar = state.next_qacr;
    state.qaci_mvar = state.next_qaci;
    state = mp.psse_twodc_guard_candidate(dm.source, state0, state, mpopt);
    changed = any(abs(state.current_pf - state0.current_pf) > ctrl_tol | ...
        abs(state.current_pt - state0.current_pt) > ctrl_tol | ...
        (state.apply_q & (abs(state.qacr_mvar - state0.qacr_mvar) > ctrl_tol | ...
        abs(state.qaci_mvar - state0.qaci_mvar) > ctrl_tol)));
end
if changed && solved_snapshot_mode(state)
    state.iterations = state.iterations + 1;
end
if changed
    state.changed_last = nnz(abs(state.current_pf - prev_pf) > ctrl_tol | ...
        abs(state.current_pt - prev_pt) > ctrl_tol | ...
        (state.apply_q & (abs(state.qacr_mvar - prev_qacr) > ctrl_tol | ...
        abs(state.qaci_mvar - prev_qaci) > ctrl_tol)));
    state.num_adjustments = state.num_adjustments + state.changed_last;
    mpc = mp.psse_twodc_update(dm.source, state);
    dm_next = task.data_model_build(mpc, task.dmc, mpopt, mpx);
else
    state.qacr_mvar = state.next_qacr;
    state.qaci_mvar = state.next_qaci;
    state.changed_last = 0;
    dm.source = mp.psse_twodc_update(dm.source, state);
end

function tf = solved_snapshot_mode(state)
tf = isfield(state, 'solved_snapshot_mode') && state.solved_snapshot_mode;

function tf = twodc_coupled_voltage_enabled(mpopt)
tf = true;
if isfield(mpopt, 'exp') && isfield(mpopt.exp, 'psse_twodc_coupled_voltage') && ...
        ~isempty(mpopt.exp.psse_twodc_coupled_voltage)
    tf = any(mpopt.exp.psse_twodc_coupled_voltage(:));
end
