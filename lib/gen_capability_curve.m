function [sat, P, Q, S, info] = gen_capability_curve(P, Q, Smax, type)
% gen_capability_curve - Generic post-solve P-Q capability curve for generators.
% ::
%
%   [SAT, P, Q, S, INFO] = GEN_CAPABILITY_CURVE(P0, Q0, SMAX, TYPE)
%
%   Evaluates a conventional generator operating point against the same
%   generic curves used by the TESIS capabilidad layer. The calculation is
%   performed internally in p.u. on the generator apparent-power base SMAX.
%   Inputs and outputs remain in MW/MVAr/MVA. If the point is outside the
%   curve, the returned P and/or Q are projected to the curve boundary.
%   P < 0 is treated as motor operation and is saturated to P = 0.
%
%   TYPE can be 1/'hydraulic'/'hidraulico', 2/'thermal'/'termico'/'default',
%   or 3/'wind'/'eolico'. Unknown or empty types use the thermal curve.
%
%   This helper is independent of OPF data and does not modify a MATPOWER
%   case or result struct.
%
% See also check_gen_capability, check_capability_limits.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

validate_inputs(P, Q, Smax);

Pin = P;
Qin = Q;
Sbase = Smax;
Ppu0 = Pin / Sbase;
Qpu0 = Qin / Sbase;
Ppu = Ppu0;
Qpu = Qpu0;
type0 = type;
type = normalize_gen_type(type);
[curve_pu, type_name] = generic_curve(1, type);
curve = curve_pu;

sat = 0;
active_limit = 'none';

if type == 1 || type == 2
    PA = curve.PA; QA = curve.QA;
    PB = curve.PB; QB = curve.QB;
    PC = curve.PC; QC = curve.QC;
    PD = curve.PD; QD = curve.QD;
    QE = curve.QE;

    q0 = (QA^2 - PB^2 - QB^2) / (2 * QA - 2 * QB);
    s0 = QA - q0;

    if Ppu < PA
        Ppu = PA;
        Qpu = min(max(Qpu, QE), QA);
        sat = 1;
        active_limit = 'p_min';
    elseif Qpu > sqrt(max(0, s0^2 - Ppu^2)) + q0 && Ppu < PB
        Qpu = sqrt(max(0, s0^2 - Ppu^2)) + q0;
        sat = 1;
        active_limit = 'overexcited_arc';
    elseif Qpu >= QB && Ppu >= PB
        Ppu = PB;
        Qpu = QB;
        sat = 1;
        active_limit = 'overexcited_corner';
    elseif Ppu > PB && Qpu < QB && Qpu > QC
        Ppu = PB;
        sat = 1;
        active_limit = 'p_max';
    elseif Ppu >= PC && Qpu <= QC
        Ppu = PC;
        Qpu = QC;
        sat = 1;
        active_limit = 'underexcited_corner';
    elseif Qpu < ((QC - QD) / (PC - PD)) * (Ppu - PD) + QD && ...
            Ppu > PD && Ppu < PC
        Qpu = ((QC - QD) / (PC - PD)) * (Ppu - PD) + QD;
        sat = 1;
        active_limit = 'underexcited_line';
    elseif Qpu <= QE && Ppu <= PD
        Qpu = QE;
        sat = 1;
        active_limit = 'underexcited_qmin';
    end
else
    PA = curve.PA; QA = curve.QA;
    PB = curve.PB; QB = curve.QB;
    PC = curve.PC; QC = curve.QC;

    if Ppu < PA
        Ppu = PA;
        Qpu = QA;
        sat = 1;
        active_limit = 'p_min';
    elseif Ppu <= PB
        qlim = (QB - QA) / (PB - PA) * Ppu;
        if Qpu > qlim
            Qpu = qlim;
            sat = 1;
            active_limit = 'low_p_qmax';
        elseif Qpu < -qlim
            Qpu = -qlim;
            sat = 1;
            active_limit = 'low_p_qmin';
        end
    elseif Ppu <= PC
        if Qpu > QB
            Qpu = QB;
            sat = 1;
            active_limit = 'qmax';
        elseif Qpu < -QB
            Qpu = -QB;
            sat = 1;
            active_limit = 'qmin';
        end
    else
        Ppu = PC;
        Qpu = min(max(Qpu, -QC), QC);
        sat = 1;
        active_limit = 'p_max';
    end
end

