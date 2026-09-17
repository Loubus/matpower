function opts = beerten_cpf_merge_opts(defaults, overrides)
%BEERTEN_CPF_MERGE_OPTS Recursively merge scalar option structs.

opts = defaults;
if nargin < 2 || isempty(overrides)
    return;
end
if ~isstruct(overrides)
    error('beerten_cpf_merge_opts:invalid_opts', ...
        'Options must be provided as a struct.');
end

names = fieldnames(overrides);
for k = 1:numel(names)
    name = names{k};
    val = overrides.(name);
    if isfield(opts, name) && isstruct(opts.(name)) && isstruct(val) && ...
            isscalar(opts.(name)) && isscalar(val)
        opts.(name) = beerten_cpf_merge_opts(opts.(name), val);
    else
        opts.(name) = val;
    end
end
end
