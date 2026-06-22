function [target, dispatch] = make_vsc_hvdc_pac_dispatch_target(base, target, policy)
% make_vsc_hvdc_pac_dispatch_target - Builds CPF targets with Pac dispatch.
% ::
%
%   TARGET = MAKE_VSC_HVDC_PAC_DISPATCH_TARGET(BASE, TARGET, POLICY)
%   [TARGET, DISPATCH] = MAKE_VSC_HVDC_PAC_DISPATCH_TARGET(...)
%
%   Applies a scheduled active-power VSC/HVDC transfer to a CPF target by
%   modifying PAC_SET on selected VSCs. This helper is intended for
%   paper-style VSC cases where active transfer is controlled on the AC side
%   through PQ or PV converters. It does not modify PDC_SET.
%
%   POLICY values:
%       'constant'
%           Copies VSC transfer set points from BASE to TARGET.
%
%       'pac_pair_transfer'
%           Schedules a point-to-point transfer between two AC-side VSC
%           converters. SOURCE absorbs more active power from the AC grid and
%           SINK injects more active power into the AC grid, with net PAC_SET
%           change equal to zero.
%
%           Required fields:
%               TRANSFER_MW
%               SOURCE_BUS or SOURCE_CONVERTER
%               SINK_BUS or SINK_CONVERTER
%
%           Optional fields:
%               QAC_DELTA, QAC_BUSES or QAC_CONVERTERS
%               CRITERION, RELIEVED_BRANCH
%
%   A positive TRANSFER_MW applies:
%       SOURCE PAC_SET = BASE PAC_SET - TRANSFER_MW
%       SINK   PAC_SET = BASE PAC_SET + TRANSFER_MW
%
% See also make_vsc_hvdc_dispatch_target, make_cpf_gen_dispatch_target,
% idx_vsc, runcpf_vsc_mtdc.

%   MATPOWER

if nargin < 3 || isempty(policy)
    policy = 'constant';
end

base = loadcase(base);
target = loadcase(target);
c = idx_vsc;

validate_cases(base, target, c);
mode = policy_mode(policy);
setpoint_cols = [c.PAC_SET c.QAC_SET c.VAC_SET c.PDC_SET ...
    c.VDC_SET c.KDROOP];
target.vsc(:, setpoint_cols) = base.vsc(:, setpoint_cols);

nv = size(base.vsc, 1);
delta_pac = zeros(nv, 1);
source_idx = [];
sink_idx = [];
transfer_mw = 0;

switch mode
    case 'constant'
        %% no additional action
    case 'pac_pair_transfer'
        transfer_mw = required_scalar_policy_field(policy, 'transfer_mw', mode);
        source_idx = selected_one_converter(policy, base, c, ...
            {'source_converter', 'source_idx', 'from_converter'}, ...
            {'source_bus', 'source_ac_bus', 'from_bus'});
        sink_idx = selected_one_converter(policy, base, c, ...
            {'sink_converter', 'sink_idx', 'to_converter'}, ...
            {'sink_bus', 'sink_ac_bus', 'to_bus'});
        if source_idx == sink_idx
            error('make_vsc_hvdc_pac_dispatch_target: source and sink converters must be different');
        end
        validate_pac_schedule(base, [source_idx; sink_idx], c);

        delta_pac(source_idx) = -transfer_mw;
        delta_pac(sink_idx) = transfer_mw;
        target.vsc(:, c.PAC_SET) = target.vsc(:, c.PAC_SET) + delta_pac;
    otherwise
        error('make_vsc_hvdc_pac_dispatch_target: unknown policy ''%s''', mode);
end

[qac_idx, delta_qac] = reactive_delta(policy, base, c);
if ~isempty(qac_idx)
    target.vsc(:, c.QAC_SET) = target.vsc(:, c.QAC_SET) + delta_qac;
end

affected = unique([source_idx(:); sink_idx(:); qac_idx(:)]);
dispatch = struct( ...
    'policy',              mode, ...
    'criterion',           policy_text(policy, 'criterion', ''), ...
    'relieved_branch',     policy_first_field(policy, {'relieved_branch', ...
                             'relieved_ac_branch'}), ...
    'transfer_mw',         transfer_mw, ...
    'source_converter_idx', source_idx, ...
    'sink_converter_idx',  sink_idx, ...
    'source_ac_bus',       converter_buses(base, source_idx, c), ...
    'sink_ac_bus',         converter_buses(base, sink_idx, c), ...
    'delta_pac_set',       delta_pac, ...
    'net_delta_pac_set',   sum(delta_pac), ...
    'uses_pdc_set',        0, ...
    'qac_converter_idx',   qac_idx(:), ...
    'qac_ac_buses',        converter_buses(base, qac_idx, c), ...
    'delta_qac_set',       delta_qac, ...
    'affected_converters', affected(:), ...
    'affected_ac_buses',   converter_buses(base, affected, c) );


function validate_cases(base, target, c)
if ~isfield(base, 'bus') || ~isfield(target, 'bus') || ...
        ~isfield(base, 'gen') || ~isfield(target, 'gen') || ...
        ~isfield(base, 'vsc') || ~isfield(target, 'vsc')
    error('make_vsc_hvdc_pac_dispatch_target: base and target must be MATPOWER cases with bus, gen and vsc fields');
end
same_size('bus', base.bus, target.bus);
same_size('gen', base.gen, target.gen);
same_size('vsc', base.vsc, target.vsc);
fixed_cols = [c.VSC_BUS c.BUSDC c.VSC_STATUS c.AC_MODE c.DC_MODE ...
    c.LOSS_A:c.REACTOR_RATE_C];
