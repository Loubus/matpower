function [target, dispatch] = make_cpf_gen_dispatch_target(base, target, policy)
% make_cpf_gen_dispatch_target - Builds CPF targets with generator redispatch.
% ::
%
%   TARGET = MAKE_CPF_GEN_DISPATCH_TARGET(BASE, TARGET, POLICY)
%   [TARGET, DISPATCH] = MAKE_CPF_GEN_DISPATCH_TARGET(...)
%
%   Applies a scheduled active-power generator redispatch policy to a CPF
%   target case. This helper is independent of VSC/HVDC data and only
%   modifies TARGET.GEN(:, PG). It does not solve an OPF, enforce PMIN/PMAX,
%   or apply AGC/saturation logic.
%
%   POLICY can be a string or a struct with a POLICY or MODE field:
%
%       'preserve' or 'target'
%           Leaves TARGET.GEN(:, PG) unchanged.
%
%       'constant'
%           Copies BASE.GEN(:, PG) to TARGET.GEN(:, PG).
%
%       'participation'
%           Copies BASE.GEN(:, PG) to TARGET.GEN(:, PG), then applies a
%           scheduled active-power amount to selected generators. Select
%           generators with POLICY.GENS or POLICY.GEN_BUSES and optionally
%           set POLICY.WEIGHTS. The amount is either POLICY.AMOUNT_MW, or
%           POLICY.LOAD_SHARE times the total active load increment.
%
% See also runcpf, idx_gen, idx_bus.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 3 || isempty(policy)
    policy = 'preserve';
end

base = loadcase(base);
target = loadcase(target);

[~, ~, PD] = idx_bus;
[GEN_BUS, PG, ~, ~, ~, ~, ~, GEN_STATUS] = idx_gen;

validate_cases(base, target);

mode = policy_mode(policy);
ng = size(base.gen, 1);
delta_pd = sum(target.bus(:, PD) - base.bus(:, PD));
amount_mw = 0;
load_share = 0;
gen_idx = zeros(0, 1);
weights = zeros(0, 1);

switch mode
    case {'preserve', 'target'}
        delta_pg = target.gen(:, PG) - base.gen(:, PG);
        amount_mw = sum(delta_pg);
    case 'constant'
        target.gen(:, PG) = base.gen(:, PG);
        delta_pg = zeros(ng, 1);
    case 'participation'
        gen_idx = selected_generators(policy, base, GEN_BUS, GEN_STATUS);
        weights = normalized_weights(policy, length(gen_idx));
        [amount_mw, load_share] = dispatch_amount(policy, delta_pd);

        delta_pg = zeros(ng, 1);
        delta_pg(gen_idx) = amount_mw * weights;
        target.gen(:, PG) = base.gen(:, PG) + delta_pg;
    otherwise
        error('make_cpf_gen_dispatch_target: unknown policy ''%s''', mode);
end

affected = find(abs(delta_pg) > 0);
dispatch = struct( ...
    'policy',              mode, ...
    'delta_pd',            delta_pd, ...
    'load_share',          load_share, ...
    'amount_mw',           amount_mw, ...
    'weights_used',        weights(:), ...
    'gen_idx',             gen_idx(:), ...
    'gen_buses',           base.gen(gen_idx, GEN_BUS), ...
    'delta_pg',            delta_pg, ...
    'target_pg',           target.gen(:, PG), ...
    'affected_generators', affected(:), ...
    'affected_buses',      base.gen(affected, GEN_BUS) );


function validate_cases(base, target)
[GEN_BUS, ~, ~, ~, ~, ~, ~, GEN_STATUS] = idx_gen;
[~, ~, ~, ~, BUS_I] = idx_bus;
if ~isfield(base, 'bus') || ~isfield(target, 'bus') || ...
        ~isfield(base, 'gen') || ~isfield(target, 'gen')
    error('make_cpf_gen_dispatch_target: base and target must be MATPOWER cases with bus and gen fields');
end
same_size('bus', base.bus, target.bus);
same_size('gen', base.gen, target.gen);
if base.baseMVA ~= target.baseMVA
    error('make_cpf_gen_dispatch_target: base and target baseMVA values must match');
