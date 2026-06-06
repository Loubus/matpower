function [sat, P, Q, S, info] = ...
        vsc_capability_geometry(P, Q, Smax, V, xEq, mode, Vmax)
% vsc_capability_geometry - Geometric post-solve P-Q capability for VSCs.
% ::
%
%   [SAT, P, Q, S, INFO] = VSC_CAPABILITY_GEOMETRY(P0, Q0, SMAX, V, XEQ)
%   [SAT, P, Q, S, INFO] = VSC_CAPABILITY_GEOMETRY(..., MODE, VMAX)
%
%   Evaluates the VSC admissible region used by the TESIS post-solve
%   saturation layer as the intersection of:
%
%       |P| <= SMAX
%       P^2 + Q^2 <= (V*SMAX)^2
%       P^2 + (Q + V^2*SMAX/XL)^2 <= (V*VMAX*SMAX/XL)^2
%
%   where XL = SMAX * XEQ. P, Q and SMAX must use the same normalized base.
%   Use VSC_CAPABILITY_CURVE for MATPOWER result values in MW/MVAr.
%
%   MODE = 'radial' scales (P,Q), preserving power factor.
%   MODE = 'preservar_p' preserves P when a feasible Q interval exists.
%
%   VSCs can inject or absorb active power, so both P > 0 and P < 0 are
%   allowed.
%
%   This is a geometric projection for PF/CPF audit and active-set
%   enforcement. It is not OPF constraint construction.
%
% See also vsc_capability_curve, check_vsc_capability.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 6 || isempty(mode)
    mode = 'radial';
end
if nargin < 7 || isempty(Vmax)
    Vmax = 1.15;
end

validate_inputs(P, Q, Smax, V, xEq, Vmax);

Pin = P;
Qin = Q;
tol = 1e-10;
margin = 1 - 10 * eps;
mode = normalize_mode(mode);

[pMax, iMax, qCenter, vRadius] = capability_params(Smax, V, xEq, Vmax, tol);
inside0 = inside_capability(P, Q, pMax, iMax, qCenter, vRadius, tol);
sat = ~inside0;
violated = violated_limits(P, Q, pMax, iMax, qCenter, vRadius, tol);
alpha = NaN;

if sat
    switch mode
        case 'radial'
            alpha = radial_scale(P, Q, pMax, iMax, qCenter, vRadius);
            P = alpha * P;
            Q = alpha * Q;
        case 'preservar_p'
            [P, Q] = preserve_p_projection(P, Q, pMax, iMax, ...
                qCenter, vRadius, margin);
        otherwise
            error('vsc_capability_geometry: mode must be radial or preservar_p');
    end
else
    alpha = 1;
end

S = abs(P + 1j * Q);
[qMin, qMax] = q_interval(P, iMax, qCenter, vRadius);
delta = hypot(P - Pin, Q - Qin);

info = struct( ...
    'kind',             'vsc', ...
    'mode',             mode, ...
    'Smax',             Smax, ...
    'V',                V, ...
    'Vmax',             Vmax, ...
    'xEq',              abs(xEq), ...
    'P_original',       Pin, ...
    'Q_original',       Qin, ...
    'S_original',       abs(Pin + 1j * Qin), ...
    'P',                P, ...
    'Q',                Q, ...
    'S',                S, ...
    'sat',              sat, ...
    'saturaP',          abs(P - Pin) > tol, ...
    'saturaQ',          abs(Q - Qin) > tol, ...
    'inside_original',  inside0, ...
    'inside_final',     inside_capability(P, Q, pMax, iMax, ...
                            qCenter, vRadius, tol), ...
    'active_limit',     limit_label(violated), ...
    'violated_p',       limit_present(violated, 'p'), ...
    'violated_current', limit_present(violated, 'current'), ...
    'violated_voltage', limit_present(violated, 'voltage_internal'), ...
    'q_on_limit',       q_on_limit(P, Q, iMax, qCenter, vRadius), ...
    'qMin',             qMin, ...
    'qMax',             qMax, ...
    'pFactible',        feasible_p(pMax, iMax, qCenter, vRadius), ...
    'pMax',             pMax, ...
    'iMax',             iMax, ...
    'qCenter',          qCenter, ...
    'vRadius',          vRadius, ...
    'margin',           min_capability_margin(Pin, Qin, pMax, iMax, ...
                            qCenter, vRadius), ...
    'projection_norm',  delta, ...
    'radial_scale',     alpha );


function validate_inputs(P, Q, Smax, V, xEq, Vmax)
if isempty(P) || ~isscalar(P) || ~isnumeric(P) || ~isfinite(P) || ...
        isempty(Q) || ~isscalar(Q) || ~isnumeric(Q) || ~isfinite(Q)
    error('vsc_capability_geometry: P and Q must be finite numeric scalars');
end
if isempty(Smax) || ~isscalar(Smax) || ~isnumeric(Smax) || ...
        ~isfinite(Smax) || Smax <= 0
    error('vsc_capability_geometry: Smax must be a positive finite scalar');
end
if isempty(V) || ~isscalar(V) || ~isnumeric(V) || ~isfinite(V) || V <= 0
    error('vsc_capability_geometry: V must be a positive finite scalar');
end
if isempty(xEq) || ~isscalar(xEq) || ~isnumeric(xEq) || ...
        ~isfinite(xEq) || abs(xEq) < 0
    error('vsc_capability_geometry: xEq must be a finite numeric scalar');
