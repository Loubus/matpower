classdef task_pf_psse < mp.task_pf_legacy
% mp.task_pf_psse - Legacy power flow task with PSS/E controls.
%
% Adds PSS/E generator reactive limit/remote voltage regulation,
% low-voltage constant MVA load behavior, transformer tap, two-terminal DC,
% switched shunt, and FACTS STATCON control to the legacy MP-Core power
% flow task. The controls are applied in next_dm(), so each adjustment
% triggers a formal data model iteration and a complete rebuild of the
% network and mathematical models.
%
% mp.task_pf_psse Properties:
%   * psse_genq - generator Q limit/remote regulation state and diagnostics
%   * psse_pqbrak - low-voltage constant MVA load state and diagnostics
%   * psse_xfmr - transformer tap control state and diagnostics
%   * psse_twodc - two-terminal DC control state and diagnostics
%   * psse_facts - FACTS device control state and diagnostics
%   * psse_swshunt - switched shunt control state and diagnostics
%
% mp.task_pf_psse Methods:
%   * next_dm - coordinate PSS/E low-voltage load, transformer, generator Q,
%       two-terminal DC, switched shunt and FACTS control
%   * control_order - return the PSS/E control order requested by mpopt
%   * apply_control - run one PSS/E control family
%   * network_model_build_post - initialize reference-bus tracking for data
%       model iterations
%   * network_model_x_soln - correct voltage angles when the reference bus
%       changes between data model iterations
%
% See also mp.task_pf_legacy, mp.xt_psse, runpf_psse.

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
        psse_gen_capability = []   % generator capability state/report
        psse_last_success_source = []  % last converged source MPC
        psse_rollback_done = false     % true after one rollback attempt
        psse_stop_after_rollback = false   % stop controls after rollback solve
        psse_pending_control = ''      % control family awaiting PF acceptance
        psse_pending_source = []       % source MPC for pending control family
        psse_pending_xfmr_state = []   % accepted xfmr state before pending move
        psse_failed_control = ''       % control family whose rebuild failed
        psse_failed_after_rollback = false  % true after a failed control rollback
    end

    methods
        function dm = next_dm(obj, mm, nm, dm, mpopt, mpx)
            % Coordinate PSS/E load, transformer, generator Q, DC, shunt and FACTS control.

            dm0 = dm;
            dm = next_dm@mp.task_pf(obj, mm, nm, dm, mpopt, mpx);
            if ~isempty(dm) || obj.dc
                return;
            end
            if ~obj.success && ~isempty(obj.psse_pending_control) && ...
                    ~obj.psse_rollback_done && ...
                    ~isempty(obj.psse_last_success_source)
                obj.psse_failed_control = obj.psse_pending_control;
                src = obj.psse_last_success_source;
                if strcmp(obj.psse_pending_control, 'xfmr')
                    [src, rejected] = obj.reject_pending_xfmr_rebuild(src, mpopt);
                    if rejected
                        obj.psse_pending_control = '';
                        obj.psse_pending_source = [];
                        obj.psse_pending_xfmr_state = [];
                        dm = obj.data_model_build(src, obj.dmc, mpopt, mpx);
                        return;
                    end
                end
                if ~isfield(src, 'psse') || isempty(src.psse)
                    src.psse = struct();
                end
                src.psse.control_failure = struct( ...
                    'control', obj.psse_failed_control, ...
                    'stage', 'post_control_power_flow', ...
                    'success', 0);
                obj.psse_rollback_done = true;
                obj.psse_stop_after_rollback = true;
                obj.psse_failed_after_rollback = true;
                obj.psse_pending_control = '';
                obj.psse_pending_source = [];
                obj.psse_pending_xfmr_state = [];
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
            obj.psse_pending_xfmr_state = [];
            if obj.psse_stop_after_rollback
                obj.psse_stop_after_rollback = false;
                if obj.psse_failed_after_rollback
                    obj.success = false;
                    obj.message = sprintf(['PSS/E %s control rebuild ' ...
                        'failed after rollback'], obj.psse_failed_control);
                end
                return;
            end

            order = obj.control_order(mpopt, dm0.source);
            for k = 1:length(order)
                dm = obj.apply_control(order{k}, mm, nm, dm0, mpopt, mpx);
                if ~isempty(dm)
                    return;
                end
                if obj.control_failed(order{k})
                    obj.success = false;
                    obj.message = sprintf(['PSS/E %s control failed to ' ...
                        'settle'], order{k});
                    obj.psse_failed_control = order{k};
                    if isfield(dm0.source, 'psse')
                        dm0.source.psse.control_failure = ...
                            obj.control_failure_report(order{k});
                    end
                    obj.psse_last_success_source = dm0.source;
                    return;
                end
            end
        end

        function order = control_order(~, mpopt, mpc)
            % Return the configured PSS/E control order.

            default_order = {'pqbrak', 'xfmr', 'genq', 'twodc', ...
                'swshunt', 'facts'};
            order = default_order;
            if psse_gen_capability_requested(mpopt)
                order = [order {'gen_capability'}];
            end
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
            if psse_gen_capability_requested(mpopt) && ...
                    ~any(strcmp(order, 'gen_capability'))
                order = [order {'gen_capability'}];
            end
            valid_order = default_order;
            if psse_gen_capability_requested(mpopt)
                valid_order = [valid_order {'gen_capability'}];
            end
            if length(order) ~= length(valid_order) || ...
                    ~all(ismember(valid_order, order)) || ...
                    length(unique(order)) ~= length(order)
                error(['mp.task_pf_psse.invalid_control_order: ' ...
                    'mpopt.exp.psse_control_order must contain each ' ...
                    'enabled PSS/E control exactly once: %s'], ...
                    strjoin(valid_order, ', '));
            end
        end

        function dm = apply_control(obj, name, mm, nm, dm0, mpopt, mpx)
            % Run one PSS/E control family.

            accepted_xfmr_state = [];
            switch name
                case 'pqbrak'
                    dm = [];
                    if ~isempty(which('mp.psse_pqbrak_control'))
                        [dm, obj.psse_pqbrak] = mp.psse_pqbrak_control( ...
                            obj, mm, nm, dm0, mpopt, mpx, obj.psse_pqbrak);
                    end
                case 'xfmr'
                    accepted_xfmr_state = obj.psse_xfmr;
                    if isempty(accepted_xfmr_state) && ...
                            isfield(dm0.source, 'psse') && ...
                            isfield(dm0.source.psse, 'xfmr')
                        accepted_xfmr_state = mp.psse_xfmr_states(dm0.source);
                    end
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
                case 'gen_capability'
                    [dm, obj.psse_gen_capability] = ...
                        mp.psse_gen_capability_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, ...
                        obj.psse_gen_capability);
                otherwise
                    error(['mp.task_pf_psse.unknown_control: ' ...
                        'Unknown PSS/E control family ''%s''.'], name);
            end
            if ~isempty(dm)
                obj.psse_pending_control = name;
                obj.psse_pending_source = dm.source;
                if strcmp(name, 'xfmr')
                    obj.psse_pending_xfmr_state = accepted_xfmr_state;
                else
                    obj.psse_pending_xfmr_state = [];
                end
            end
        end

        function TorF = control_failed(obj, name)
            % Return true when a PSS/E control family exhausted unsuccessfully.

            TorF = false;
            state = obj.control_state(name);
            if isempty(state) || ~isstruct(state)
                return;
            end
            if isfield(state, 'control_failed') && ...
                    ~isempty(state.control_failed) && ...
                    any(state.control_failed(:))
                TorF = true;
                return;
            end
            if ~isfield(state, 'report') || isempty(state.report)
                return;
            end
            report = state.report;
            TorF = isfield(report, 'control_failed') && ...
                ~isempty(report.control_failed) && any(report.control_failed(:));
        end

        function failure = control_failure_report(obj, name)
            % Build a compact, machine-readable control failure marker.

            state = obj.control_state(name);
            reason = '';
            max_iter_reached = [];
            last_violations = [];
            if ~isempty(state) && isstruct(state)
                if isfield(state, 'failure_reason')
                    reason = state.failure_reason;
                end
                if isfield(state, 'max_iter_reached')
                    max_iter_reached = state.max_iter_reached;
                end
                if isfield(state, 'last_violations')
                    last_violations = state.last_violations;
                end
            end
            if ~isempty(state) && isstruct(state) && ...
                    isfield(state, 'report') && ~isempty(state.report)
                report = state.report;
                if isfield(report, 'failure_reason')
                    reason = report.failure_reason;
                end
                if isfield(report, 'max_iter_reached')
                    max_iter_reached = report.max_iter_reached;
                end
                if isfield(report, 'last_violations')
                    last_violations = report.last_violations;
                end
            end
            failure = struct( ...
                'control', name, ...
                'stage', 'control_settlement', ...
                'success', 0, ...
                'reason', reason, ...
                'max_iter_reached', max_iter_reached, ...
                'last_violations', last_violations);
        end

        function state = control_state(obj, name)
            % Fetch the stored state/report for a PSS/E control family.

            switch name
                case 'pqbrak'
                    state = obj.psse_pqbrak;
                case 'xfmr'
                    state = obj.psse_xfmr;
                case 'genq'
                    state = obj.psse_genq;
                case 'twodc'
                    state = obj.psse_twodc;
                case 'swshunt'
                    state = obj.psse_swshunt;
                case 'facts'
                    state = obj.psse_facts;
                case 'gen_capability'
                    state = obj.psse_gen_capability;
                otherwise
                    state = [];
            end
        end

        function dm = sync_source_solution(obj, dm, nm)
            % Use the previous solved voltage as the initial point for rebuilds.

            [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
            [~, PG, QG] = idx_gen;
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
            if isfield(dm.source, 'gen') && ~isempty(dm.source.gen) && ...
                    isfield(dm.elements, 'gen') && ...
                    isprop(dm.elements.gen, 'tab')
                tab = dm.elements.gen.tab;
                if all(ismember({'pg', 'qg'}, tab.Properties.VariableNames))
                    n = min(size(dm.source.gen, 1), height(tab));
                    pg = tab.pg(1:n);
                    qg = tab.qg(1:n);
                    if isfield(dm.source, 'baseMVA') && ...
                            dm.source.baseMVA > 0 && ...
                            max(abs(pg)) < 10 && ...
                            max(abs(dm.source.gen(1:n, PG))) > 10
                        pg = pg * dm.source.baseMVA;
                        qg = qg * dm.source.baseMVA;
                    end
                    dm.source.gen(1:n, PG) = pg;
                    dm.source.gen(1:n, QG) = qg;
                end
            end
        end

        function nm = network_model_build_post(obj, nm, dm, mpopt)
            % Initialize reference-bus tracking for data model iterations.

            nm = network_model_build_post@mp.task_pf(obj, nm, dm, mpopt);
            if ~obj.dc && nm.np ~= 0 && mpopt.pf.enforce_q_lims == 0
                [ref, ~, ~] = nm.node_types(obj, dm);
                if obj.i_nm == 1 || isempty(obj.ref0)
                    obj.iterations = 0;
                    obj.ref0 = ref;
                    obj.ref = ref;
                    obj.va_ref0 = nm.get_va(ref);
                else
                    obj.ref = ref;
                end
            end
        end

        function nm = network_model_x_soln(obj, mm, nm)
            % Correct voltage angles if a single reference bus changes.

            nm = network_model_x_soln@mp.task(obj, mm, nm);
            if ~obj.dc && obj.i_nm > 1 && isscalar(obj.ref) && ...
                    isscalar(obj.ref0) && obj.ref ~= obj.ref0
                vm = abs(nm.soln.v);
                va = angle(nm.soln.v);
                va = va - va(obj.ref0) + obj.va_ref0;
                nm.soln.v = vm .* exp(1j * va);
            end
        end

        function [src, rejected] = reject_pending_xfmr_rebuild(obj, src, mpopt)
            % Reject a transformer tap candidate whose rebuilt PF failed.

            rejected = false;
            candidate = obj.psse_xfmr;
            state = obj.psse_pending_xfmr_state;
            if isempty(state) || ~isstruct(state) || ...
                    isempty(candidate) || ~isstruct(candidate) || ...
                    ~isfield(src, 'psse') || ~isfield(src.psse, 'xfmr')
                return;
            end
            if ~isfield(candidate, 'current_tap') || ...
                    numel(candidate.current_tap) ~= state.n || ...
                    ~isfield(candidate, 'current_raw') || ...
                    numel(candidate.current_raw) ~= state.n
                return;
            end

            moved = abs(candidate.current_tap(:) - state.current_tap(:)) > 1e-9;
            moved = moved & state.controllable(:);
            if ~any(moved)
                return;
            end

            if ~isfield(state, 'locked_out') || isempty(state.locked_out)
                state.locked_out = false(state.n, 1);
            end
            state = mp.psse_xfmr_guard_candidate(src, state, candidate, ...
                mpopt);

            src = mp.psse_xfmr_update(src, state);
            obj.psse_xfmr = state;
            rejected = true;
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
    error(['mp.task_pf_psse.invalid_control_order_type: ' ...
        'mpopt.exp.psse_control_order must be a cell array, string, or char']);
end

keep = ~cellfun(@isempty, order);
order = lower(strtrim(order(keep)));
end

function TorF = psse_gen_capability_requested(mpopt)
% Return true when generator capability control is explicitly enabled.

TorF = false;
if ~isfield(mpopt, 'vsc_mtdc') || ...
        ~isfield(mpopt.vsc_mtdc, 'capability_gen_enforce') || ...
        isempty(mpopt.vsc_mtdc.capability_gen_enforce)
    return;
end
raw = mpopt.vsc_mtdc.capability_gen_enforce;
if islogical(raw) || isnumeric(raw)
    TorF = any(raw(:) ~= 0);
elseif ischar(raw) || isstring(raw)
    TorF = any(strcmpi(char(raw), {'1', 'true', 'on', 'yes'}));
end
end
