function ev = vsc_mtdc_cpf_append_event(ev, add)
% vsc_mtdc_cpf_append_event - Append non-duplicate CPF event records.

if isempty(add)
    return;
end
for kk = 1:numel(add)
    add_kk = add(kk);
    if ~isempty(ev)
        ev = vsc_mtdc_cpf_add_missing_event_fields(ev, fieldnames(add_kk));
        add_kk = vsc_mtdc_cpf_add_missing_event_fields(add_kk, fieldnames(ev));
        add_kk = orderfields(add_kk, ev);
    end
    if vsc_mtdc_cpf_is_duplicate_event(ev, add_kk)
        continue;
    end
    if isempty(ev)
        ev = add_kk;
    else
        ev(end+1) = add_kk; %#ok<AGROW>
    end
end
