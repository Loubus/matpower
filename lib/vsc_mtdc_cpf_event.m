function ev = vsc_mtdc_cpf_event(name, event_k, event_idx, msg, varargin)
%VSC_MTDC_CPF_EVENT Build a simple CPF event record.

ev = struct('k', event_k, 'name', name, 'idx', event_idx, 'msg', msg);
for kk = 1:2:length(varargin)
    ev.(varargin{kk}) = varargin{kk+1};
end
