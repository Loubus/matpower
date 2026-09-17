function [mpc, info] = beerten_cpf_apply_options(mpc, opts)
%BEERTEN_CPF_APPLY_OPTIONS Apply runner options to a Beerten case struct.

info = struct();
info.had_vsc_hvdc = has_vsc_mtdc_fields(mpc);
info.vsc_hvdc_enabled = logical(opts.vsc_hvdc.enabled);
info.vsc_rows = 0;
info.busdc_rows = 0;
info.branchdc_rows = 0;
if isfield(mpc, 'vsc')
    info.vsc_rows = size(mpc.vsc, 1);
end
if isfield(mpc, 'busdc')
    info.busdc_rows = size(mpc.busdc, 1);
end
if isfield(mpc, 'branchdc')
    info.branchdc_rows = size(mpc.branchdc, 1);
end
info.had_switched_shunt = has_psse_switched_shunt(mpc);
info.had_ultc_transformer = has_psse_ultc_transformer(mpc);
info.switched_shunt_enabled = logical(opts.devices.switched_shunt);
info.ultc_transformer_enabled = logical(opts.devices.ultc_transformer);

mpc = apply_psse_device_options(mpc, opts);
mpc = apply_psse_controls(mpc, opts);

if ~opts.vsc_hvdc.enabled
    mpc = disable_vsc_hvdc(mpc, opts);
    return;
end

if opts.vsc_hvdc.force_in_service && has_vsc_mtdc_fields(mpc)
    c = idx_vsc;
    bdc = idx_busdc;
    brdc = idx_branchdc;
    mpc.vsc(:, c.VSC_STATUS) = 1;
    mpc.busdc(:, bdc.BUSDC_STATUS) = 1;
    mpc.branchdc(:, brdc.BRDC_STATUS) = 1;
end

if opts.policy.disable_hvdc_redispatch_for_full_trace
    mpc = set_hvdc_policy_none(mpc);
end
if opts.policy.disable_vsc_derating_for_full_trace
    mpc = set_vsc_derating_enabled(mpc, 0);
end
end

function mpc = apply_psse_controls(mpc, opts)
if ~isfield(mpc, 'psse')
    return;
end
if ~isfield(mpc.psse, 'system')
    mpc.psse.system = struct();
end
if ~isfield(mpc.psse.system, 'solver')
    mpc.psse.system.solver = struct();
end
mpc.psse.system.solver.ACTAPS = ...
    opts.controls.ACTAPS && opts.devices.ultc_transformer;
mpc.psse.system.solver.SWSHNT = ...
    opts.controls.SWSHNT && opts.devices.switched_shunt;
end

function mpc = apply_psse_device_options(mpc, opts)
if opts.devices.switched_shunt && opts.devices.ultc_transformer
    return;
end
if ~isfield(mpc, 'psse')
    return;
end
if ~opts.devices.switched_shunt
    mpc = remove_psse_switched_shunts(mpc);
end
if ~opts.devices.ultc_transformer
    mpc = remove_psse_ultc_transformers(mpc);
end
end

function mpc = remove_psse_switched_shunts(mpc)
if isfield(mpc.psse, 'swshunt') && isfield(mpc.psse.swshunt, 'num') && ...
        ~isempty(mpc.psse.swshunt.num)
    [~, ~, ~, ~, BUS_I, ~, ~, ~, ~, BS] = idx_bus;
    i_col = psse_col(mpc.psse.swshunt, 'I');
    if i_col > 0
        sw_buses = mpc.psse.swshunt.num(:, i_col);
        for k = 1:numel(sw_buses)
            row = find(mpc.bus(:, BUS_I) == sw_buses(k), 1);
            if ~isempty(row)
                mpc.bus(row, BS) = 0;
            end
        end
    end
end
if isfield(mpc.psse, 'swshunt')
    mpc.psse = rmfield(mpc.psse, 'swshunt');
end
mpc = set_explicit_option_flag(mpc, 'enable_psse_switched_shunt', 0);
end

function mpc = remove_psse_ultc_transformers(mpc)
if isfield(mpc.psse, 'xfmr')
    if isfield(mpc.psse.xfmr, 'two')
        mpc = remove_two_winding_transformer_topology(mpc, ...
            mpc.psse.xfmr.two);
        mpc.psse.xfmr.two = empty_two_winding_xfmr();
    end
    if isfield(mpc.psse.xfmr, 'three')
        mpc.psse.xfmr.three = empty_three_winding_xfmr();
    end
end
mpc = set_explicit_option_flag(mpc, 'enable_psse_ultc', 0);
end

function mpc = remove_two_winding_transformer_topology(mpc, xf)
if ~isfield(xf, 'num') || isempty(xf.num)
    return;
end

[~, ~, ~, ~, BUS_I, ~, PD, QD, GS, BS] = idx_bus;
[F_BUS, T_BUS] = idx_brch;

