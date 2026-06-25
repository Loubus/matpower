function [mpc, state] = psse_branch_collapse(mpc)
% psse_branch_collapse - Collapses low-impedance PSS/E branches for PF.
% ::
%
%   [MPC, STATE] = MP.PSSE_BRANCH_COLLAPSE(MPC)
%
% Collapses active AC branch rows with impedance magnitude at or below the
% PSS/E THRSHZ threshold into a single bus before ext2int(). The solved
% voltages can then be expanded back to the original bus list with
% mp.psse_branch_expand().
%
% See also mp.psse_branch_expand, runpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

state = struct('active', false);
if ~isfield(mpc, 'psse') || isempty(mpc.bus) || ...
        ~isfield(mpc, 'branch') || isempty(mpc.branch)
    return;
end
if isfield(mpc.psse, 'branch_collapsed') && ...
        isfield(mpc.psse.branch_collapsed, 'active') && ...
        mpc.psse.branch_collapsed.active && ...
        isfield(mpc.psse.branch_collapsed, 'original_bus')
    state = mpc.psse.branch_collapsed;
    return;
end
if isfield(mpc.psse, 'branch_collapse_disabled') && ...
        ~isempty(mpc.psse.branch_collapse_disabled) && ...
        any(mpc.psse.branch_collapse_disabled(:))
    return;
end

[~, ~, ~, ~, BUS_I, ~, PD, QD, GS, BS] = idx_bus;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, ~, ~, ~, TAP, SHIFT, BR_STATUS] = idx_brch;
[GEN_BUS] = idx_gen;
dci = idx_dcline;

thrshz = mp.psse_system_value(mpc, 'general', 'THRSHZ', 1e-4);
if isnan(thrshz) || thrshz <= 0
    thrshz = 1e-4;
end

nb = size(mpc.bus, 1);
nbr = size(mpc.branch, 1);
old_ext = mpc.bus(:, BUS_I);
[has_f, f_idx] = ismember(mpc.branch(:, F_BUS), old_ext);
[has_t, t_idx] = ismember(mpc.branch(:, T_BUS), old_ext);
[xfmr_branch, xfmr_bus] = psse_xfmr_collapse_protection(mpc, old_ext, nbr);
xfmr_endpoint = false(nbr, 1);
xfmr_endpoint(has_f) = xfmr_endpoint(has_f) | xfmr_bus(f_idx(has_f));
xfmr_endpoint(has_t) = xfmr_endpoint(has_t) | xfmr_bus(t_idx(has_t));
tap = mpc.branch(:, TAP);
neutral_tap = tap == 0 | abs(tap - 1) <= 1e-12;
zmag = hypot(mpc.branch(:, BR_R), mpc.branch(:, BR_X));
candidate = mpc.branch(:, BR_STATUS) ~= 0 & zmag <= thrshz & ...
    abs(mpc.branch(:, BR_B)) <= 1e-12 & neutral_tap & ...
    abs(mpc.branch(:, SHIFT)) <= 1e-12 & ...
    mpc.branch(:, F_BUS) ~= mpc.branch(:, T_BUS) & ...
    ~xfmr_branch & ~xfmr_endpoint;
if ~any(candidate)
    return;
end

candidate = candidate & has_f & has_t;
if ~any(candidate)
    return;
end

parent = 1:nb;
for kk = find(candidate(:))'
    parent = uf_union(parent, f_idx(kk), t_idx(kk));
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

root_ext = old_ext(roots);
mapped_f = root_ext(f_idx);
mapped_t = root_ext(t_idx);
branch_remove = candidate | (has_f & has_t & mapped_f == mapped_t);
branch_keep = find(~branch_remove);
old_to_new_branch = zeros(nbr, 1);
old_to_new_branch(branch_keep) = (1:length(branch_keep))';

state.active = true;
state.kind = 'branch';
state.threshold = thrshz;
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

for kk = find(remove_bus(:))'
    r = roots(kk);
    mpc.bus(r, [PD QD GS BS]) = mpc.bus(r, [PD QD GS BS]) + ...
        mpc.bus(kk, [PD QD GS BS]);
end
mpc.bus = set_representative_bus_states(mpc.bus, roots, remove_bus);

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
mpc.psse.branch_collapsed = state;

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

function [branch_mask, bus_mask] = psse_xfmr_collapse_protection(mpc, old_ext, nbr)
branch_mask = false(nbr, 1);
bus_mask = false(length(old_ext), 1);
if ~isfield(mpc.psse, 'xfmr') || isempty(mpc.psse.xfmr)
    return;
end

branch_idx = [];
bus_ext = [];
xf = mpc.psse.xfmr;
if isfield(xf, 'two') && isstruct(xf.two)
    [branch_idx, bus_ext] = collect_xfmr_protection( ...
        xf.two, branch_idx, bus_ext, {'i', 'j', 'cont1'});
end
if isfield(xf, 'three') && isstruct(xf.three)
    [branch_idx, bus_ext] = collect_xfmr_protection( ...
        xf.three, branch_idx, bus_ext, ...
        {'i', 'j', 'k', 'cont1', 'cont2', 'cont3'});
end

branch_idx = branch_idx(~isnan(branch_idx) & branch_idx > 0 & ...
    branch_idx <= nbr);
branch_mask(branch_idx) = true;

bus_ext = abs(bus_ext(~isnan(bus_ext) & bus_ext ~= 0));
[tf, loc] = ismember(bus_ext, old_ext);
bus_mask(loc(tf)) = true;

function [branch_idx, bus_ext] = collect_xfmr_protection(x, branch_idx, ...
        bus_ext, colnames)
if isfield(x, 'branch_idx') && ~isempty(x.branch_idx)
    branch_idx = [branch_idx; x.branch_idx(:)];
end
if ~isfield(x, 'num') || isempty(x.num) || ~isfield(x, 'col') || ...
        isempty(x.col)
    return;
end
cols = zeros(length(colnames), 1);
ncols = 0;
for kk = 1:length(colnames)
    name = colnames{kk};
    if isfield(x.col, name)
        c = x.col.(name);
        if ~isempty(c) && c > 0 && c <= size(x.num, 2)
            ncols = ncols + 1;
            cols(ncols) = c;
        end
    end
end
if ncols
    bus_ext = [bus_ext; reshape(x.num(:, cols(1:ncols)), [], 1)];
end