end
if any(base.bus(:, BUS_I) ~= target.bus(:, BUS_I))
    error('make_cpf_gen_dispatch_target: base and target bus numbers must match');
end
if any(base.gen(:, GEN_BUS) ~= target.gen(:, GEN_BUS)) || ...
        any(base.gen(:, GEN_STATUS) ~= target.gen(:, GEN_STATUS))
    error('make_cpf_gen_dispatch_target: base and target generator buses/statuses must match');
end


function same_size(name, a, b)
if size(a, 1) ~= size(b, 1) || size(a, 2) ~= size(b, 2)
    error('make_cpf_gen_dispatch_target: base and target %s matrices must have the same size', name);
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
        mode = 'preserve';
    end
else
    error('make_cpf_gen_dispatch_target: policy must be a string or struct');
end


function idx = selected_generators(policy, mpc, GEN_BUS, GEN_STATUS)
idx = policy_first_field(policy, {'gens', 'gen_idx', 'generators'});
if isempty(idx)
    buses = policy_first_field(policy, {'gen_buses', 'buses'});
    if isempty(buses)
        error('make_cpf_gen_dispatch_target: participation policy requires gens or gen_buses');
    end
    idx = generator_indices_from_buses(mpc, buses, GEN_BUS, GEN_STATUS);
end
idx = validate_generator_indices(idx, mpc, GEN_STATUS);


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


function idx = generator_indices_from_buses(mpc, buses, GEN_BUS, GEN_STATUS)
buses = buses(:);
idx = zeros(length(buses), 1);
is_load = isload(mpc.gen);
for kk = 1:length(buses)
    rows = find(mpc.gen(:, GEN_BUS) == buses(kk) & ...
        mpc.gen(:, GEN_STATUS) > 0 & ~is_load);
    if isempty(rows)
        error('make_cpf_gen_dispatch_target: no in-service generator at bus %g', buses(kk));
    elseif length(rows) > 1
        error('make_cpf_gen_dispatch_target: multiple generators at bus %g; use gens instead', buses(kk));
    end
    idx(kk) = rows;
end


function idx = validate_generator_indices(idx, mpc, GEN_STATUS)
idx = idx(:);
ng = size(mpc.gen, 1);
if ~isnumeric(idx) || any(~isfinite(idx)) || any(idx < 1) || ...
        any(idx > ng) || any(idx ~= fix(idx))
    error('make_cpf_gen_dispatch_target: generator indices are invalid');
end
if length(unique(idx)) ~= length(idx)
    error('make_cpf_gen_dispatch_target: generator indices must be unique');
end
if any(mpc.gen(idx, GEN_STATUS) <= 0)
    error('make_cpf_gen_dispatch_target: scheduled generators must be in service');
end
if any(isload(mpc.gen(idx, :)))
    error('make_cpf_gen_dispatch_target: scheduled rows must be generators, not dispatchable loads');
end


function w = normalized_weights(policy, n)
w = policy_first_field(policy, {'weights', 'weight'});
if isempty(w)
    w = ones(n, 1);
else
    w = w(:);
end
if length(w) ~= n || ~isnumeric(w) || any(~isfinite(w)) || any(w < 0) || ...
        sum(w) <= 0
    error('make_cpf_gen_dispatch_target: weights must be non-negative and match the generator list');
end
w = w / sum(w);


function [amount_mw, load_share] = dispatch_amount(policy, delta_pd)
amount = policy_first_field(policy, {'amount_mw', 'amount', 'delta_mw'});
share = policy_first_field(policy, {'load_share', 'share'});
if ~isempty(amount)
    if ~isscalar(amount) || ~isnumeric(amount) || ~isfinite(amount)
        error('make_cpf_gen_dispatch_target: amount_mw must be a finite scalar');
    end
    amount_mw = amount;
    load_share = 0;
elseif ~isempty(share)
    if ~isscalar(share) || ~isnumeric(share) || ~isfinite(share)
        error('make_cpf_gen_dispatch_target: load_share must be a finite scalar');
    end
    load_share = share;
    amount_mw = load_share * delta_pd;
else
    error('make_cpf_gen_dispatch_target: participation policy requires amount_mw or load_share');
end