P = Ppu * Sbase;
Q = Qpu * Sbase;
S = abs(P + 1j * Q);
delta = hypot(P - Pin, Q - Qin);
delta_pu = hypot(Ppu - Ppu0, Qpu - Qpu0);
curve = scale_curve(curve_pu, Sbase);

info = struct( ...
    'kind',             'gen', ...
    'mode',             'post_solve_projection', ...
    'gen_type',         type_name, ...
    'gen_type_code',    type, ...
    'gen_type_input',   type0, ...
    'Smax',             Smax, ...
    'element_base_mva', Sbase, ...
    'per_unit_base',    'element', ...
    'P_original',       Pin, ...
    'Q_original',       Qin, ...
    'S_original',       abs(Pin + 1j * Qin), ...
    'P_original_pu',    Ppu0, ...
    'Q_original_pu',    Qpu0, ...
    'S_original_pu',    abs(Ppu0 + 1j * Qpu0), ...
    'P',                P, ...
    'Q',                Q, ...
    'S',                S, ...
    'P_pu',             Ppu, ...
    'Q_pu',             Qpu, ...
    'S_pu',             abs(Ppu + 1j * Qpu), ...
    'Smax_pu',          1, ...
    'sat',              sat, ...
    'saturaP',          abs(P - Pin) > 1e-10, ...
    'saturaQ',          abs(Q - Qin) > 1e-10, ...
    'active_limit',     active_limit, ...
    'margin',           signed_margin(sat, delta), ...
    'margin_pu',        signed_margin(sat, delta_pu), ...
    'projection_norm',  delta, ...
    'projection_norm_pu', delta_pu, ...
    'curve',            curve, ...
    'curve_pu',         curve_pu );


function validate_inputs(P, Q, Smax)
if isempty(P) || ~isscalar(P) || ~isnumeric(P) || ~isfinite(P) || ...
        isempty(Q) || ~isscalar(Q) || ~isnumeric(Q) || ~isfinite(Q)
    error('gen_capability_curve: P and Q must be finite numeric scalars');
end
if isempty(Smax) || ~isscalar(Smax) || ~isnumeric(Smax) || ...
        ~isfinite(Smax) || Smax <= 0
    error('gen_capability_curve: Smax must be a positive finite scalar');
end


function type = normalize_gen_type(type)
if nargin < 1 || isempty(type)
    type = 2;
    return;
end
if isnumeric(type)
    if ~isscalar(type) || ~isfinite(type) || ~ismember(type, [1 2 3])
        type = 2;
    end
    return;
end
if ischar(type)
    key = lower(strrep(type, '_', '-'));
    switch key
        case {'hydraulic', 'hydro', 'hidraulico', 'hidraulica'}
            type = 1;
        case {'thermal', 'termico', 'termica', 'default'}
            type = 2;
        case {'wind', 'eolico', 'eolica'}
            type = 3;
        otherwise
            type = 2;
    end
else
    type = 2;
end


function [curve, name] = generic_curve(Smax, type)
if type == 1
    name = 'hydraulic';
    curve = struct( ...
        'PA', 0,            'QA', 0.75 * Smax, ...
        'PB', 0.85 * Smax,  'QB', 0.55 * Smax, ...
        'PC', 0.85 * Smax,  'QC', -0.45 * Smax, ...
        'PD', 0.25 * Smax,  'QD', -0.85 * Smax, ...
        'QE', -0.85 * Smax );
elseif type == 3
    name = 'wind';
    curve = struct( ...
        'PA', 0,            'QA', 0, ...
        'PB', 0.15 * Smax,  'QB', 0.25 * Smax, ...
        'PC', 0.80 * Smax,  'QC', 0.25 * Smax );
else
    name = 'thermal';
    curve = struct( ...
        'PA', 0,            'QA', 0.8 * Smax, ...
        'PB', 0.8 * Smax,   'QB', 0.6 * Smax, ...
        'PC', 0.8 * Smax,   'QC', -0.2 * Smax, ...
        'PD', 0.15 * Smax,  'QD', -0.45 * Smax, ...
        'QE', -0.45 * Smax );
end


function curve = scale_curve(curve, Sbase)
names = fieldnames(curve);
for kk = 1:length(names)
    curve.(names{kk}) = curve.(names{kk}) * Sbase;
end


function m = signed_margin(sat, delta)
if sat
    m = -delta;
else
    m = delta;
end