merges = zeros(0, 3);
for k = 1:size(xf.num, 1)
    [from_bus, to_bus] = xfmr_buses(xf, k);
    branch_row = xfmr_branch_row(mpc, xf, k, from_bus, to_bus);
    if branch_row == 0
        error('beerten_cpf_apply_options:missing_ultc_branch', ...
            'Could not find the AC branch for ULTC transformer row %d.', k);
    end
    if from_bus == 0 || to_bus == 0
        from_bus = mpc.branch(branch_row, F_BUS);
        to_bus = mpc.branch(branch_row, T_BUS);
    end
    [retained_bus, removed_bus] = radial_extra_bus(mpc, ...
        from_bus, to_bus, branch_row);
    merges(end+1, :) = [retained_bus removed_bus branch_row]; %#ok<AGROW>
end

for k = 1:size(merges, 1)
    retained_row = find(mpc.bus(:, BUS_I) == merges(k, 1), 1);
    removed_row = find(mpc.bus(:, BUS_I) == merges(k, 2), 1);
    if isempty(retained_row) || isempty(removed_row)
        continue;
    end
    mpc.bus(retained_row, [PD QD GS BS]) = ...
        mpc.bus(retained_row, [PD QD GS BS]) + ...
        mpc.bus(removed_row, [PD QD GS BS]);
end

branch_rows = unique(merges(:, 3));
branch_rows = branch_rows(branch_rows > 0 & branch_rows <= size(mpc.branch, 1));
mpc.branch(branch_rows, :) = [];

removed_buses = unique(merges(:, 2));
remove_bus_rows = false(size(mpc.bus, 1), 1);
for k = 1:numel(removed_buses)
    remove_bus_rows = remove_bus_rows | mpc.bus(:, BUS_I) == removed_buses(k);
end
mpc.bus(remove_bus_rows, :) = [];
end

function [from_bus, to_bus] = xfmr_buses(xf, row)
from_bus = 0;
to_bus = 0;
i_col = psse_col(xf, 'I');
j_col = psse_col(xf, 'J');
if i_col > 0
    from_bus = xf.num(row, i_col);
end
if j_col > 0
    to_bus = xf.num(row, j_col);
end
end

function row = xfmr_branch_row(mpc, xf, xf_row, from_bus, to_bus)
[F_BUS, T_BUS] = idx_brch;
row = 0;
if isfield(xf, 'branch_idx') && numel(xf.branch_idx) >= xf_row && ...
        isfinite(xf.branch_idx(xf_row)) && xf.branch_idx(xf_row) >= 1 && ...
        xf.branch_idx(xf_row) <= size(mpc.branch, 1)
    row = xf.branch_idx(xf_row);
    return;
end
if from_bus == 0 || to_bus == 0
    return;
end
match = find((mpc.branch(:, F_BUS) == from_bus & ...
    mpc.branch(:, T_BUS) == to_bus) | ...
    (mpc.branch(:, F_BUS) == to_bus & ...
    mpc.branch(:, T_BUS) == from_bus), 1);
if ~isempty(match)
    row = match;
end
end

function [retained_bus, removed_bus] = radial_extra_bus(mpc, bus_a, ...
        bus_b, branch_row)
[F_BUS, T_BUS] = idx_brch;
[GEN_BUS] = idx_gen;
candidates = [bus_a bus_b];
for k = 1:2
    candidate = candidates(k);
    other = candidates(3 - k);
    connected = find(mpc.branch(:, F_BUS) == candidate | ...
        mpc.branch(:, T_BUS) == candidate);
    connected = setdiff(connected(:), branch_row);
    has_gen = isfield(mpc, 'gen') && ...
        any(mpc.gen(:, GEN_BUS) == candidate);
    has_vsc = isfield(mpc, 'vsc') && ...
        ~isempty(mpc.vsc) && any(mpc.vsc(:, 1) == candidate);
    if isempty(connected) && ~has_gen && ~has_vsc
        removed_bus = candidate;
        retained_bus = other;
        return;
    end
end
error('beerten_cpf_apply_options:non_radial_ultc_bus', ...
    ['Cannot remove ULTC transformer between buses %g and %g because ' ...
    'neither side is a radial auxiliary bus.'], bus_a, bus_b);
end

function tf = has_psse_switched_shunt(mpc)
tf = isfield(mpc, 'psse') && isfield(mpc.psse, 'swshunt') && ...
    isfield(mpc.psse.swshunt, 'num') && ~isempty(mpc.psse.swshunt.num);
end

function tf = has_psse_ultc_transformer(mpc)
tf = false;
if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'xfmr')
    return;
end
if isfield(mpc.psse.xfmr, 'two') && isfield(mpc.psse.xfmr.two, 'num') && ...
        ~isempty(mpc.psse.xfmr.two.num)
    tf = true;
    return;
end
if isfield(mpc.psse.xfmr, 'three') && ...
        isfield(mpc.psse.xfmr.three, 'num') && ...
        ~isempty(mpc.psse.xfmr.three.num)
    tf = true;