end
if isempty(Vmax) || ~isscalar(Vmax) || ~isnumeric(Vmax) || ...
        ~isfinite(Vmax) || Vmax <= 0
    error('vsc_capability_geometry: Vmax must be a positive finite scalar');
end


function mode = normalize_mode(mode)
mode = lower(strrep(char(mode), '_', '-'));
switch mode
    case {'radial', 'factor-potencia', 'fp'}
        mode = 'radial';
    case {'preservar-p', 'preservar_p', 'preserve-p', 'preserve_p', ...
            'droop', 'slack'}
        mode = 'preservar_p';
end


function [pMax, iMax, qCenter, vRadius] = ...
        capability_params(Smax, V, xEq, Vmax, tol)
xEq = abs(xEq);
pMax = Smax;
iMax = V * Smax;
if xEq > tol
    XL = Smax * xEq;
    qCenter = V^2 * Smax / XL;
    vRadius = V * Vmax * Smax / XL;
else
    qCenter = 0;
    vRadius = Inf;
end


function inside = inside_capability(P, Q, pMax, iMax, qCenter, vRadius, tol)
inside = abs(P) <= pMax + tol && P^2 + Q^2 <= iMax^2 + tol;
if isfinite(vRadius)
    inside = inside && P^2 + (Q + qCenter)^2 <= vRadius^2 + tol;
end


function labels = violated_limits(P, Q, pMax, iMax, qCenter, vRadius, tol)
labels = {};
if abs(P) > pMax + tol
    labels{end+1} = 'p';
end
if hypot(P, Q) > iMax + tol
    labels{end+1} = 'current';
end
if isfinite(vRadius) && hypot(P, Q + qCenter) > vRadius + tol
    labels{end+1} = 'voltage_internal';
end


function label = limit_label(labels)
if isempty(labels)
    label = 'none';
else
    label = sprintf('%s+', labels{:});
    label = label(1:end-1);
end


function present = limit_present(labels, name)
present = 0;
for kk = 1:length(labels)
    if strcmp(labels{kk}, name)
        present = 1;
        return;
    end
end


function alpha = radial_scale(P, Q, pMax, iMax, qCenter, vRadius)
tol = 1e-12;
normPQ = hypot(P, Q);

if normPQ <= tol
    alpha = 1;
    return;
end

alpha = 1;
if abs(P) > tol
    alpha = min(alpha, pMax / abs(P));
end
alpha = min(alpha, iMax / normPQ);

if isfinite(vRadius)
    a = normPQ^2;
    b = 2 * Q * qCenter;
    cc = qCenter^2 - vRadius^2;
    disc = max(0, b^2 - 4 * a * cc);
    alpha = min(alpha, (-b + sqrt(disc)) / (2 * a));
end

alpha = max(0, min(1, alpha));


function [P, Q] = preserve_p_projection(P, Q, pMax, iMax, ...
        qCenter, vRadius, margin)
pFeas = feasible_p(pMax, iMax, qCenter, vRadius);
if abs(P) > pFeas || ~valid_q_interval(P, iMax, qCenter, vRadius)
    P = nonzero_sign(P) * pFeas * margin;
end

[qMin, qMax] = q_interval(P, iMax, qCenter, vRadius);
if qMin > qMax
    error('vsc_capability_geometry: VSC capability region is infeasible');
end
Q = min(max(Q, qMin), qMax);


function pFeas = feasible_p(pMax, iMax, qCenter, vRadius)
pHi = min(pMax, iMax);
if isfinite(vRadius)
    pHi = min(pHi, vRadius);
end
if valid_q_interval(pHi, iMax, qCenter, vRadius)
    pFeas = pHi;
    return;
end

pLo = 0;
if ~valid_q_interval(pLo, iMax, qCenter, vRadius)
    pFeas = 0;
    return;
end

for kk = 1:60
    pMid = 0.5 * (pLo + pHi);
    if valid_q_interval(pMid, iMax, qCenter, vRadius)
        pLo = pMid;
    else
        pHi = pMid;
    end
end
pFeas = pLo;


function valid = valid_q_interval(P, iMax, qCenter, vRadius)
[qMin, qMax] = q_interval(P, iMax, qCenter, vRadius);
valid = qMin <= qMax;


function [qMin, qMax] = q_interval(P, iMax, qCenter, vRadius)
qI = sqrt(max(0, iMax.^2 - P.^2));
qMin = -qI;
qMax = qI;
if isfinite(vRadius)
    qV = sqrt(max(0, vRadius.^2 - P.^2));
    qMin = max(qMin, -qCenter - qV);
    qMax = min(qMax, -qCenter + qV);
end


function on_limit = q_on_limit(P, Q, iMax, qCenter, vRadius)
[qMin, qMax] = q_interval(P, iMax, qCenter, vRadius);
tol = 1e-7;
on_limit = abs(Q - qMin) <= tol || abs(Q - qMax) <= tol;


function m = min_capability_margin(P, Q, pMax, iMax, qCenter, vRadius)
m = min(pMax - abs(P), iMax - hypot(P, Q));
if isfinite(vRadius)
    m = min(m, vRadius - hypot(P, Q + qCenter));
end


function s = nonzero_sign(x)
if x < 0
    s = -1;
else
    s = 1;
end
