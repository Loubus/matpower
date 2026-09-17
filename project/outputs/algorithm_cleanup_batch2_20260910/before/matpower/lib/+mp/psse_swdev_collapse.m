function [mpc, state] = psse_swdev_collapse(mpc)
% psse_swdev_collapse - Collapses closed PSS/E switching devices for PF.
% ::
%
%   [MPC, STATE] = MP.PSSE_SWDEV_COLLAPSE(MPC)
%
% PSS/E SYSTEM SWITCHING DEVICE records use X for loop-flow calculations,
% while closed devices are electrical connectors for power flow. For
% runpf_psse(), collapse closed devices at or below THRSHZ into a single bus
% before ext2int(), preserving enough state to expand solved voltages back to
% the original bus list.
%
% See also runpf_psse, psse2mpc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

state = struct('active', false);
if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'swdev') || ...
        isempty(mpc.psse.swdev.branch_idx) || isempty(mpc.bus)
    return;
end
if isfield(mpc.psse.swdev, 'collapse_disabled') && ...
        ~isempty(mpc.psse.swdev.collapse_disabled) && ...
        any(mpc.psse.swdev.collapse_disabled(:))
    return;
end
if isfield(mpc.psse, 'swdev_collapsed') && ...
        isfield(mpc.psse.swdev_collapsed, 'active') && ...
        mpc.psse.swdev_collapsed.active && ...
        isfield(mpc.psse.swdev_collapsed, 'original_bus')
    state = mpc.psse.swdev_collapsed;
    return;
end

[~, ~, ~, ~, BUS_I, ~, PD, QD, GS, BS] = idx_bus;
[F_BUS, T_BUS, ~, ~, ~, ~, ~, ~, ~, ~, BR_STATUS] = idx_brch;
[GEN_BUS] = idx_gen;
dci = idx_dcline;

swdev = mpc.psse.swdev;
thrshz = mp.psse_system_value(mpc, 'general', 'THRSHZ', 1e-4);
if isnan(thrshz) || thrshz <= 0
    thrshz = 1e-4;
end

nb = size(mpc.bus, 1);
nbr = size(mpc.branch, 1);
candidate = swdev.status ~= 0 & abs(swdev.x) <= thrshz & ...
    swdev.branch_idx > 0 & swdev.branch_idx <= nbr;
closed = false(size(candidate));
if any(candidate)
    closed(candidate) = mpc.branch(swdev.branch_idx(candidate), ...
        BR_STATUS) ~= 0;
end
if ~any(closed)
    return;
end

parent = 1:nb;
for kk = find(closed(:))'
    i = swdev.f_bus_idx(kk);
    j = swdev.t_bus_idx(kk);
    if i > 0 && i <= nb && j > 0 && j <= nb
        parent = uf_union(parent, i, j);
    end
end
for kk = 1:nb
    parent(kk) = uf_find(parent, kk);
end

roots = parent(:);
for kk = 1:nb
    roots(kk) = find(parent == parent(kk), 1, 'first');
end
remove_bus = (1:nb)' ~= roots(:);
if ~any(remove_bus)
    return;
end

bus_keep = find(~remove_bus);
old_to_new_bus = zeros(nb, 1);
old_to_new_bus(bus_keep) = (1:length(bus_keep))';
old_to_new_bus(remove_bus) = old_to_new_bus(roots(remove_bus));

branch_remove = false(nbr, 1);
branch_remove(swdev.branch_idx(closed)) = true;
branch_keep = find(~branch_remove);
old_to_new_branch = zeros(nbr, 1);
old_to_new_branch(branch_keep) = (1:length(branch_keep))';

state.active = true;
state.original_bus = mpc.bus;
if isfield(mpc, 'bus_name')
    state.original_bus_name = mpc.bus_name;
else
    state.original_bus_name = [];