end
end

function xf = empty_two_winding_xfmr()
xf = struct( ...
    'colnames', {{}}, ...
    'num', zeros(0, 52), ...
    'txt', {cell(0, 52)}, ...
    'branch_idx', zeros(0, 1), ...
    'col', struct());
end

function xf = empty_three_winding_xfmr()
xf = struct( ...
    'colnames', {{}}, ...
    'num', zeros(0, 112), ...
    'txt', {cell(0, 112)}, ...
    'branch_idx', zeros(0, 3), ...
    'col', struct());
end

function col = psse_col(block, name)
col = 0;
if ~isfield(block, 'colnames')
    return;
end
match = find(strcmpi(block.colnames, name), 1);
if ~isempty(match)
    col = match;
end
end

function mpc = disable_vsc_hvdc(mpc, opts)
fields = {'busdc', 'branchdc', 'vsc'};
for k = 1:numel(fields)
    if isfield(mpc, fields{k})
        mpc = rmfield(mpc, fields{k});
    end
end
if opts.vsc_hvdc.disable_vsc_capability_policy && ...
        isfield(mpc, 'vsc_capability')
    mpc = rmfield(mpc, 'vsc_capability');
end
if opts.vsc_hvdc.disable_hvdc_policy
    mpc = set_hvdc_policy_none(mpc);
end
if opts.vsc_hvdc.disable_vsc_capability_policy
    mpc = remove_policy_field(mpc, 'vsc_capability');
    mpc = remove_policy_field(mpc, 'vsc_slack_q_relief');
end
mpc = set_explicit_option_flag(mpc, 'enable_vsc_capability_enforcement', 0);
mpc = set_explicit_option_flag(mpc, 'enable_vsc_hvdc', 0);
end

function TorF = has_vsc_mtdc_fields(mpc)
TorF = isstruct(mpc) && isfield(mpc, 'busdc') && ...
    isfield(mpc, 'branchdc') && isfield(mpc, 'vsc');
end

function mpc = set_hvdc_policy_none(mpc)
mpc = set_nested_hvdc_policy_none(mpc, {'cpf_policies', 'hvdc'});
mpc = set_nested_hvdc_policy_none(mpc, ...
    {'explicit_options', 'cpf_policies', 'hvdc'});
end

function mpc = set_nested_hvdc_policy_none(mpc, path)
if ~has_nested_struct(mpc, path)
    return;
end
switch numel(path)
    case 2
        mpc.(path{1}).(path{2}).policy = 'none';
        if isfield(mpc.(path{1}).(path{2}), 'vsc_derating')
            mpc.(path{1}).(path{2}).vsc_derating.enabled = 0;
        end
    case 3
        mpc.(path{1}).(path{2}).(path{3}).policy = 'none';
        if isfield(mpc.(path{1}).(path{2}).(path{3}), 'vsc_derating')
            mpc.(path{1}).(path{2}).(path{3}).vsc_derating.enabled = 0;
        end
end
end

function mpc = set_vsc_derating_enabled(mpc, enabled)
mpc = set_nested_vsc_derating_enabled(mpc, {'cpf_policies', 'hvdc'}, enabled);
mpc = set_nested_vsc_derating_enabled(mpc, ...
    {'explicit_options', 'cpf_policies', 'hvdc'}, enabled);
end

function mpc = set_nested_vsc_derating_enabled(mpc, path, enabled)
if ~has_nested_struct(mpc, path)
    return;
end
switch numel(path)
    case 2
        if isfield(mpc.(path{1}).(path{2}), 'vsc_derating')
            mpc.(path{1}).(path{2}).vsc_derating.enabled = enabled;
        end
    case 3
        if isfield(mpc.(path{1}).(path{2}).(path{3}), 'vsc_derating')
            mpc.(path{1}).(path{2}).(path{3}).vsc_derating.enabled = enabled;
        end
end
end

function mpc = remove_policy_field(mpc, field)
if isfield(mpc, 'cpf_policies') && isfield(mpc.cpf_policies, field)
    mpc.cpf_policies = rmfield(mpc.cpf_policies, field);
end
if isfield(mpc, 'explicit_options') && ...
        isfield(mpc.explicit_options, 'cpf_policies') && ...
        isfield(mpc.explicit_options.cpf_policies, field)
    mpc.explicit_options.cpf_policies = ...
        rmfield(mpc.explicit_options.cpf_policies, field);
end
end

function mpc = set_explicit_option_flag(mpc, field, value)
if isfield(mpc, 'explicit_options') && isstruct(mpc.explicit_options)
    mpc.explicit_options.(field) = value;
end
end

function tf = has_nested_struct(s, path)
tf = isstruct(s);
for kk = 1:numel(path)
    if ~tf || ~isfield(s, path{kk})
        tf = false;
        return;
    end
    s = s.(path{kk});
    tf = isstruct(s);
end
end
