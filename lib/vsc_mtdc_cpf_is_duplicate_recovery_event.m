function tf = vsc_mtdc_cpf_is_duplicate_recovery_event(events, ev)
% vsc_mtdc_cpf_is_duplicate_recovery_event - True for repeated recovery events.

tf = false;
if isempty(events) || ~isfield(ev, 'name') || ...
        ~isfield(ev, 'lambda_freeze')
    return;
end
last_ev = events(end);
if ~isfield(last_ev, 'name') || ~strcmp(last_ev.name, ev.name)
    return;
end
if ~isfield(last_ev, 'lambda_freeze') || ...
        isempty(last_ev.lambda_freeze) || isempty(ev.lambda_freeze) || ...
        abs(last_ev.lambda_freeze - ev.lambda_freeze) > 1e-10
    return;
end
if isfield(last_ev, 'relief_action') && isfield(ev, 'relief_action')
    if strcmp(last_ev.relief_action, 'margin_increase') && ...
            strcmp(ev.relief_action, 'margin_increase') && ...
            isfield(last_ev, 'margin_new') && ...
            isfield(ev, 'margin_new')
        tf = abs(last_ev.margin_new - ev.margin_new) <= 1e-12;
        return;
    end
    tf = strcmp(last_ev.relief_action, ev.relief_action);
else
    tf = true;
end
