function [mpc_next, report] = enforce_vsc_capability_active_set(mpc, results, opt)
% enforce_vsc_capability_active_set - Applies TESIS-style VSC active set.
% ::
%
%   [MPC_NEXT, REPORT] = ENFORCE_VSC_CAPABILITY_ACTIVE_SET(MPC, RESULTS, OPT)
%
%   Checks the solved VSC P/Q point in RESULTS against each converter's
%   capability curve, then updates MPC_NEXT.VSC(:, AC_MODE/PAC_SET/QAC_SET)
%   for saturated converters. This is the active-set enforcement step for
%   TESIS-style solve-saturate-continue PF/CPF logic. It does not solve a PF
%   itself and does not add OPF constraints. Callers should re-solve MPC_NEXT
%   and repeat until REPORT shows no active-set changes.
%
%   OPT fields:
%       CAPABILITY_VSC_SMAX   scalar/vector/cell Smax fallback
%       CAPABILITY_VSC_VMAX   scalar/vector/cell Vmax fallback, default 1.15
%       CAPABILITY_VSC_MODE   scalar/vector/cell projection fallback
%
% See also vsc_capability_policy, vsc_capability_curve, runpf_vsc_mtdc.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 3 || isempty(opt)
    opt = struct();
end

c = idx_vsc;
mpc_next = mpc;
report = empty_report();

if ~isfield(mpc, 'vsc') || isempty(mpc.vsc) || ...
        ~isfield(results, 'vsc') || isempty(results.vsc)
    return;
end

active = find(mpc.vsc(:, c.VSC_STATUS) > 0);
tol = 1e-8;
for kk = 1:length(active)
    k = active(kk);
    if size(results.vsc, 1) < k || size(results.vsc, 2) < c.QAC
        continue;
    end
    P0 = results.vsc(k, c.PAC);
    Q0 = results.vsc(k, c.QAC);
    V0 = vsc_capability_voltage(results.vsc, mpc.vsc, k, c);
    params = vsc_capability_params(mpc, opt, k, kk);
    policy = vsc_capability_policy(mpc.vsc(k, :), ...
        struct('mode', params.mode), k, kk);

    try
        [sat, Psat, Qsat, Ssat, info] = vsc_capability_curve( ...
            P0, Q0, params.Smax, V0, results.vsc(k, :), ...
            policy.projection_mode, params.Vmax, results.baseMVA);
    catch me
        error('enforce_vsc_capability_active_set: VSC row %d capability evaluation failed: %s', ...
            k, me.message);
    end
    if ~sat
        continue;
    end

    from_mode = mpc.vsc(k, c.AC_MODE);
    to_mode = target_ac_mode(policy, P0, Psat, tol);
    old_vals = mpc.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]);
    new_vals = [to_mode Psat Qsat];
    changed = any(abs(old_vals - new_vals) > tol);
    if changed
        mpc_next.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]) = new_vals;
    end
    report = append_report(report, k, from_mode, to_mode, P0, Q0, V0, ...
        Psat, Qsat, Ssat, info, policy, params, changed);
end

report.changed = any(report.changed_idx);
report.violations = length(report.saturated_idx);


function report = empty_report()
report = struct( ...
    'type',                         'vsc_capability_active_set', ...
    'changed',                      0, ...
    'changed_idx',                  [], ...
    'saturated_idx',                [], ...
    'unchanged_saturated_idx',      [], ...
    'from_mode',                    [], ...
    'to_mode',                      [], ...
    'active_limit',                 {{}}, ...
    'projection_mode',              {{}}, ...
    'policy_reason',                {{}}, ...
    'target_ac_mode_if_saturated',  [], ...
    'P_candidate',                  [], ...
    'Q_candidate',                  [], ...
    'V_candidate',                  [], ...
    'P_projected',                  [], ...
    'Q_projected',                  [], ...
    'S_projected',                  [], ...
    'margin_candidate',             [], ...
    'Smax',                         [], ...
    'Vmax',                         [], ...
    'Smax_source',                  {{}}, ...
    'Vmax_source',                  {{}}, ...
    'mode_source',                  {{}}, ...
    'violations',                   0 );


function report = append_report(report, k, from_mode, to_mode, P0, Q0, V0, ...
        Psat, Qsat, Ssat, info, policy, params, changed)
if changed
    report.changed_idx(end+1, 1) = k;
else
    report.unchanged_saturated_idx(end+1, 1) = k;
end
report.saturated_idx(end+1, 1) = k;
report.from_mode(end+1, 1) = from_mode;
report.to_mode(end+1, 1) = to_mode;
report.active_limit{end+1, 1} = info.active_limit;
report.projection_mode{end+1, 1} = info.mode;
report.policy_reason{end+1, 1} = policy.reason;
report.target_ac_mode_if_saturated(end+1, 1) = ...
    policy.target_ac_mode_if_saturated;
report.P_candidate(end+1, 1) = P0;
report.Q_candidate(end+1, 1) = Q0;
report.V_candidate(end+1, 1) = V0;
report.P_projected(end+1, 1) = Psat;
report.Q_projected(end+1, 1) = Qsat;
report.S_projected(end+1, 1) = Ssat;
report.margin_candidate(end+1, 1) = info.margin;
report.Smax(end+1, 1) = info.Smax;
report.Vmax(end+1, 1) = info.Vmax;
report.Smax_source{end+1, 1} = params.Smax_source;
report.Vmax_source{end+1, 1} = params.Vmax_source;
report.mode_source{end+1, 1} = params.mode_source;


function mode = target_ac_mode(policy, P0, Psat, tol)
if abs(Psat - P0) > tol
    mode = policy.target_ac_mode_if_p_changed;
else
    mode = policy.target_ac_mode_if_p_preserved;
end


function V = vsc_capability_voltage(vsc_result, vsc_control, row, c)
if size(vsc_result, 2) >= c.VAC_PCC && ...
        isfinite(vsc_result(row, c.VAC_PCC)) && ...
        vsc_result(row, c.VAC_PCC) > 0
    V = vsc_result(row, c.VAC_PCC);
elseif size(vsc_result, 2) >= c.VAC_INTERNAL && ...
        isfinite(vsc_result(row, c.VAC_INTERNAL)) && ...
        vsc_result(row, c.VAC_INTERNAL) > 0
    V = vsc_result(row, c.VAC_INTERNAL);
else
    V = vsc_control(row, c.VAC_SET);
end
