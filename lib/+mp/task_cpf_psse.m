classdef task_cpf_psse < mp.task_cpf_legacy
% mp.task_cpf_psse - Legacy CPF task with PSS/E controls.
%
% Adds the PSS/E control coordination used by mp.task_pf_psse to the legacy
% MP-Core CPF task. The CPF mathematical model remains MATPOWER's augmented
% continuation system; PSS/E controls are applied as data-model active-set
% updates between CPF solves.
%
% The PSS/E control order and per-family dispatch intentionally mirror
% mp.task_pf_psse. CPF keeps its own methods because control changes are
% accepted through PNE callbacks and fixed-lambda warmstarts, while PF uses
% next_dm() data-model iterations.
%
% See also mp.task_cpf_legacy, mp.task_pf_psse, mp.xt_psse, runcpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

    properties
        psse_genq = []      % PSS/E generator Q/remote regulation state/report
        psse_pqbrak = []    % PSS/E low-voltage constant MVA load state/report
        psse_xfmr = []      % PSS/E transformer tap control state/report
        psse_twodc = []     % PSS/E two-terminal DC control state/report
        psse_facts = []     % PSS/E FACTS device control state/report
        psse_swshunt = []   % PSS/E switched shunt control state/report
        psse_last_success_source = []  % last converged source MPC
        psse_rollback_done = false     % true after one rollback attempt
        psse_stop_after_rollback = false   % stop controls after rollback solve
        psse_pending_control = ''      % control family awaiting CPF acceptance
        psse_pending_source = []       % source MPC for pending control family
        psse_pending_lambda = NaN      % lambda at which the pending control changed
        psse_target_source = []        % CPF target source preserved across rebuilds
        psse_failed_control = ''       % control family whose rebuild failed
        psse_failed_after_rollback = false  % true after a failed rollback
        psse_reorient_after_warmstart = false % true after fixed-lambda PSS/E re-correction
        psse_reorient_pV = []          % previous CPF voltage for tangent orientation
        psse_reorient_plam = NaN       % previous CPF lambda for tangent orientation
        psse_reorient_zp = []          % previous CPF tangent for tangent orientation
        psse_last_control_lambda = NaN % last CPF lambda where cycle memory was reset
    end

    methods
        function dm = data_model_build(obj, d, dmc, mpopt, mpx)
            % Build CPF data models, including single-source control rebuilds.

            if iscell(d) && length(d) == 2
                obj.psse_target_source = d{2};
                dm = data_model_build@mp.task_cpf(obj, d, dmc, mpopt, mpx);
                if isfield(dm.userdata, 'target') && ...
                        isfield(dm.userdata.target, 'source')
                    obj.psse_target_source = dm.userdata.target.source;
                end
            else
                dm = data_model_build@mp.task_pf(obj, d, dmc, mpopt, mpx);
                dmt = obj.psse_target_source_for_rebuild(d);
                dmt = mp.psse_sync_cpf_target(d, dmt);
                obj.psse_target_source = dmt;
                dm.userdata.target = data_model_build@mp.task_pf( ...
                    obj, dmt, dmc, mpopt, mpx);
            end
        end

        function opt = math_model_opt(obj, mm, nm, dm, mpopt)
            % Add the PSS/E CPF control callback to the PNE solve options.

            opt = math_model_opt@mp.task_cpf(obj, mm, nm, dm, mpopt);
            if ~obj.dc
                opt.callbacks{end+1} = { ...
                    @(k, nx, cx, px, s, opt)obj.callback_psse( ...
                        k, nx, cx, px, s, opt, mm, nm, dm, mpopt), ...
                    35 };
            end
        end

        function [mm, nm, dm] = next_mm(obj, mm, nm, dm, mpopt, mpx)
            % Resume CPF after a PSS/E control active-set update.

            if isfield(mm.soln.output, 'warmstart') && ...
                    ~isempty(obj.psse_pending_source)
                ws = mm.soln.output.warmstart;
                ad = mm.aux_data;

                %% PSS/E active-set re-corrections are internal control
                %% passes at the same loading point, not new continuation
                %% steps. Keep the public CPF step counter from consuming
                %% cpf.max_it while taps/shunts settle at fixed lambda.
                ws.cont_steps = max(ws.cont_steps - 1, 0);

                %% save parameter lambda and solved voltages
                %% for current & prev step
                ws.clam = ws.x(end);
                ws.plam = ws.xp(end);
                [ws.cV, ~] = mm.convert_x_m2n_cpf(ws.x, nm);
                [ws.pV, ~] = mm.convert_x_m2n_cpf(ws.xp, nm);

                %% expand tangent z to all nodes + lambda, for cur & prev step
                [ws.z, ws.zp] = mm.expand_z_warmstart(nm, ad, ws.z, ws.zp);

                %% Preserve the continuation orientation across the PSS/E
                %% active-set rebuild, then re-correct at fixed lambda. The
                %% tangent is restored in callback_psse() after the
                %% fixed-lambda point has converged on the new equations.
                obj.psse_reorient_after_warmstart = true;
                obj.psse_reorient_pV = ws.pV;
                obj.psse_reorient_plam = ws.plam;
                obj.psse_reorient_zp = ws.zp;
                ws.plam = ws.clam;
                ws.pV = ws.cV;
                ws.zp = ws.z;
                ws.parm = @pne_pfcn_natural;

                %% set warmstart for next math model
                obj.warmstart = ws;

                %% rebuild CPF base/target with the new PSS/E active set
                dm = obj.data_model_build( ...
                    obj.psse_pending_source, obj.dmc, mpopt, mpx);
                nm = obj.network_model_build(dm, mpopt, mpx);
                obj.dm = dm;
                obj.nm = nm;

                %% reset var_map
                obj.nm.userdata.var_map = {};

                %% create new math model
                mm = obj.math_model_build(nm, dm, mpopt, mpx);
            else
                [mm, nm, dm] = next_mm@mp.task_cpf( ...
                    obj, mm, nm, dm, mpopt, mpx);
            end
        end

        function dm = next_dm(obj, mm, nm, dm, mpopt, mpx)
            % Handle CPF failure rollback; PSS/E controls run in callback_psse().

            dm0 = dm;
            dm = next_dm@mp.task(obj, mm, nm, dm, mpopt, mpx);
            if ~isempty(dm) || obj.dc
                return;
            end
            if ~obj.success && ~isempty(obj.psse_pending_control) && ...
                    ~obj.psse_rollback_done && ...
                    ~isempty(obj.psse_last_success_source)
                obj.psse_failed_control = obj.psse_pending_control;
                src = obj.psse_last_success_source;
                if ~isfield(src, 'psse') || isempty(src.psse)
                    src.psse = struct();
                end
                src.psse.control_failure = struct( ...
                    'control', obj.psse_failed_control, ...
                    'stage', 'post_control_cpf', ...
                    'success', 0);
                obj.psse_rollback_done = true;
                obj.psse_stop_after_rollback = true;
                obj.psse_failed_after_rollback = true;
                obj.psse_pending_control = '';
                obj.psse_pending_source = [];
                obj.psse_pending_lambda = NaN;
                dm = obj.data_model_build(src, obj.dmc, mpopt, mpx);
                return;
            end
            if ~obj.success
                if ~obj.psse_rollback_done && ...
                        ~isempty(obj.psse_last_success_source)
                    obj.psse_rollback_done = true;
                    obj.psse_stop_after_rollback = true;
                    dm = obj.data_model_build( ...
                        obj.psse_last_success_source, obj.dmc, mpopt, mpx);
                end
                return;
            end
            dm0 = obj.sync_source_solution(dm0, nm);
            obj.psse_last_success_source = dm0.source;
            obj.psse_pending_control = '';
            obj.psse_pending_source = [];
            obj.psse_pending_lambda = NaN;
            if obj.psse_stop_after_rollback
                obj.psse_stop_after_rollback = false;
                if obj.psse_failed_after_rollback
                    obj.success = false;
                    obj.message = sprintf(['PSS/E %s control rebuild ' ...
                        'failed after rollback'], obj.psse_failed_control);
                end
                return;
            end
        end

        function [nx, cx, s] = callback_psse(obj, k, nx, cx, ~, s, ...
                ~, mm, nm, dm, mpopt)
            % Evaluate PSS/E controls at accepted CPF points.

            if k <= 0 || obj.dc || s.done || s.rollback || ...
                    ~isempty(s.warmstart)
                return;
            end

            psse_warmstart = obj.psse_reorient_after_warmstart;
            if psse_warmstart
                nx = obj.reorient_after_psse_warmstart(nx, mm, nm);
            end

            [dm0, nm0] = obj.cpf_control_context(nx, mm, nm, dm, mpopt);
            obj.psse_last_success_source = dm0.source;
            obj.psse_pending_control = '';
            obj.psse_pending_source = [];
            obj.psse_pending_lambda = NaN;
            if ~psse_warmstart
                obj.reset_control_cycle_window(nx.x(end));
            end

            mpx = obj.psse_mpx_from_options(mpopt);
            order = obj.control_order(mpopt, dm0.source);
            for kk = 1:length(order)
                dm_next = obj.apply_control( ...
                    order{kk}, mm, nm0, dm0, mpopt, mpx);
                if ~isempty(dm_next)
                    obj.psse_pending_control = order{kk};
                    obj.psse_pending_source = dm_next.source;
                    obj.psse_pending_lambda = nx.x(end);
                    [ev_idx, detail] = psse_control_change_summary( ...
                        order{kk}, dm0.source, dm_next.source);
                    msg = sprintf(['PSS/E %s control update at ' ...
                        'lambda = %.8g; CPF will re-correct at the ' ...
                        'same loading point.'], order{kk}, nx.x(end));
                    if ~isempty(detail)
                        msg = sprintf('%s %s', msg, detail);
                    end
                    nx = obj.append_psse_event( ...
                        nx, k, order{kk}, msg, ev_idx);
                    s.done = 1;
                    s.done_msg = msg;
                    s.warmstart = struct();
                    return;
                end
            end
        end

        function order = control_order(~, mpopt, mpc)
            % Return the configured PSS/E control order.
            %
            % Keep this in sync with mp.task_pf_psse.control_order(). CPF
            % cannot inherit the PF task, but the family order must remain
            % identical until a shared PSS/E control coordinator exists.

            default_order = {'pqbrak', 'xfmr', 'genq', 'twodc', ...
                'swshunt', 'facts'};
            order = default_order;
            if nargin >= 3 && isfield(mpc, 'psse') && ...
                    isfield(mpc.psse, 'twodc') && ...
                    ((isfield(mpc.psse.twodc, 'pq_model_deferred') && ...
                    mpc.psse.twodc.pq_model_deferred) || ...
                    (isfield(mpc.psse.twodc, 'prepare_deferred') && ...
                    mpc.psse.twodc.prepare_deferred))
                order = {'xfmr', 'twodc', 'genq', 'swshunt', ...
                    'facts', 'pqbrak'};
            end
            if ~isfield(mpopt, 'exp') || ...
                    ~isfield(mpopt.exp, 'psse_control_order') || ...
                    isempty(mpopt.exp.psse_control_order)
                return;
            end

            order = parse_control_order(mpopt.exp.psse_control_order);
            if length(order) ~= length(default_order) || ...
                    ~all(ismember(default_order, order)) || ...
                    length(unique(order)) ~= length(order)
                error(['mp.task_cpf_psse.invalid_control_order: ' ...
                    'mpopt.exp.psse_control_order must contain each ' ...
                    'PSS/E control exactly once: %s'], ...
                    strjoin(default_order, ', '));
            end
        end

        function dm = apply_control(obj, name, mm, nm, dm0, mpopt, mpx)
            % Run one PSS/E control family.
            %
            % This mirrors mp.task_pf_psse.apply_control(), but stores the
            % pending source so callback_psse() can re-correct the same CPF
            % loading point after any PSS/E active-set change.

            switch name
                case 'pqbrak'
                    dm = [];
                    if ~isempty(which('mp.psse_pqbrak_control'))
                        [dm, obj.psse_pqbrak] = mp.psse_pqbrak_control( ...
                            obj, mm, nm, dm0, mpopt, mpx, obj.psse_pqbrak);
                    end
                case 'xfmr'
                    [dm, obj.psse_xfmr] = mp.psse_xfmr_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, obj.psse_xfmr);
                case 'genq'
                    dm = [];
                    if ~isempty(which('mp.psse_genq_control'))
                        [dm, obj.psse_genq] = mp.psse_genq_control( ...
                            obj, mm, nm, dm0, mpopt, mpx, obj.psse_genq);
                    end
                case 'twodc'
                    [dm, obj.psse_twodc] = mp.psse_twodc_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, obj.psse_twodc);
                case 'swshunt'
                    [dm, obj.psse_swshunt] = mp.psse_swshunt_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, obj.psse_swshunt);
                case 'facts'
                    [dm, obj.psse_facts] = mp.psse_facts_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, obj.psse_facts);
                otherwise
                    error(['mp.task_cpf_psse.unknown_control: ' ...
                        'Unknown PSS/E control family ''%s''.'], name);
            end
            if ~isempty(dm)
                obj.psse_pending_control = name;
                obj.psse_pending_source = dm.source;
            end
        end

        function [dm0, nm0] = cpf_control_context(obj, nx, mm, nm, dm, mpopt)
            % Build solved CPF context used by PSS/E control helpers.

            dm0 = dm.copy();
            soln0 = mm.soln;
            cleanup = onCleanup(@()restore_mm_soln(mm, soln0));
            mm.soln.x = nx.x;
            nm0 = mm.network_model_x_soln(nm);
            nm0 = obj.network_model_update(mm, nm0);
            dm0 = mm.data_model_update(nm0, dm0, mpopt);
            dm0 = obj.sync_source_solution(dm0, nm0);
        end

        function nx = reorient_after_psse_warmstart(obj, nx, mm, nm)
            % Restore the CPF tangent after a fixed-lambda PSS/E re-correction.

            obj.psse_reorient_after_warmstart = false;
            if isempty(obj.psse_reorient_pV) || isempty(obj.psse_reorient_zp)
                return;
            end

            ad = mm.aux_data;
            pV = obj.psse_reorient_pV;
            plam = obj.psse_reorient_plam;
            zp_full = obj.psse_reorient_zp;
            obj.psse_reorient_pV = [];
            obj.psse_reorient_plam = NaN;
            obj.psse_reorient_zp = [];

            xp = [angle(pV([ad.pv; ad.pq])); abs(pV(ad.pq)); plam];
            i = [ad.pv; ad.pq; nm.nv/2 + ad.pq; nm.nv+1];
            zp = zp_full(i);
            parm = nx.default_parm;
            if isempty(parm)
                parm = nx.parm;
            end
            nx.z = psse_pne_tangent(mm, nx.x, xp, zp, parm, 1);
            nx.parm = parm;
        end

        function nx = append_psse_event(~, nx, k, name, msg, idx)
            % Add a trace event for a PSS/E CPF control warmstart.

            if nargin < 6
                idx = [];
            end
            e = struct( ...
                'k', k, ...
                'name', sprintf('PSSE_%s', upper(name)), ...
                'idx', idx, ...
                'msg', msg );
            if isempty(nx.events)
                nx.events = e;
            else
                nx.events(end+1) = e;
            end
        end

        function mpx = psse_mpx_from_options(~, mpopt)
            % Return extension list stored in options for CPF rebuilds.

            if isfield(mpopt, 'exp') && isfield(mpopt.exp, 'mpx') && ...
                    ~isempty(mpopt.exp.mpx)
                if iscell(mpopt.exp.mpx)
                    mpx = mpopt.exp.mpx;
                else
                    mpx = { mpopt.exp.mpx };
                end
            else
                mpx = {};
            end
        end

        function dm = sync_source_solution(obj, dm, nm)
            % Use the current solved voltage as the source for control checks.

            [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
            if obj.dc || isempty(dm) || ~isfield(dm.source, 'bus') || ...
                    isempty(dm.source.bus)
                return;
            end
            if ~isempty(nm) && isobject(nm) && isprop(nm, 'soln') && ...
                    isfield(nm.soln, 'v') && ...
                    length(nm.soln.v) == size(dm.source.bus, 1)
                v = nm.soln.v;
                dm.source.bus(:, VM) = abs(v);
                dm.source.bus(:, VA) = angle(v) * 180 / pi;
            end
        end

        function nm = network_model_x_soln(obj, mm, nm)
            % Update CPF network solution and guard multi-reference systems.

            nm = network_model_x_soln@mp.task(obj, mm, nm);
            nm.userdata.target = mm.network_model_x_soln(nm.userdata.target);

            if ~obj.dc && obj.i_nm > 1 && isscalar(obj.ref) && ...
                    isscalar(obj.ref0) && obj.ref ~= obj.ref0
                vm = abs(nm.soln.v);
                va = angle(nm.soln.v);
                va = va - va(obj.ref0) + obj.va_ref0;
                nm.soln.v = vm .* exp(1j * va);
            end
        end

        function dmt = psse_target_source_for_rebuild(obj, d)
            % Return the current CPF target source for a single-source rebuild.

            dmt = d;
            if ~isempty(obj.psse_target_source)
                dmt = obj.psse_target_source;
            elseif ~isempty(obj.dm) && isfield(obj.dm.userdata, 'target') && ...
                    ~isempty(obj.dm.userdata.target) && ...
                    isfield(obj.dm.userdata.target, 'source')
                dmt = obj.dm.userdata.target.source;
            end
        end

        function reset_control_cycle_window(obj, lam)
            % Clear per-loading-point PSS/E control cycle memory.
            %
            % PF iterations see one solve per active-set update; CPF can
            % revisit the same loading point through warmstarts. Reset only
            % when lambda changes so discrete tap/shunt cycle memory remains
            % local to a single continuation point.

            tol = 1e-10;
            if ~isnan(obj.psse_last_control_lambda) && ...
                    abs(lam - obj.psse_last_control_lambda) <= tol
                return;
            end
            obj.psse_last_control_lambda = lam;
            obj.psse_xfmr = psse_reset_cycle_state(obj.psse_xfmr);
            obj.psse_swshunt = psse_reset_cycle_state(obj.psse_swshunt);
        end
    end     %% methods
end         %% classdef

function order = parse_control_order(raw)
% Parse a cell/string/char PSS/E control order into lowercase names.

if ischar(raw)
    txt = regexprep(raw, '\s*->\s*', ',');
    order = regexp(txt, '[,\s]+', 'split');
elseif isstring(raw)
    if isscalar(raw)
        order = parse_control_order(char(raw));
    else
        order = cellstr(raw(:))';
    end
elseif iscell(raw)
    order = raw(:)';
else
    error(['mp.task_cpf_psse.invalid_control_order_type: ' ...
        'mpopt.exp.psse_control_order must be a cell array, string, or char']);
end

keep = ~cellfun(@isempty, order);
order = lower(strtrim(order(keep)));
end

function restore_mm_soln(mm, soln)
% Restore a math model solution after temporary CPF control evaluation.

mm.soln = soln;
end

function state = psse_reset_cycle_state(state)
% Reset cycle detection fields that should be local to one loading point.

if isempty(state) || ~isstruct(state) || ...
        ~isfield(state, 'initialized') || ~state.initialized
    return;
end
if isfield(state, 'visited_signatures')
    state.visited_signatures = {};
end
if isfield(state, 'iterations')
    state.iterations = 0;
end
if isfield(state, 'max_iter_reached')
    state.max_iter_reached = 0;
end
if isfield(state, 'best_score')
    state.best_score = Inf;
end
if isfield(state, 'best_tap') && isfield(state, 'current_tap')
    state.best_tap = state.current_tap;
end
if isfield(state, 'best_raw') && isfield(state, 'current_raw')
    state.best_raw = state.current_raw;
end
if isfield(state, 'best_b') && isfield(state, 'current_b')
    state.best_b = state.current_b;
end
if isfield(state, 'best_violations')
    state.best_violations = 0;
end
if isfield(state, 'best_violation_sum')
    state.best_violation_sum = 0;
end
if isfield(state, 'cycle_resolved')
    state.cycle_resolved = 0;
end
if isfield(state, 'cycle_probe_attempted')
    state.cycle_probe_attempted = 0;
end
if isfield(state, 'cycle_probe_pending')
    state.cycle_probe_pending = 0;
end
end

function [idx, detail] = psse_control_change_summary(name, before, after)
% Summarize the source-table change that triggered a PSS/E CPF warmstart.

idx = [];
detail = '';
switch lower(name)
    case 'xfmr'
        [idx, detail] = psse_xfmr_change_summary(before, after);
    case 'swshunt'
        [idx, detail] = psse_swshunt_change_summary(before, after);
end
end

function [idx, detail] = psse_xfmr_change_summary(before, after)
% Summarize transformer TAP moves by MATPOWER branch row.

[~, ~, ~, ~, ~, ~, ~, ~, TAP] = idx_brch;
idx = [];
detail = '';
if ~isstruct(before) || ~isstruct(after) || ...
        ~isfield(before, 'branch') || ~isfield(after, 'branch') || ...
        isempty(before.branch) || isempty(after.branch) || ...
        size(before.branch, 2) < TAP || size(after.branch, 2) < TAP
    return;
end

n = min(size(before.branch, 1), size(after.branch, 1));
tap0 = before.branch(1:n, TAP);
tap1 = after.branch(1:n, TAP);
tap0(tap0 == 0) = 1;
tap1(tap1 == 0) = 1;

idx = find(abs(tap1 - tap0) > 1e-10);
detail = psse_change_list('Changed TAP', 'branch', ...
    idx, tap0(idx), tap1(idx));
end

function [idx, detail] = psse_swshunt_change_summary(before, after)
% Summarize switched-shunt BINIT moves by external bus number.

idx = [];
detail = '';
if ~isstruct(before) || ~isstruct(after) || ...
        ~isfield(before, 'psse') || ~isfield(after, 'psse') || ...
        ~isfield(before.psse, 'swshunt') || ...
        ~isfield(after.psse, 'swshunt') || ...
        ~isfield(before.psse.swshunt, 'num') || ...
        ~isfield(after.psse.swshunt, 'num') || ...
        isempty(before.psse.swshunt.num) || ...
        isempty(after.psse.swshunt.num)
    return;
end

num0 = before.psse.swshunt.num;
num1 = after.psse.swshunt.num;
n = min(size(num0, 1), size(num1, 1));
binit0 = psse_swshunt_col(before.psse.swshunt, 'BINIT', 9);
binit1 = psse_swshunt_col(after.psse.swshunt, 'BINIT', 9);
i_col = psse_swshunt_col(after.psse.swshunt, 'I', 1);
if n == 0 || size(num0, 2) < binit0 || size(num1, 2) < binit1 || ...
        size(num1, 2) < i_col
    return;
end

b0 = num0(1:n, binit0);
b1 = num1(1:n, binit1);
changed = abs(b1 - b0) > 1e-9 | xor(isnan(b0), isnan(b1));
rows = find(changed);
idx = num1(rows, i_col).';
detail = psse_change_list('Changed BINIT', 'bus', ...
    idx, b0(rows), b1(rows));
end

function col = psse_swshunt_col(sw, name, default_col)
% Locate a switched-shunt column from metadata with a conservative fallback.

col = default_col;
if strcmpi(name, 'BINIT') && isfield(sw, 'binit_col') && ...
        ~isempty(sw.binit_col) && sw.binit_col > 0
    col = sw.binit_col;
    return;
end
if ~isfield(sw, 'colnames') || isempty(sw.colnames)
    return;
end

cols = sw.colnames;
if isstring(cols)
    cols = cellstr(cols);
elseif ischar(cols)
    cols = cellstr(cols);
end
k = find(strcmpi(strtrim(cols), name), 1);
if ~isempty(k)
    col = k;
end
end

function detail = psse_change_list(prefix, label, idx, oldval, newval)
% Format a short control-change list for CPF event messages.

detail = '';
if isempty(idx)
    return;
end

max_items = 6;
n = length(idx);
m = min(n, max_items);
items = cell(1, m);
for k = 1:m
    items{k} = sprintf('%s %.12g %.8g->%.8g', ...
        label, idx(k), oldval(k), newval(k));
end
if n > m
    tail = sprintf(', +%d more', n - m);
else
    tail = '';
end
detail = sprintf('%s: %s%s.', prefix, strjoin(items, ', '), tail);
end

function z = psse_pne_tangent(mm, x, xp, zp, parm, direction)
% Find normalized tangent vector for a PSS/E CPF warmstart reorientation.

[~, df] = psse_nleq_fcn(mm, x);
[~, dp] = parm(x, xp, 0, zp);
rhs = [zeros(size(df, 1), 1); direction];
z = [df; dp] \ rhs;
z = z / norm(z);
end

function [f, J] = psse_nleq_fcn(mm, x)
% Evaluate nonlinear/linear equations in the same form used by pnes_master().

flin = []; Jlin = [];
fqcn = []; Jqcn = [];
fnln = []; Jnln = [];
if mm.lin.get_N()
    [flin, ~, Jlin] = mm.lin.eval(mm.var, x);
end
if nargout > 1
    if mm.qcn.get_N()
        [fqcn, Jqcn] = mm.qcn.eval(mm.var, x);
    end
    if mm.nle.get_N()
        [fnln, Jnln] = mm.nle.eval(mm.var, x);
    end
    J = [Jnln; Jqcn; Jlin];
else
    if mm.qcn.get_N()
        fqcn = mm.qcn.eval(mm.var, x);
    end
    if mm.nle.get_N()
        fnln = mm.nle.eval(mm.var, x);
    end
end
f = [fnln; fqcn; flin];
end
