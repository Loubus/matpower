function accepted = psse_xfmr_guard_candidate(mpc, state0, target, mpopt)
% psse_xfmr_guard_candidate - Guards PSS/E transformer tap candidates.
% ::
%
%   ACCEPTED = MP.PSSE_XFMR_GUARD_CANDIDATE(MPC, STATE0, TARGET, MPOPT)
%
% Probes a failed transformer tap candidate row-by-row with a plain AC power
% flow. Valid tap moves are accepted onto the last solved state; rows that
% still fail as singletons are locked out and reported.
%
% See also mp.psse_xfmr_control, mp.psse_xfmr_update.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

accepted = state0;
accepted.rebuild_replay_attempted = 1;
accepted.rebuild_replay_attempts = 0;
accepted.rebuild_replay_candidate_rows = zeros(0, 1);
accepted.rebuild_replay_accepted_rows = zeros(0, 1);
accepted.rebuild_replay_rejected_rows = zeros(0, 1);
accepted.rebuild_replay_attempt_rows = {};
accepted.rebuild_replay_attempt_success = false(0, 1);
accepted.rebuild_replay_from_tap = zeros(0, 1);
accepted.rebuild_replay_to_tap = zeros(0, 1);
accepted.rebuild_replay_from_windv = zeros(0, 1);
accepted.rebuild_replay_to_windv = zeros(0, 1);
accepted.rebuild_replay_kind = zeros(0, 1);
accepted.rebuild_replay_raw_row = zeros(0, 1);
accepted.rebuild_replay_winding = zeros(0, 1);
accepted.rebuild_replay_branch_idx = zeros(0, 1);
accepted.rebuild_replay_branch_ext = zeros(0, 1);
accepted.rebuild_replay_reg_bus_idx = zeros(0, 1);
accepted.rebuild_replay_cod = zeros(0, 1);
accepted.rebuild_replay_cont = zeros(0, 1);
accepted.rebuild_replay_cw = zeros(0, 1);
accepted.rebuild_replay_windv = zeros(0, 1);
accepted.rebuild_replay_rma = zeros(0, 1);
accepted.rebuild_replay_rmi = zeros(0, 1);
accepted.rebuild_replay_vma = zeros(0, 1);
accepted.rebuild_replay_vmi = zeros(0, 1);
accepted.rebuild_replay_ntp = zeros(0, 1);
accepted.rebuild_replay_tab = zeros(0, 1);

if isempty(state0) || ~isstruct(state0) || isempty(target) || ...
        ~isstruct(target) || ~isfield(state0, 'n') || ...
        ~isfield(target, 'current_tap') || ~isfield(target, 'current_raw') || ...
        numel(target.current_tap) ~= state0.n || ...
        numel(target.current_raw) ~= state0.n
    accepted = mark_rejected(accepted, zeros(0, 1));
    return;
end

moved = abs(target.current_tap(:) - state0.current_tap(:)) > 1e-9;
moved = moved & state0.controllable(:);
rows = find(moved);
accepted.rebuild_replay_candidate_rows = rows(:);
accepted = replay_row_metadata(accepted, rows, target);
accepted = reset_replay_control_state(accepted);

if isempty(rows)
    accepted.report = mp.psse_xfmr_report(accepted);
    return;
end

queue = split_rows(rows);
while ~isempty(queue)
    rows = queue{1};
    queue(1) = [];
    trial = copy_candidate_rows(accepted, target, rows);
    ok = probe_candidate(mpc, trial, mpopt);
    accepted.rebuild_replay_attempts = accepted.rebuild_replay_attempts + 1;
    accepted.rebuild_replay_attempt_rows{end+1, 1} = rows(:);
    accepted.rebuild_replay_attempt_success(end+1, 1) = ok;
    if ok
        accepted = trial;
        accepted.rebuild_replay_accepted_rows = unique([ ...
            accepted.rebuild_replay_accepted_rows(:); rows(:)]);
    elseif numel(rows) > 1
        queue = [split_rows(rows); queue]; %#ok<AGROW>
    else
        accepted = mark_rejected(accepted, rows);
    end
end

accepted.changed_last = numel(accepted.rebuild_replay_accepted_rows);
if isfield(state0, 'num_adjustments') && ~isempty(state0.num_adjustments)
    accepted.num_adjustments = state0.num_adjustments + accepted.changed_last;
end
accepted.report = mp.psse_xfmr_report(accepted);

function chunks = split_rows(rows)
rows = rows(:);
if numel(rows) <= 1
    chunks = {rows};
