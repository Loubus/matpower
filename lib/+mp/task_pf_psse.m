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
%   * next_dm - coordinate PSS/E generator Q, low-voltage load, transformer,
%       two-terminal DC, switched shunt and FACTS control
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
    end

    methods
        function dm = next_dm(obj, mm, nm, dm, mpopt, mpx)
            % Coordinate PSS/E generator Q, load, transformer, DC, shunt and FACTS control.

            dm0 = dm;
            dm = next_dm@mp.task_pf(obj, mm, nm, dm, mpopt, mpx);
            if ~isempty(dm) || obj.dc || ~obj.success
                return;
            end

            if ~isempty(which('mp.psse_genq_control'))
                [dm, obj.psse_genq] = mp.psse_genq_control( ...
                    obj, mm, nm, dm0, mpopt, mpx, obj.psse_genq);
                if ~isempty(dm)
                    return;
                end
            end

            if ~isempty(which('mp.psse_pqbrak_control'))
                [dm, obj.psse_pqbrak] = mp.psse_pqbrak_control( ...
                    obj, mm, nm, dm0, mpopt, mpx, obj.psse_pqbrak);
                if ~isempty(dm)
                    return;
                end
            end

            [dm, obj.psse_xfmr] = mp.psse_xfmr_control( ...
                obj, mm, nm, dm0, mpopt, mpx, obj.psse_xfmr);
            if ~isempty(dm)
                return;
            end

            [dm, obj.psse_twodc] = mp.psse_twodc_control( ...
                obj, mm, nm, dm0, mpopt, mpx, obj.psse_twodc);
            if ~isempty(dm)
                return;
            end

            [dm, obj.psse_swshunt] = mp.psse_swshunt_control( ...
                obj, mm, nm, dm0, mpopt, mpx, obj.psse_swshunt);
            if ~isempty(dm)
                return;
            end

            [dm, obj.psse_facts] = mp.psse_facts_control( ...
                obj, mm, nm, dm0, mpopt, mpx, obj.psse_facts);
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
