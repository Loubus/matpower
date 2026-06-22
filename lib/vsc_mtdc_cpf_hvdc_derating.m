function varargout = vsc_mtdc_cpf_hvdc_derating(op, varargin)
%VSC_MTDC_CPF_HVDC_DERATING HVDC derating CPF report/event utilities.

switch lower(op)
    case 'empty_report'
        varargout{1} = empty_report(varargin{:});
    case 'utilization_report'
        varargout{1} = utilization_report(varargin{:});
    case 'copy_utilization_report'
        varargout{1} = copy_utilization_report(varargin{:});
    case 'backoff_lambda'
        varargout{1} = backoff_lambda(varargin{:});
    case 'apply_floor'
        varargout{1} = apply_floor(varargin{:});
    case 'record'
        varargout{1} = event_record(varargin{:});
    case 'skipped_record'
        varargout{1} = skipped_event_record(varargin{:});
    case 'complete'
        varargout{1} = complete_event(varargin{:});
    case 'active_set_signature'
        varargout{1} = active_set_signature(varargin{:});
    otherwise
        error('vsc_mtdc_cpf_hvdc_derating:unknown_op', ...
            'Unknown HVDC derating utility ''%s''.', op);
end


function report = empty_report(d)
report = struct('changed_idx', [], 'lambda_event', [], ...
    'monitor_idx', d.monitor_idx(:), 'utilization', [], ...
    'margin', [], 'Smax', [], 'P', [], 'Q', [], 'V', [], ...
    'active_limit', {{}}, 'max_utilization', NaN, ...
    'limiting_vsc', NaN, 'start_utilization', ...
    d.start_utilization, 'target_utilization', ...
    d.target_utilization, 'backoff_lambda', 0, ...
    'old_pac_set', [], 'new_pac_set', [], ...
    'old_qac_set', [], 'new_qac_set', [], ...
    'final_P', [], 'final_Q', [], 'final_V', [], ...
    'final_utilization', []);


function out = utilization_report(r, current, d, opt, baseMVA)
c = idx_vsc;
out = struct('idx', [], 'utilization', [], 'margin', [], ...
    'Smax', [], 'P', [], 'Q', [], 'V', [], ...
    'active_limit', {{}}, 'max_utilization', NaN, ...
    'limiting_vsc', NaN);
rows = d.monitor_idx(:);
rows = rows(rows >= 1 & rows <= size(current.vsc, 1) & ...
    rows <= size(r.vsc, 1));
rows = rows(current.vsc(rows, c.VSC_STATUS) > 0);
if isempty(rows)
    return;
end
for kk = 1:length(rows)
    k = rows(kk);
    P0 = r.vsc(k, c.PAC);
    Q0 = r.vsc(k, c.QAC);
    V0 = capability_voltage(r.vsc, k, c);
    params = vsc_capability_params(current, opt, k, kk);
    try
        [~, ~, ~, ~, info] = vsc_capability_curve( ...
            P0, Q0, params.Smax, V0, r.vsc(k, :), ...
            params.mode, params.Vmax, baseMVA);
        margin = info.margin;
        Smax = info.Smax;
        active_limit = info.active_limit;
    catch
        margin = NaN;
        Smax = params.Smax;
        active_limit = 'evaluation_failed';
    end
    if isfinite(margin) && isfinite(Smax) && Smax > 0
        util = max(0, 1 - margin / Smax);
    else
        util = abs(P0 + 1j * Q0) / max(params.Smax, eps);
    end
    out.idx(end+1, 1) = k;
    out.utilization(end+1, 1) = util;
    out.margin(end+1, 1) = margin;
    out.Smax(end+1, 1) = Smax;
    out.P(end+1, 1) = P0;
    out.Q(end+1, 1) = Q0;
    out.V(end+1, 1) = V0;
    out.active_limit{end+1, 1} = active_limit;
end
[out.max_utilization, pos] = max(out.utilization);
out.limiting_vsc = out.idx(pos);


function report = copy_utilization_report(report, u)
report.monitor_idx = u.idx;
report.utilization = u.utilization;
report.margin = u.margin;
report.Smax = u.Smax;
report.P = u.P;
report.Q = u.Q;
report.V = u.V;
report.active_limit = u.active_limit;
report.max_utilization = u.max_utilization;
report.limiting_vsc = u.limiting_vsc;