if any(any(base.vsc(:, fixed_cols) ~= target.vsc(:, fixed_cols)))
    error('make_vsc_hvdc_pac_dispatch_target: base and target VSC topology, modes and station data must match');
end


function same_size(name, a, b)
if size(a, 1) ~= size(b, 1) || size(a, 2) ~= size(b, 2)
    error('make_vsc_hvdc_pac_dispatch_target: base and target %s matrices must have the same size', name);
end


function mode = policy_mode(policy)
if ischar(policy)
    mode = lower(policy);
elseif isstruct(policy)
    if isfield(policy, 'policy')
        mode = lower(policy.policy);
    elseif isfield(policy, 'mode')
        mode = lower(policy.mode);
    else
        mode = 'constant';
    end
else
    error('make_vsc_hvdc_pac_dispatch_target: policy must be a string or struct');
end


function val = required_scalar_policy_field(policy, name, mode)
if ~isstruct(policy) || ~isfield(policy, name) || isempty(policy.(name))
    error('make_vsc_hvdc_pac_dispatch_target: policy ''%s'' requires %s', ...
        mode, upper(name));
end
val = policy.(name);
if ~isscalar(val) || ~isnumeric(val) || ~isfinite(val)
    error('make_vsc_hvdc_pac_dispatch_target: %s must be a finite scalar', ...
        upper(name));
end


function idx = selected_one_converter(policy, mpc, c, idx_fields, bus_fields)
idx = policy_first_field(policy, idx_fields);
if isempty(idx)
    buses = policy_first_field(policy, bus_fields);
    if isempty(buses)
        error('make_vsc_hvdc_pac_dispatch_target: pac_pair_transfer requires source and sink selectors');
    end
    idx = converter_indices_from_buses(mpc, c, buses);
end
idx = validate_converter_indices(idx, size(mpc.vsc, 1));
if length(idx) ~= 1
    error('make_vsc_hvdc_pac_dispatch_target: source and sink selectors must each identify exactly one converter');
end


function val = policy_first_field(policy, names)
val = [];
if ~isstruct(policy)
    return;
end
for kk = 1:length(names)
    if isfield(policy, names{kk}) && ~isempty(policy.(names{kk}))
        val = policy.(names{kk});
        return;
    end
end


function idx = converter_indices_from_buses(mpc, c, buses)
buses = buses(:);
idx = zeros(length(buses), 1);
for kk = 1:length(buses)
    row = find(mpc.vsc(:, c.VSC_BUS) == buses(kk), 1);
    if isempty(row)
        error('make_vsc_hvdc_pac_dispatch_target: no VSC converter at AC bus %g', buses(kk));
    end
    idx(kk) = row;
end


function idx = validate_converter_indices(idx, nv)
idx = idx(:);
if ~isnumeric(idx) || any(~isfinite(idx)) || any(idx < 1) || ...
        any(idx > nv) || any(idx ~= fix(idx))
    error('make_vsc_hvdc_pac_dispatch_target: converter indices are invalid');
end
if length(unique(idx)) ~= length(idx)
    error('make_vsc_hvdc_pac_dispatch_target: converter indices must be unique');
end


function validate_pac_schedule(mpc, idx, c)
active = find(mpc.vsc(:, c.VSC_STATUS) > 0);
if any(~ismember(idx, active))
    error('make_vsc_hvdc_pac_dispatch_target: scheduled converters must be in service');
end
valid_ac = mpc.vsc(idx, c.AC_MODE) == c.VSC_AC_PQ | ...
    mpc.vsc(idx, c.AC_MODE) == c.VSC_AC_PV;
if any(~valid_ac)
    error('make_vsc_hvdc_pac_dispatch_target: scheduled Pac converters must use VSC_AC_PQ or VSC_AC_PV');
end


function [idx, delta_qac] = reactive_delta(policy, mpc, c)
nv = size(mpc.vsc, 1);
idx = zeros(0, 1);
delta_qac = zeros(nv, 1);
if ~isstruct(policy)
    return;
end
dq = policy_first_field(policy, {'qac_delta', 'qac_deltas'});
if isempty(dq)
    return;
end
idx = policy_first_field(policy, {'qac_converters', ...
    'qac_converter_idx', 'qac_vsc', 'qac_vsc_idx'});
if isempty(idx)
    buses = policy_first_field(policy, {'qac_buses', 'qac_ac_buses', ...
        'qac_vsc_buses'});
    if ~isempty(buses)
        idx = converter_indices_from_buses(mpc, c, buses);
    end
end
dq = dq(:);
if isempty(idx) && length(dq) == nv
    idx = find(abs(dq) > 0);
    dq = dq(idx);
elseif isempty(idx)
    error('make_vsc_hvdc_pac_dispatch_target: QAC schedule requires qac converters or qac buses');
end
idx = validate_converter_indices(idx, nv);
if length(dq) ~= length(idx)
    error('make_vsc_hvdc_pac_dispatch_target: QAC deltas must match the QAC converter list');
end
delta_qac(idx) = dq;


function buses = converter_buses(mpc, idx, c)
if isempty(idx)
    buses = zeros(0, 1);
else
    buses = mpc.vsc(idx, c.VSC_BUS);
end


function txt = policy_text(policy, field, default)
txt = default;
if isstruct(policy) && isfield(policy, field) && ~isempty(policy.(field))
    txt = policy.(field);
end
