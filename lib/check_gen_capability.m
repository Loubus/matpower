function report = check_gen_capability(results, opt)
% check_gen_capability - Audits conventional generator P-Q capability curves.
% ::
%
%   REPORT = CHECK_GEN_CAPABILITY(RESULTS)
%   REPORT = CHECK_GEN_CAPABILITY(RESULTS, OPT)
%
%   Evaluates in-service conventional generators after a PF/CPF solution
%   without modifying RESULTS. This is a post-solve saturation audit, not OPF
%   constraint enforcement. Generators connected to REF buses are treated as
%   slack resources and are exempt from saturation. The default generator curve
%   is thermal unless OPT.GEN_TYPE supplies a scalar, vector or cell array of
%   types accepted by GEN_CAPABILITY_CURVE.
%
%   Optional OPT fields:
%       GEN_IDX   selected generator rows, default all in-service generators
%       GEN_TYPE  scalar/vector/cell generator type, default thermal
%       GEN_SMAX  scalar/vector apparent-power base, default MBASE/baseMVA
%
% See also gen_capability_curve, check_capability_limits.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 2 || isempty(opt)
    opt = struct();
end
mpc = loadcase(results);

[~, ~, REF, ~, BUS_I, BUS_TYPE] = idx_bus;
[GEN_BUS, PG, QG, ~, ~, ~, MBASE, GEN_STATUS] = idx_gen;
ng = size(mpc.gen, 1);
elements = repmat(empty_element(), 0, 1);

if ng == 0
    report = build_report(elements);
    return;
end

idx = selected_generators(mpc, opt, GEN_STATUS);
elements = repmat(empty_element(), length(idx), 1);
for kk = 1:length(idx)
    g = idx(kk);
    P0 = mpc.gen(g, PG);
    Q0 = mpc.gen(g, QG);
    Smax = option_value(opt, 'gen_smax', g, kk, default_smax(mpc, g, MBASE));
    type = option_value(opt, 'gen_type', g, kk, 2);
    if is_slack_generator(mpc, g, GEN_BUS, BUS_I, BUS_TYPE, REF)
        [sat, Psat, Qsat, Ssat, info] = ...
            slack_exempt_info(P0, Q0, Smax, type);
    else
        [sat, Psat, Qsat, Ssat, info] = ...
            gen_capability_curve(P0, Q0, Smax, type);
    end
    elements(kk) = struct( ...
        'type',          'gen', ...
        'idx',           g, ...
        'bus',           mpc.gen(g, GEN_BUS), ...
        'status',        mpc.gen(g, GEN_STATUS), ...
        'P',             P0, ...
        'Q',             Q0, ...
        'S',             abs(P0 + 1j * Q0), ...
        'P_saturated',   Psat, ...
        'Q_saturated',   Qsat, ...
        'S_saturated',   Ssat, ...
        'sat',           sat, ...
        'active_limit',  info.active_limit, ...
        'margin',        info.margin, ...
        'mode',          info.mode, ...
        'info',          info );
end
report = build_report(elements);


function idx = selected_generators(mpc, opt, GEN_STATUS)
ng = size(mpc.gen, 1);
if isfield(opt, 'gen_idx') && ~isempty(opt.gen_idx)
    idx = opt.gen_idx(:);
    if ~isnumeric(idx) || any(~isfinite(idx)) || any(idx < 1) || ...
            any(idx > ng) || any(idx ~= fix(idx))
        error('check_gen_capability: generator indices are invalid');
    end
else
    idx = find(mpc.gen(:, GEN_STATUS) > 0 & ~isload(mpc.gen));
end


function Smax = default_smax(mpc, g, MBASE)
Smax = mpc.gen(g, MBASE);
if ~isfinite(Smax) || Smax <= 0
    Smax = mpc.baseMVA;
end


function TorF = is_slack_generator(mpc, g, GEN_BUS, BUS_I, BUS_TYPE, REF)
row = find(mpc.bus(:, BUS_I) == mpc.gen(g, GEN_BUS), 1);
TorF = ~isempty(row) && mpc.bus(row, BUS_TYPE) == REF;


function [sat, P, Q, S, info] = slack_exempt_info(P, Q, Smax, type)
sat = 0;
S = abs(P + 1j * Q);
info = struct( ...
    'kind',             'gen', ...
    'mode',             'slack_exempt', ...
    'gen_type',         'slack_exempt', ...
    'gen_type_code',    type, ...
    'gen_type_input',   type, ...
    'Smax',             Smax, ...
    'P_original',       P, ...
    'Q_original',       Q, ...
    'S_original',       S, ...
    'P',                P, ...
    'Q',                Q, ...
    'S',                S, ...
    'sat',              sat, ...
    'saturaP',          0, ...
    'saturaQ',          0, ...
    'active_limit',     'slack_exempt', ...
    'margin',           Inf, ...
    'projection_norm',  0, ...
    'curve',            struct() );


function val = option_value(opt, name, g, kk, default)
val = default;
if ~isfield(opt, name) || isempty(opt.(name))
    return;
end
raw = opt.(name);
if iscell(raw)
    if isscalar(raw)
        val = raw{1};
    elseif numel(raw) >= g
        val = raw{g};
    elseif numel(raw) >= kk
        val = raw{kk};
    else
        error('check_gen_capability: option %s has invalid length', name);
    end
elseif isnumeric(raw)
    if isscalar(raw)
        val = raw;
    elseif numel(raw) >= g
        val = raw(g);
    elseif numel(raw) >= kk
        val = raw(kk);
    else
        error('check_gen_capability: option %s has invalid length', name);
    end
else
    val = raw;
end


function report = build_report(elements)
sat = zeros(length(elements), 1);
for kk = 1:length(elements)
    sat(kk) = elements(kk).sat;
end
report = struct( ...
    'type',        'gen', ...
    'count',       length(elements), ...
    'violations',  sum(sat), ...
    'elements',    elements );


function e = empty_element()
e = struct( ...
    'type',          '', ...
    'idx',           [], ...
    'bus',           [], ...
    'status',        [], ...
    'P',             [], ...
    'Q',             [], ...
    'S',             [], ...
    'P_saturated',   [], ...
    'Q_saturated',   [], ...
    'S_saturated',   [], ...
    'sat',           [], ...
    'active_limit',  '', ...
    'margin',        [], ...
    'mode',          '', ...
    'info',          struct() );
