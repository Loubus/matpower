function cpfc = psse_cpf_compact_trace(cpf, tol)
% psse_cpf_compact_trace - Compress repeated-lambda CPF trace points.
% ::
%
%   CPFC = MP.PSSE_CPF_COMPACT_TRACE(CPF)
%   CPFC = MP.PSSE_CPF_COMPACT_TRACE(CPF, TOL)
%
% Keeps the first and last point of each consecutive repeated-lambda block and
% removes only the intermediate re-correction points. This is intended for
% plotting PSS/E active-set jumps as one vertical move, while preserving the
% full diagnostic trace in RESULTS.CPF.
%
% See also runcpf_psse, mp.task_cpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 2 || isempty(tol)
    tol = 1e-10;
end

cpfc = cpf;
if ~isstruct(cpf) || ~isfield(cpf, 'lam') || isempty(cpf.lam)
    return;
end

lam = cpf.lam(:).';
n = length(lam);
keep = true(1, n);
groups = repmat( ...
    struct('i1', [], 'iN', [], 'lambda', [], 'n_removed', []), 1, n);
ng = 0;

i = 1;
while i <= n
    j = i;
    while j < n && abs(lam(j+1) - lam(i)) <= tol
        j = j + 1;
    end
    if j > i
        if j > i + 1
            keep(i+1:j-1) = false;
        end
        ng = ng + 1;
        groups(ng) = struct( ...
            'i1', i, ...
            'iN', j, ...
            'lambda', lam(i), ...
            'n_removed', max(0, j-i-1) );
    end
    i = j + 1;
end
groups = groups(1:ng);

idx = find(keep);
names = fieldnames(cpf);
for k = 1:length(names)
    name = names{k};
    val = cpf.(name);
    if isnumeric(val) || islogical(val)
        if isvector(val) && numel(val) == n
            cpfc.(name) = psse_keep_vector_orientation(val, idx);
        elseif ismatrix(val) && size(val, 2) == n
            cpfc.(name) = val(:, idx);
        end
    end
end

cpfc.source_index = idx;
cpfc.repeat_groups = groups;
cpfc.compaction = struct( ...
    'tol', tol, ...
    'original_points', n, ...
    'kept_points', length(idx), ...
    'removed_points', n - length(idx) );
end

function valc = psse_keep_vector_orientation(val, idx)
% Preserve row/column orientation while selecting compact CPF points.

if isrow(val)
    valc = val(idx);
else
    valc = val(idx(:));
end
end
