classdef xt_psse < mp.extension
% mp.xt_psse - |MATPOWER| extension for PSS/E power flow behavior.
%
% Replaces the standard legacy power flow task with mp.task_pf_psse,
% enabling opt-in PSS/E-specific controls through runpf_psse().
%
% mp.xt_psse Methods:
%   * task_class - replace legacy PF task with PSS/E PF task
%
% See also mp.extension, mp.task_pf_psse, runpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

    methods
        function task_class = task_class(~, task_class, ~)
            % Replace legacy PF task with PSS/E PF task.

            if isequal(task_class, @mp.task_pf_legacy)
                task_class = @mp.task_pf_psse;
            end
        end
    end     %% methods
end         %% classdef
