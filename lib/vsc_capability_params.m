function params = vsc_capability_params(mpc, opt, k, kk)
% vsc_capability_params - Resolves per-converter VSC capability parameters.
% ::
%
%   PARAMS = VSC_CAPABILITY_PARAMS(MPC, OPT, K, KK)
%
%   Resolves the parameters used by the TESIS-style VSC post-solve saturation
%   layer for converter K. Case metadata in MPC.VSC_CAPABILITY has priority
%   over global options. Scalar and vector options remain supported as
%   study/test fallbacks. These parameters feed PF/CPF audit and active-set
%   enforcement logic, not OPF constraints.
%
%   Supported metadata fields:
%       Snom, Smax, smax          converter nominal MVA / capability base
%       VconvMax, Vmax, vmax      internal converter voltage limit
%       mode, projection_mode     projection policy override
%
%   Supported option fields:
%       vsc_smax, capability_vsc_smax
%       vmax, capability_vsc_vmax
%       mode, capability_vsc_mode
%
% See also vsc_capability_curve, vsc_capability_policy.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 2 || isempty(opt)
    opt = struct();
end
if nargin < 4 || isempty(kk)
    kk = k;
end

[Smax, Ssrc] = metadata_or_option(mpc, opt, k, kk, ...
    {'Snom', 'Smax', 'smax'}, ...
    {'vsc_smax', 'capability_vsc_smax'}, []);
[Vmax, Vsrc] = metadata_or_option(mpc, opt, k, kk, ...
    {'VconvMax', 'Vmax', 'vmax'}, ...
    {'vmax', 'capability_vsc_vmax'}, 1.15);
[mode, Msrc] = metadata_or_option(mpc, opt, k, kk, ...
    {'mode', 'projection_mode'}, ...
    {'mode', 'capability_vsc_mode'}, []);

params = struct( ...
    'Smax',       Smax, ...
    'Vmax',       Vmax, ...
    'mode',       mode, ...
    'Smax_source', Ssrc, ...
    'Vmax_source', Vsrc, ...
    'mode_source', Msrc );


function [val, source] = metadata_or_option(mpc, opt, k, kk, ...
        meta_names, opt_names, default)
[val, found] = metadata_value(mpc, meta_names, k, kk);
if found
    source = 'metadata';
    return;
end
[val, found] = option_value(opt, opt_names, k, kk);
if found
    source = 'option';
    return;
end
val = default;
source = 'default';


function [val, found] = metadata_value(mpc, names, k, kk)
val = [];
found = 0;
if ~isfield(mpc, 'vsc_capability') || isempty(mpc.vsc_capability) || ...
        ~isstruct(mpc.vsc_capability)
    return;
end
meta = mpc.vsc_capability;
if numel(meta) > 1
    if numel(meta) >= k
        meta = meta(k);
    elseif numel(meta) >= kk
        meta = meta(kk);
    else
        return;
    end
    index = 1;
else
    index = k;
end
for ii = 1:length(names)
    name = names{ii};
    if isfield(meta, name) && ~empty_value(meta.(name))
        val = indexed_value(meta.(name), index, kk, name);
        found = ~empty_value(val);
        if found
            return;
        end
    end
end


function [val, found] = option_value(opt, names, k, kk)
val = [];
found = 0;
if ~isstruct(opt)
    return;
end
for ii = 1:length(names)
    name = names{ii};
    if isfield(opt, name) && ~empty_value(opt.(name))
        val = indexed_value(opt.(name), k, kk, name);
        found = ~empty_value(val);
        if found
            return;
        end
    end
end


function val = indexed_value(raw, k, kk, name)
if iscell(raw)
    if isscalar(raw)
        val = raw{1};
    elseif numel(raw) >= k
        val = raw{k};
    elseif numel(raw) >= kk
        val = raw{kk};
    else
        error('vsc_capability_params: option %s has invalid length', name);
    end
elseif isnumeric(raw)
    if isscalar(raw)
        val = raw;
    elseif numel(raw) >= k
        val = raw(k);
    elseif numel(raw) >= kk
        val = raw(kk);
    else
        error('vsc_capability_params: option %s has invalid length', name);
    end
else
    val = raw;
end


function TorF = empty_value(val)
TorF = isempty(val);
if ~TorF && (ischar(val) || isstring(val))
    TorF = isempty(char(val));
end
