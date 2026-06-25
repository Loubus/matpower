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
        psse_gen_redispatch = []   % CPF generator redispatch state/report
        psse_gen_capability = []   % generator capability state/report
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
        psse_redispatch_base_source = []   % CPF segment base for redispatch
        psse_redispatch_lambda = NaN       % accepted lambda for redispatch
        psse_gen_pq_trace = []             % optional accepted-point P/Q trace
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
                pending_source = obj.rebase_pending_source_for_cpf();
                dm = obj.data_model_build(pending_source, obj.dmc, ...
                    mpopt, mpx);
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

            if k < 0
                obj.write_gen_pq_trace(mpopt);
                return;
            elseif k == 0
                obj.reset_gen_pq_trace(mpopt);
                return;
            end

            if obj.dc || s.rollback || ...
                    ~isempty(s.warmstart)
                return;
            end

            psse_warmstart = obj.psse_reorient_after_warmstart;
            if psse_warmstart
                nx = obj.reorient_after_psse_warmstart(nx, mm, nm);
                [nx, s] = obj.suppress_warmstart_nose_event(nx, s);
            end

            [dm0, nm0] = obj.cpf_control_context(nx, mm, nm, dm, mpopt);
            obj.record_gen_pq_trace(k, nx, mm, nm, dm0.source, mpopt, ...
                psse_warmstart);
            obj.psse_last_success_source = dm0.source;
            obj.psse_pending_control = '';
            obj.psse_pending_source = [];
            obj.psse_pending_lambda = NaN;
            if ~psse_warmstart
                obj.reset_control_cycle_window(nx.x(end));
            end

            mpx = obj.psse_mpx_from_options(mpopt);
            if s.done
                order = {};
                if psse_gen_redispatch_requested(mpopt, dm0.source)
                    order = [order {'gen_redispatch'}];
                end
                if psse_gen_capability_requested(mpopt)
                    order = [order {'gen_capability'}];
                end
            else
                order = obj.control_order(mpopt, dm0.source);
            end
            for kk = 1:length(order)
                dm_eval = dm0;
                if strcmp(order{kk}, 'gen_redispatch')
                    obj.psse_redispatch_base_source = dm0.source;
                    obj.psse_redispatch_lambda = nx.x(end);
                    dm_eval = dm0.copy();
                    dm_eval.source = obj.cpf_current_source_solution( ...
                        nx, mm, nm, dm_eval.source, mpopt);
                elseif strcmp(order{kk}, 'gen_capability')
                    dm_eval = dm0.copy();
                    dm_eval.source = obj.cpf_current_source_solution( ...
                        nx, mm, nm, dm_eval.source, mpopt);
                end
                dm_next = obj.apply_control( ...
                    order{kk}, mm, nm0, dm_eval, mpopt, mpx);
                if ~isempty(dm_next)
                    obj.psse_pending_control = order{kk};
                    obj.psse_pending_source = dm_next.source;
                    obj.psse_pending_lambda = nx.x(end);
                    [ev_idx, detail] = psse_control_change_summary( ...
                        order{kk}, dm_eval.source, dm_next.source);
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
            if psse_gen_redispatch_requested(mpopt, mpc)
                order = [{'gen_redispatch'} order];
            end
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
            if psse_gen_redispatch_requested(mpopt, mpc) && ...
                    ~any(strcmp(order, 'gen_redispatch'))
                order = [{'gen_redispatch'} order];
            end
            if psse_gen_capability_requested(mpopt) && ...
                    ~any(strcmp(order, 'gen_capability'))
                order = [order {'gen_capability'}];
            end
            valid_order = default_order;
            if psse_gen_redispatch_requested(mpopt, mpc)
                valid_order = [{'gen_redispatch'} valid_order];
            end
            if psse_gen_capability_requested(mpopt)
                valid_order = [valid_order {'gen_capability'}];
            end
            if length(order) ~= length(valid_order) || ...
                    ~all(ismember(valid_order, order)) || ...
                    length(unique(order)) ~= length(order)
                error(['mp.task_cpf_psse.invalid_control_order: ' ...
                    'mpopt.exp.psse_control_order must contain each ' ...
                    'enabled PSS/E control exactly once: %s'], ...
                    strjoin(valid_order, ', '));
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
                case 'gen_redispatch'
                    [dm, obj.psse_gen_redispatch] = ...
                        mp.psse_gen_redispatch_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, ...
                        obj.psse_gen_redispatch);
                case 'gen_capability'
                    [dm, obj.psse_gen_capability] = ...
                        mp.psse_gen_capability_control( ...
                        obj, mm, nm, dm0, mpopt, mpx, ...
                        obj.psse_gen_capability);
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

        function source = cpf_current_source_solution(obj, nx, mm, nm, ...
                source, mpopt)
            % Reconstruct CPF-implied generator P/Q for control policies.
            %
            % MP-Core CPF keeps generator injections in the continuation
            % transfer rather than as solved data-model table values. Use
            % the same PF solution update as legacy CPF result packaging so
            % capability controls see the P/Q that users see in results.gen.

            if obj.dc || isempty(source) || isempty(obj.psse_target_source) || ...
                    ~isfield(source, 'bus') || ~isfield(source, 'gen') || ...
                    ~isfield(source, 'branch')
                return;
            end
            target = obj.psse_target_source;
            if ~isfield(target, 'bus') || ~isfield(target, 'gen') || ...
                    ~isfield(target, 'branch') || ...
                    size(source.bus, 1) ~= size(target.bus, 1) || ...
                    size(source.gen, 1) ~= size(target.gen, 1)
                return;
            end

            [~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
            [~, PG] = idx_gen;
            lam = nx.x(end);
            try
                [V, ~] = mm.convert_x_m2n_cpf(nx.x, nm);
                current = source;
                current.bus(:, [PD QD]) = source.bus(:, [PD QD]) + ...
                    lam * (target.bus(:, [PD QD]) - source.bus(:, [PD QD]));
                current.gen(:, PG) = source.gen(:, PG) + ...
                    lam * (target.gen(:, PG) - source.gen(:, PG));
                [ref, pv, pq] = bustypes(current.bus, current.gen);
                [Ybus, Yf, Yt] = makeYbus(current.baseMVA, ...
                    current.bus, current.branch);
                [current.bus, current.gen, current.branch] = pfsoln( ...
                    current.baseMVA, current.bus, current.gen, ...
                    current.branch, Ybus, Yf, Yt, V, ref, pv, pq, mpopt);
                source.bus = current.bus;
                source.gen = current.gen;
                source.branch = current.branch;
            catch
                %% Fall back to data-model values if the reconstructed
                %% current case is unavailable for an unusual extension.
            end
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

        function [nx, s] = suppress_warmstart_nose_event(~, nx, s)
            % Ignore NOSE detections from the fixed-lambda correction step.

            if ~isfield(nx, 'step') || nx.step ~= 0 || ...
                    ~isfield(s, 'events') || isempty(s.events)
                return;
            end
            names = {s.events.name};
            zero = [s.events.zero] ~= 0;
            nose = strcmp(names, 'NOSE') & zero;
            if ~any(nose)
                return;
            end

            for kk = find(nose)
                eidx = s.events(kk).eidx;
                if eidx > 0 && isfield(nx, 'efv') && length(nx.efv) >= eidx
                    nx.efv{eidx}(:) = nx.z(end);
                end
            end
            s.events(nose) = [];
            if isempty(s.events)
                s.events = psse_no_event();
            end
            if isfield(s, 'done') && s.done && isfield(s, 'done_msg') && ...
                    contains(s.done_msg, 'Nose point eliminated')
                s.done = 0;
                s.done_msg = '';
            end
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

        function source = rebase_pending_source_for_cpf(obj)
            % Keep PSS/E active-set rebuilds on the original CPF loading scale.

            source = obj.psse_pending_source;
            if isempty(source) || isempty(obj.psse_target_source) || ...
                    isnan(obj.psse_pending_lambda) || ...
                    ~any(strcmp(obj.psse_pending_control, ...
                    {'gen_capability', 'gen_redispatch'}))
                return;
            end

            lam = obj.psse_pending_lambda;
            target = obj.psse_target_source;
            [~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
            if isfield(source, 'bus') && isfield(target, 'bus') && ...
                    size(source.bus, 1) == size(target.bus, 1) && ...
                    abs(1 - lam) > 1e-10
                source.bus(:, [PD QD]) = ...
                    (source.bus(:, [PD QD]) - ...
                    lam * target.bus(:, [PD QD])) / (1 - lam);
            end

            dci = idx_dcline;
            if isfield(source, 'dcline') && ~isempty(source.dcline) && ...
                    isfield(target, 'dcline') && ...
                    size(source.dcline, 1) == size(target.dcline, 1) && ...
                    size(source.dcline, 2) >= dci.PT && ...
                    size(target.dcline, 2) >= dci.PT && ...
                    abs(1 - lam) > 1e-10
                source.dcline(:, [dci.PF dci.PT]) = ...
                    (source.dcline(:, [dci.PF dci.PT]) - ...
                    lam * target.dcline(:, [dci.PF dci.PT])) / ...
                    (1 - lam);
            end

            [~, PG] = idx_gen;
            if strcmp(obj.psse_pending_control, 'gen_redispatch') && ...
                    isfield(source, 'gen') && isfield(target, 'gen') && ...
                    size(source.gen, 1) == size(target.gen, 1) && ...
                    size(source.gen, 2) >= PG && size(target.gen, 2) >= PG && ...
                    abs(1 - lam) > 1e-10
                source.gen(:, PG) = (source.gen(:, PG) - ...
                    lam * target.gen(:, PG)) / (1 - lam);
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

        function reset_gen_pq_trace(obj, mpopt)
            % Initialize optional generator P/Q trace capture.

            obj.psse_gen_pq_trace = [];
            trace_file = psse_gen_pq_trace_file(mpopt);
            if isempty(trace_file) || exist(trace_file, 'file') ~= 2
                return;
            end
            delete(trace_file);
        end

        function record_gen_pq_trace(obj, k, nx, mm, nm, source, mpopt, ...
                psse_warmstart)
            % Capture the solved generator P/Q point for this lambda.

            trace_file = psse_gen_pq_trace_file(mpopt);
            if isempty(trace_file) || obj.dc || isempty(source) || ...
                    ~isfield(source, 'gen') || isempty(source.gen)
                return;
            end

            source = obj.cpf_current_source_solution( ...
                nx, mm, nm, source, mpopt);
            [GEN_BUS, PG, QG, QMAX, QMIN, ~, ~, GEN_STATUS, ...
                PMAX, PMIN] = idx_gen;
            ng = size(source.gen, 1);
            gen_idx = (1:ng)';
            if isfield(source, 'order') && isfield(source.order, 'gen') && ...
                    isfield(source.order.gen, 'status') && ...
                    isfield(source.order.gen.status, 'on')
                on = source.order.gen.status.on(:);
                if numel(on) == ng
                    gen_idx = on;
                end
            end

            rec = struct( ...
                'k', k, ...
                'lambda', nx.x(end), ...
                'step', nx.step, ...
                'warmstart', logical(psse_warmstart), ...
                'gen_idx', gen_idx, ...
                'bus', source.gen(:, GEN_BUS), ...
                'PG', source.gen(:, PG), ...
                'QG', source.gen(:, QG), ...
                'QMAX', source.gen(:, QMAX), ...
                'QMIN', source.gen(:, QMIN), ...
                'PMAX', source.gen(:, PMAX), ...
                'PMIN', source.gen(:, PMIN), ...
                'GEN_STATUS', source.gen(:, GEN_STATUS) );
            if isempty(obj.psse_gen_pq_trace)
                obj.psse_gen_pq_trace = rec;
            else
                obj.psse_gen_pq_trace(end+1) = rec;
            end
        end

        function write_gen_pq_trace(obj, mpopt)
            % Save optional generator P/Q trace capture to disk.

            trace_file = psse_gen_pq_trace_file(mpopt);
            if isempty(trace_file)
                return;
            end
            [trace_dir, ~, ~] = fileparts(trace_file);
            if ~isempty(trace_dir) && exist(trace_dir, 'dir') ~= 7
                mkdir(trace_dir);
            end
            gen_pq_trace = obj.psse_gen_pq_trace;
            trace_info = struct( ...
                'created_by', 'mp.task_cpf_psse', ...
                'description', ['Solved generator P/Q values captured at ' ...
                    'accepted CPF callback points.'] );
            save(trace_file, 'gen_pq_trace', 'trace_info', '-v7.3');
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

function ev = psse_no_event()
% Return the MP-Opt-Model PNE no-event placeholder.

ev = struct( ...
    'eidx', 0, ...
    'zero', 0, ...
    'step_scale', 1, ...
    'log', 0, ...
    'name', '', ...
    'idx', 0, ...
    'msg', '');
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

function TorF = psse_gen_redispatch_requested(mpopt, mpc)
% Return true when dynamic CPF generator redispatch is explicitly enabled.

if nargin < 2
    mpc = [];
end
TorF = cpf_gen_redispatch_policy_state('enabled', mpc, mpc, mpopt);
end

function trace_file = psse_gen_pq_trace_file(mpopt)
% Return optional generator P/Q trace output file.

trace_file = '';
if ~isfield(mpopt, 'exp') || ...
        ~isfield(mpopt.exp, 'psse_gen_pq_trace_file') || ...
        isempty(mpopt.exp.psse_gen_pq_trace_file)
    return;
end
trace_file = mpopt.exp.psse_gen_pq_trace_file;
if isstring(trace_file)
    trace_file = char(trace_file);
end
if ~ischar(trace_file)
    trace_file = '';
end
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
    case 'gen_redispatch'
        [idx, detail] = psse_gen_redispatch_change_summary(before, after);
    case 'gen_capability'
        [idx, detail] = psse_gen_capability_change_summary(before, after);
end
end

function [idx, detail] = psse_gen_redispatch_change_summary(before, after)
% Summarize accepted-point generator redispatch by generator row.

[~, PG] = idx_gen;
idx = [];
detail = '';
if ~isstruct(before) || ~isstruct(after) || ...
        ~isfield(before, 'gen') || ~isfield(after, 'gen') || ...
        isempty(before.gen) || isempty(after.gen)
    return;
end
n = min(size(before.gen, 1), size(after.gen, 1));
if size(before.gen, 2) < PG || size(after.gen, 2) < PG
    return;
end
delta = abs(after.gen(1:n, PG) - before.gen(1:n, PG));
idx = find(delta > 1e-8).';
detail = psse_change_list('Changed redispatch PG', ...
    'gen', idx, before.gen(idx, PG), after.gen(idx, PG));
end

function [idx, detail] = psse_gen_capability_change_summary(before, after)
% Summarize generator capability freezes by generator row.

[~, PG, QG, QMAX, QMIN] = idx_gen;
idx = [];
detail = '';
if ~isstruct(before) || ~isstruct(after) || ...
        ~isfield(before, 'gen') || ~isfield(after, 'gen') || ...
        isempty(before.gen) || isempty(after.gen)
    return;
end
n = min(size(before.gen, 1), size(after.gen, 1));
cols = [PG QG QMAX QMIN];
if size(before.gen, 2) < max(cols) || size(after.gen, 2) < max(cols)
    return;
end
delta = abs(after.gen(1:n, cols) - before.gen(1:n, cols));
rows = find(any(delta > 1e-8, 2));
idx = rows.';
detail = psse_change_list('Changed generator capability point', ...
    'gen', idx, before.gen(rows, PG), after.gen(rows, PG));
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
