function ev = vsc_mtdc_cpf_add_missing_event_fields(ev, names)
% vsc_mtdc_cpf_add_missing_event_fields - Widen CPF event structs.

for kk = 1:length(names)
    if ~isfield(ev, names{kk})
        [ev.(names{kk})] = deal([]);
    end
end
