function val = gen_capability_metadata_or_option_value(mpc, opt, ...
        meta_names, opt_names, g, kk, default, error_prefix)
%GEN_CAPABILITY_METADATA_OR_OPTION_VALUE Resolve generator capability value.

if nargin < 8 || isempty(error_prefix)
    error_prefix = 'gen_capability';
end
val = metadata_value(mpc, meta_names, g, kk, []);
if ~isempty(val)
    return;
end
for ii = 1:length(opt_names)
    val = option_value(opt, opt_names{ii}, g, kk, [], error_prefix);
    if ~isempty(val)
        return;
    end
end
val = default;


function val = metadata_value(mpc, names, g, kk, default)
val = default;
if ~isfield(mpc, 'gen_capability') || isempty(mpc.gen_capability) || ...
        ~isstruct(mpc.gen_capability)
    return;
end
meta = mpc.gen_capability;
if numel(meta) > 1
    if numel(meta) >= g
        meta = meta(g);
    elseif numel(meta) >= kk
        meta = meta(kk);
    else
        return;
    end
    index = 1;
else
    index = g;
end
for jj = 1:length(names)
    name = names{jj};
    if isfield(meta, name) && ~isempty(meta.(name))
        val = indexed_value(meta.(name), index, kk, name, ...
            'gen_capability');
        return;
    end
end


function val = option_value(opt, name, g, kk, default, error_prefix)
val = default;
if ~isfield(opt, name) || isempty(opt.(name))
    return;
end
raw = opt.(name);
val = indexed_value(raw, g, kk, name, error_prefix);


function val = indexed_value(raw, g, kk, name, error_prefix)
if iscell(raw)
    if isscalar(raw)
        val = raw{1};
    elseif numel(raw) >= g
        val = raw{g};
    elseif numel(raw) >= kk
        val = raw{kk};
    else
        error('%s: option %s has invalid length', error_prefix, name);
    end
elseif isnumeric(raw)
    if isscalar(raw)
        val = raw;
    elseif numel(raw) >= g
        val = raw(g);
    elseif numel(raw) >= kk
        val = raw(kk);
    else
        error('%s: option %s has invalid length', error_prefix, name);
    end
else
    val = raw;
end
