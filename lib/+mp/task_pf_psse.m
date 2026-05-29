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
        psse_last_success_source = []  % last converged source MPC
        psse_rollback_done = false     % true after one rollback attempt
        psse_stop_after_rollback = false   % stop controls after rollback solve
        psse_pending_control = ''      % control family awaiting PF acceptance
        psse_pending_source = []       % source MPC for pending control family
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
            end
        end

        function order = control_order(~, mpopt, mpc)
            % Return the configured PSS/E control order.

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
                error(['mp.task_pf_psse.invalid_control_order: ' ...
                    'mpopt.exp.psse_control_order must contain each ' ...
                    'PSS/E control exactly once: %s'], ...
                    strjoin(default_order, ', '));
            end
        end

        function dm = apply_control(obj, name, mm, nm, dm0, mpopt, mpx)
            % Run one PSS/E control family.

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
                    error(['mp.task_pf_psse.unknown_control: ' ...
                        'Unknown PSS/E control family ''%s''.'], name);
            end
            if ~isempty(dm)
                obj.psse_pending_control = name;
                obj.psse_pending_source = dm.source;
            end
        end

        function dm = sync_source_solution(obj, dm, nm)
            % Use the previous solved voltage as the initial point for rebuilds.

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
