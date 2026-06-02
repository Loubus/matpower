function target = psse_sync_cpf_target(base, target, base_ref)
% psse_sync_cpf_target - Copies PSS/E control state from CPF base to target.
% ::
%
%   TARGET = MP.PSSE_SYNC_CPF_TARGET(BASE, TARGET)
%   TARGET = MP.PSSE_SYNC_CPF_TARGET(BASE, TARGET, BASE_REF)
%
% Preserves load and active ``dcline`` transfer deltas in ``TARGET`` while
% copying the solved PSS/E active-set state from ``BASE`` for taps, shunts,
% generator Q control, DC line controls, FACTS and low-voltage load metadata.
%
% See also runcpf_psse, mp.task_cpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if isempty(target) || ~isstruct(base) || ~isstruct(target)
    target = base;
    return;
end
if nargin < 3
    base_ref = [];
end

[~, ~, ~, ~, ~, BUS_TYPE, PD, QD, GS, BS, ~, VM, VA] = idx_bus;
[~, PG, QG, QMAX, QMIN, VG, ~, GEN_STATUS, PMAX, PMIN] = idx_gen;
[~, ~, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, TAP, SHIFT, ...
    BR_STATUS] = idx_brch;
dci = idx_dcline;

if isfield(base, 'bus') && isfield(target, 'bus') && ...
        size(base.bus, 1) == size(target.bus, 1)
    load_delta = psse_cpf_load_delta(base_ref, target);
    if isempty(load_delta)
        keep = target.bus(:, [PD QD]);
    end
    cols = intersect([BUS_TYPE GS BS VM VA], 1:size(base.bus, 2));
    target.bus(:, cols) = base.bus(:, cols);
    if isempty(load_delta)
        target.bus(:, [PD QD]) = keep;
    else
        target.bus(:, [PD QD]) = base.bus(:, [PD QD]) + load_delta;
    end
end

if isfield(base, 'gen') && isfield(target, 'gen') && ...
        size(base.gen, 1) == size(target.gen, 1)
    keep_cols = intersect([PG PMAX PMIN], 1:size(target.gen, 2));
    keep = target.gen(:, keep_cols);
    cols = intersect([QG QMAX QMIN VG GEN_STATUS], 1:size(base.gen, 2));
    target.gen(:, cols) = base.gen(:, cols);
    target.gen(:, keep_cols) = keep;
end

if isfield(base, 'branch') && isfield(target, 'branch') && ...
        size(base.branch, 1) == size(target.branch, 1)
    cols = intersect([BR_R BR_X BR_B RATE_A RATE_B RATE_C TAP SHIFT ...
        BR_STATUS], 1:size(base.branch, 2));
    target.branch(:, cols) = base.branch(:, cols);
end

if isfield(base, 'dcline') && isfield(target, 'dcline') && ...
        size(base.dcline, 1) == size(target.dcline, 1)
    dcline_delta = psse_cpf_dcline_delta(base_ref, target);
    target.dcline = base.dcline;
    if ~isempty(dcline_delta) && size(target.dcline, 2) >= dci.PT
        target.dcline(:, [dci.PF dci.PT]) = ...
            base.dcline(:, [dci.PF dci.PT]) + dcline_delta;
    end
end

if isfield(base, 'psse')
    if ~isfield(target, 'psse') || isempty(target.psse)
        target.psse = base.psse;
    else
        families = {'xfmr', 'genq', 'twodc', 'swshunt', 'facts', ...
            'pqbrak', 'solver_options', 'control_failure'};
        for k = 1:length(families)
            name = families{k};
            if isfield(base.psse, name)
                target.psse.(name) = base.psse.(name);
            end
        end
    end
end
if exist('load_delta', 'var') && ~isempty(load_delta) && isfield(target, 'psse')
    target.psse.cpf_load_delta = load_delta;
end
if exist('dcline_delta', 'var') && ~isempty(dcline_delta) && ...
        isfield(target, 'psse')
    target.psse.cpf_dcline_delta = dcline_delta;
end

function load_delta = psse_cpf_load_delta(base_ref, target)
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
load_delta = [];
if ~isempty(base_ref) && isstruct(base_ref) && isfield(base_ref, 'bus') && ...
        isfield(target, 'bus') && size(base_ref.bus, 1) == size(target.bus, 1)
    load_delta = target.bus(:, [PD QD]) - base_ref.bus(:, [PD QD]);
elseif isfield(target, 'psse') && isfield(target.psse, 'cpf_load_delta') && ...
        size(target.psse.cpf_load_delta, 1) == size(target.bus, 1)
    load_delta = target.psse.cpf_load_delta;
end

function dcline_delta = psse_cpf_dcline_delta(base_ref, target)
dci = idx_dcline;
dcline_delta = [];
if ~isfield(target, 'dcline') || isempty(target.dcline) || ...
        size(target.dcline, 2) < dci.PT
    return;
end
if ~isempty(base_ref) && isstruct(base_ref) && ...
        isfield(base_ref, 'dcline') && ...
        size(base_ref.dcline, 1) == size(target.dcline, 1) && ...
        size(base_ref.dcline, 2) >= dci.PT
    dcline_delta = target.dcline(:, [dci.PF dci.PT]) - ...
        base_ref.dcline(:, [dci.PF dci.PT]);
elseif isfield(target, 'psse') && ...
        isfield(target.psse, 'cpf_dcline_delta') && ...
        size(target.psse.cpf_dcline_delta, 1) == size(target.dcline, 1)
    dcline_delta = target.psse.cpf_dcline_delta;
end