function backoff_lam = backoff_lambda(util, d)
if util <= d.start_utilization
    backoff_lam = 0;
    return;
end
span = max(d.start_utilization - d.target_utilization, eps);
severity = max(1, (util - d.target_utilization) / span);
backoff_lam = d.backoff_lambda_per_step * severity;


function vals = apply_floor(old_vals, vals, base_vals, scale)
if scale <= 0
    return;
end
scale = min(max(scale, 0), 1);
floor_vals = base_vals + scale * (old_vals - base_vals);
for kk = 1:numel(vals)
    if abs(vals(kk) - base_vals(kk)) < ...
            abs(floor_vals(kk) - base_vals(kk))
        vals(kk) = floor_vals(kk);
    end
end


function ev = event_record(event_k, event_idx, msg, report)
ev = struct('k', event_k, 'name', 'HVDC_DERATING', ...
    'idx', event_idx, 'msg', msg, ...
    'lambda_event', report.lambda_event, ...
    'changed_vsc_idx', report.changed_idx, ...
    'monitor_vsc_idx', report.monitor_idx, ...
    'utilization', report.utilization, ...
    'margin', report.margin, 'Smax', report.Smax, ...
    'P', report.P, 'Q', report.Q, 'V', report.V, ...
    'active_limit', {report.active_limit}, ...
    'max_utilization', report.max_utilization, ...
    'limiting_vsc', report.limiting_vsc, ...
    'start_utilization', report.start_utilization, ...
    'target_utilization', report.target_utilization, ...
    'backoff_lambda', report.backoff_lambda, ...
    'old_pac_set', report.old_pac_set, ...
    'new_pac_set', report.new_pac_set, ...
    'old_qac_set', report.old_qac_set, ...
    'new_qac_set', report.new_qac_set, ...
    'final_P', [], 'final_Q', [], 'final_V', [], ...
    'final_utilization', []);


function ev = skipped_event_record(event_k, event_idx, msg, ...
        lambda_event, max_utilization, limiting_vsc, backoff_lam)
ev = struct('k', event_k, ...
    'name', 'HVDC_DERATING_SKIPPED', ...
    'idx', event_idx, 'msg', msg, ...
    'lambda_event', lambda_event, ...
    'max_utilization', max_utilization, ...
    'limiting_vsc', limiting_vsc, ...
    'backoff_lambda', backoff_lam);


function ev = complete_event(ev, report, r, current, d, opt, baseMVA)
c = idx_vsc;
rows = report.changed_idx(:);
n = length(rows);
final_P = NaN(n, 1);
final_Q = NaN(n, 1);
final_V = NaN(n, 1);
final_util = NaN(n, 1);
for kk = 1:n
    k = rows(kk);
    if size(r.vsc, 1) < k || size(r.vsc, 2) < c.QAC
        continue;
    end
    final_P(kk) = r.vsc(k, c.PAC);
    final_Q(kk) = r.vsc(k, c.QAC);
    final_V(kk) = capability_voltage(r.vsc, k, c);
end
u = utilization_report(r, current, d, opt, baseMVA);
[~, loc] = ismember(rows, u.idx);
for kk = 1:n
    if loc(kk) > 0
        final_util(kk) = u.utilization(loc(kk));
    end
end
ev.final_P = final_P;
ev.final_Q = final_Q;
ev.final_V = final_V;
ev.final_utilization = final_util;


function sig = active_set_signature(mpc)
c = idx_vsc;
cols = [c.PAC_SET c.QAC_SET];
cols = cols(cols <= size(mpc.vsc, 2));
vals = reshape(mpc.vsc(:, cols), [], 1);
sig = sprintf('%.9g,', round(vals(:)' * 1e9) / 1e9);


function V = capability_voltage(vsc, row, c)
if size(vsc, 2) >= c.VAC_PCC && ...
        isfinite(vsc(row, c.VAC_PCC)) && vsc(row, c.VAC_PCC) > 0
    V = vsc(row, c.VAC_PCC);
elseif size(vsc, 2) >= c.VAC_INTERNAL && ...
        isfinite(vsc(row, c.VAC_INTERNAL)) && ...
        vsc(row, c.VAC_INTERNAL) > 0
    V = vsc(row, c.VAC_INTERNAL);
else
    V = vsc(row, c.VAC_SET);
end
