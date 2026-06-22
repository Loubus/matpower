function tf = vsc_mtdc_cpf_is_duplicate_event(events, ev)
% vsc_mtdc_cpf_is_duplicate_event - True for repeated adjacent CPF events.

tf = false;
if isempty(events) || ~isfield(events, 'name') || ...
        ~isfield(ev, 'name') || ~strcmp(events(end).name, ev.name)
    return;
end
same_k = isfield(events, 'k') && isfield(ev, 'k') && ...
    isequaln(events(end).k, ev.k);
same_msg = isfield(events, 'msg') && isfield(ev, 'msg') && ...
    strcmp(events(end).msg, ev.msg);
tf = same_k && same_msg;