end
state.original_gen = mpc.gen;
state.original_branch = mpc.branch;
if isfield(mpc, 'dcline')
    state.original_dcline = mpc.dcline;
else
    state.original_dcline = [];
end
state.bus_keep = bus_keep;
state.branch_keep = branch_keep;
state.old_to_new_bus = old_to_new_bus;
state.old_to_new_branch = old_to_new_branch;
state.roots = roots;
state.collapsed_branch_idx = find(branch_remove);

%% aggregate removed bus shunts and loads onto the representative bus
for kk = find(remove_bus(:))'
    r = roots(kk);
    mpc.bus(r, [PD QD GS BS]) = mpc.bus(r, [PD QD GS BS]) + ...
        mpc.bus(kk, [PD QD GS BS]);
end
mpc.bus = set_representative_bus_states(mpc.bus, roots, remove_bus);

%% replace removed external bus numbers by representative external numbers
old_ext = mpc.bus(:, BUS_I);
root_ext = old_ext(roots);
for col = [F_BUS T_BUS]
    [tf, loc] = ismember(mpc.branch(:, col), old_ext);
    mpc.branch(tf, col) = root_ext(loc(tf));
end
[tf, loc] = ismember(mpc.gen(:, GEN_BUS), old_ext);
mpc.gen(tf, GEN_BUS) = root_ext(loc(tf));
if isfield(mpc, 'dcline') && ~isempty(mpc.dcline)
    for col = [dci.F_BUS dci.T_BUS]
        [tf, loc] = ismember(mpc.dcline(:, col), old_ext);
        mpc.dcline(tf, col) = root_ext(loc(tf));
    end
end

mpc.bus = mpc.bus(bus_keep, :);
if isfield(mpc, 'bus_name') && length(mpc.bus_name) == nb
    mpc.bus_name = mpc.bus_name(bus_keep, :);
end
mpc.branch = mpc.branch(branch_keep, :);
mpc.psse = update_metadata_indices(mpc.psse, old_to_new_bus, old_to_new_branch);
mpc.psse.swdev_collapsed = state;

function bus = set_representative_bus_states(bus, roots, remove_bus)
[~, PV, REF, ~, ~, BUS_TYPE, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
reps = unique(roots(remove_bus));
for r = reps(:)'
    members = find(roots == r);
    ref_members = members(bus(members, BUS_TYPE) == REF);
    pv_members = members(bus(members, BUS_TYPE) == PV);
    if ~isempty(ref_members)
        src = ref_members(1);
        bus(r, BUS_TYPE) = REF;
        bus(r, [VM VA]) = bus(src, [VM VA]);
    elseif ~isempty(pv_members)
        src = pv_members(1);
        bus(r, BUS_TYPE) = PV;
        bus(r, [VM VA]) = bus(src, [VM VA]);
    end
end

function parent = uf_union(parent, a, b)
ra = uf_find(parent, a);
rb = uf_find(parent, b);
if ra ~= rb
    parent(max(ra, rb)) = min(ra, rb);
end

function r = uf_find(parent, a)
r = a;
while parent(r) ~= r
    r = parent(r);
end

function s = update_metadata_indices(s, old_to_new_bus, old_to_new_branch)
if ~isstruct(s)
    return;
end
for ii = 1:numel(s)
    f = fieldnames(s(ii));
    for jj = 1:length(f)
        name = f{jj};
        val = s(ii).(name);
        if isstruct(val)
            s(ii).(name) = update_metadata_indices(val, ...
                old_to_new_bus, old_to_new_branch);
        elseif isnumeric(val)
            if endsWith(name, 'bus_idx')
                s(ii).(name) = remap_positive(val, old_to_new_bus);
            elseif strcmp(name, 'branch_idx')
                s(ii).(name) = remap_positive(val, old_to_new_branch);
            end
        end
    end
end

function v = remap_positive(v, map)
idx = v > 0 & v <= length(map);
v(idx) = map(v(idx));
