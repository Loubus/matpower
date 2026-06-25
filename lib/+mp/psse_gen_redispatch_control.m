function [dm_next, state] = psse_gen_redispatch_control( ...
        task, mm, nm, dm, mpopt, mpx, state) %#ok<INUSD>
% psse_gen_redispatch_control - Executes CPF generator redispatch policy.
% ::
%
%   [DM_NEXT, STATE] = MP.PSSE_GEN_REDISPATCH_CONTROL(TASK, MM, NM, DM,
%       MPOPT, MPX, STATE)
%
% Applies accepted-point incremental generator redispatch for PSS/E-aware CPF
% runs. The active-set rebuild is handled by mp.task_cpf_psse.
%
% See also cpf_gen_redispatch_policy_state, mp.task_cpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

dm_next = [];
if nargin < 7 || isempty(state) || ~isstruct(state)
    state = [];
end
has_source = (isobject(dm) && isprop(dm, 'source')) || ...
    (isstruct(dm) && isfield(dm, 'source'));
if isempty(dm) || ~has_source || ...
        ~cpf_gen_redispatch_policy_state('enabled', dm.source, ...
        target_source(task), mpopt)
    return;
end

base = redispatch_base_source(task, dm.source);
target = target_source(task);
lam = redispatch_lambda(task);
[source1, target1, state, changed] = cpf_gen_redispatch_policy_state( ...
    'apply', base, dm.source, target, mpopt, state, lam);

if changed
    if ~isempty(target1) && isprop(task, 'psse_target_source')
        task.psse_target_source = target1;
    end
    dm_next = task.data_model_build(source1, task.dmc, mpopt, mpx);
end

function base = redispatch_base_source(task, fallback)
base = fallback;
if isprop(task, 'psse_redispatch_base_source') && ...
        ~isempty(task.psse_redispatch_base_source)
    base = task.psse_redispatch_base_source;
end

function lam = redispatch_lambda(task)
lam = NaN;
if isprop(task, 'psse_redispatch_lambda') && ...
        ~isempty(task.psse_redispatch_lambda)
    lam = task.psse_redispatch_lambda;
end

function target = target_source(task)
target = [];
if isprop(task, 'psse_target_source')
    target = task.psse_target_source;
end