else
    mid = floor(numel(rows) / 2);
    chunks = {rows(1:mid); rows(mid+1:end)};
end

function state = copy_candidate_rows(state, target, rows)
rows = rows(:);
state.current_tap(rows) = target.current_tap(rows);
state.current_raw(rows) = target.current_raw(rows);

function state = mark_rejected(state, rows)
rows = rows(:);
rows = rows(rows > 0 & rows <= state.n);
if ~isfield(state, 'locked_out') || isempty(state.locked_out)
    state.locked_out = false(state.n, 1);
end
state.locked_out(rows) = true;
state.rebuild_replay_rejected_rows = unique([ ...
    state.rebuild_replay_rejected_rows(:); rows(:)]);
if ~isfield(state, 'rebuild_rejected_rows') || ...
        isempty(state.rebuild_rejected_rows)
    state.rebuild_rejected_rows = zeros(0, 1);
end
state.rebuild_rejected_rows = unique([ ...
    state.rebuild_rejected_rows(:); rows(:)]);

function state = replay_row_metadata(state, rows, target)
rows = rows(:);
state.rebuild_replay_from_tap = state.current_tap(rows);
state.rebuild_replay_to_tap = target.current_tap(rows);
state.rebuild_replay_from_windv = state.current_raw(rows);
state.rebuild_replay_to_windv = target.current_raw(rows);
state.rebuild_replay_kind = value_or_empty(state, 'kind', rows);
state.rebuild_replay_raw_row = value_or_empty(state, 'raw_row', rows);
state.rebuild_replay_winding = value_or_empty(state, 'winding', rows);
state.rebuild_replay_branch_idx = value_or_empty(state, 'branch_idx', rows);
state.rebuild_replay_branch_ext = value_or_empty(state, 'branch_ext', rows);
state.rebuild_replay_reg_bus_idx = value_or_empty(state, 'reg_bus_idx', rows);
state.rebuild_replay_cod = value_or_empty(state, 'cod', rows);
state.rebuild_replay_cont = value_or_empty(state, 'cont', rows);
state.rebuild_replay_cw = value_or_empty(state, 'cw', rows);
state.rebuild_replay_windv = value_or_empty(state, 'windv', rows);
state.rebuild_replay_rma = value_or_empty(state, 'rma', rows);
state.rebuild_replay_rmi = value_or_empty(state, 'rmi', rows);
state.rebuild_replay_vma = value_or_empty(state, 'vma', rows);
state.rebuild_replay_vmi = value_or_empty(state, 'vmi', rows);
state.rebuild_replay_ntp = value_or_empty(state, 'ntp', rows);
state.rebuild_replay_tab = value_or_empty(state, 'tab', rows);

function v = value_or_empty(state, field, rows)
if isfield(state, field) && numel(state.(field)) >= max([rows; 0])
    v = state.(field)(rows);
else
    v = zeros(size(rows));
end

function state = reset_replay_control_state(state)
state.changed_last = 0;
state.control_failed = 0;
state.failure_reason = '';
state.visited_signatures = {};
state.best_score = Inf;
state.best_tap = state.current_tap;
state.best_raw = state.current_raw;
state.best_violations = 0;
state.best_violation_sum = 0;
state.cycle_detected = 0;
state.cycle_resolved = 0;
state.repeated_states = 0;
state.cycle_resolution_changes = 0;
state.cycle_probe_attempted = 0;
state.cycle_probe_pending = 0;
if ~isfield(state, 'rebuild_rejected') || isempty(state.rebuild_rejected)
    state.rebuild_rejected = 0;
end
state.rebuild_rejected = state.rebuild_rejected + 1;

function ok = probe_candidate(mpc, state, mpopt)
ok = false;
try
    candidate = mp.psse_xfmr_update(mpc, state);
    if isfield(candidate, 'order')
        candidate = rmfield(candidate, 'order');
    end
    auxopt = mpoption(mpopt, 'verbose', 0, 'out.all', 0, ...
        'pf.enforce_q_lims', 0);
    auxopt.exp.mpx = {};
    auxopt.exp.use_legacy_core = 0;
    warn_state = warning;
    cleanup = onCleanup(@() warning(warn_state));
    warning('off', 'all');
    r = runpf(candidate, auxopt);
    if isstruct(r) && isfield(r, 'success') && r.success && ...
            isfield(r, 'bus') && ~isempty(r.bus)
        [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
        vm = r.bus(:, VM);
        ok = all(isfinite(vm)) && min(vm) > 0.05 && max(vm) < 5;
    end
catch
    ok = false;
end
