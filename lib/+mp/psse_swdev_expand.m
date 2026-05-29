function results = psse_swdev_expand(results, state)
% psse_swdev_expand - Expands solved collapsed SWDEV buses for reporting.
% ::
%
%   RESULTS = MP.PSSE_SWDEV_EXPAND(RESULTS, STATE)
%
% Restores the original bus and branch rows after mp.psse_swdev_collapse().
% Collapsed buses inherit the solved voltage of their representative bus.
%
% See also mp.psse_swdev_collapse, runpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if isempty(state) || ~isstruct(state) || ~isfield(state, 'active') || ...
        ~state.active
    return;
end

[~, ~, ~, ~, BUS_I, BUS_TYPE, PD, QD, GS, BS] = idx_bus;
[GEN_BUS] = idx_gen;
dci = idx_dcline;

bus0 = state.original_bus;
bus = zeros(size(bus0, 1), max(size(bus0, 2), size(results.bus, 2)));
bus(:, 1:size(bus0, 2)) = bus0;
res_ext = results.bus(:, BUS_I);
orig_ext = bus0(:, BUS_I);
root_ext = orig_ext(state.roots);
[tf, loc] = ismember(root_ext, res_ext);
for kk = find(tf(:))'
    src = results.bus(loc(kk), :);
    bus(kk, 1:length(src)) = src;
    bus(kk, BUS_I) = orig_ext(kk);
    bus(kk, [BUS_TYPE PD QD GS BS]) = bus0(kk, [BUS_TYPE PD QD GS BS]);
end
results.bus = bus;

if isfield(results, 'gen') && ~isempty(results.gen) && ...
        isfield(state, 'original_gen') && ~isempty(state.original_gen)
    gen = results.gen;
    ncol = max(size(gen, 2), size(state.original_gen, 2));
    if size(gen, 2) < ncol
        gen(:, end+1:ncol) = 0;
    end
    gen(:, GEN_BUS) = state.original_gen(:, GEN_BUS);
    results.gen = gen;
end

if isfield(results, 'branch') && ~isempty(results.branch) && ...
        isfield(state, 'original_branch') && ~isempty(state.original_branch)
    branch0 = state.original_branch;
    branch = zeros(size(branch0, 1), max(size(branch0, 2), ...
        size(results.branch, 2)));
    branch(:, 1:size(branch0, 2)) = branch0;
    keep = state.branch_keep(:);
    n = min(length(keep), size(results.branch, 1));
    branch(keep(1:n), 1:size(results.branch, 2)) = results.branch(1:n, :);
    results.branch = branch;
end

if isfield(results, 'dcline') && ~isempty(results.dcline) && ...
        isfield(state, 'original_dcline') && ~isempty(state.original_dcline)
    results.dcline(:, dci.F_BUS) = state.original_dcline(:, dci.F_BUS);
    results.dcline(:, dci.T_BUS) = state.original_dcline(:, dci.T_BUS);
end

if isfield(results, 'psse')
    results.psse.swdev_collapsed = rmfield(state, intersect( ...
        fieldnames(state), {'original_bus', 'original_gen', ...
        'original_bus_name', 'original_branch', 'original_dcline'}));
end

if isfield(results, 'bus_name') && isfield(state, 'original_bus_name') && ...
        ~isempty(state.original_bus_name)
    results.bus_name = state.original_bus_name;
end
