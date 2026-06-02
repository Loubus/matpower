classdef xt_psse < mp.extension
% mp.xt_psse - |MATPOWER| extension for PSS/E PF/CPF behavior.
%
% Replaces the standard legacy power flow and continuation power flow tasks
% with PSS/E-aware variants, enabling opt-in PSS/E-specific controls through
% runpf_psse() and runcpf_psse().
%
% mp.xt_psse Methods:
%   * task_class - replace legacy PF/CPF tasks with PSS/E task variants
%
% See also mp.extension, mp.task_pf_psse, mp.task_cpf_psse, runpf_psse,
% runcpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

    methods
        function task_class = task_class(~, task_class, ~)
            % Replace legacy PF/CPF tasks with PSS/E-aware task variants.

            if isequal(task_class, @mp.task_pf_legacy)
                task_class = @mp.task_pf_psse;
            elseif isequal(task_class, @mp.task_cpf_legacy)
                task_class = @mp.task_cpf_psse;
            end
        end
    end     %% methods
end         %% classdef
