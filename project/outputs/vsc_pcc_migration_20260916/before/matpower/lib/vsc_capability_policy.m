function policy = vsc_capability_policy(vsc_row, opt, k, kk)
% vsc_capability_policy - Resolves TESIS-style VSC saturation policy.
% ::
%
%   POLICY = VSC_CAPABILITY_POLICY(VSC_ROW)
%   POLICY = VSC_CAPABILITY_POLICY(VSC_ROW, OPT, K, KK)
%
%   Returns the explicit post-solve saturation policy used by the VSC-MTDC
%   capability layer. This is PF/CPF active-set logic, not an OPF
%   constraint. DC voltage slack and DC droop converters default to
%   PROJECTION_MODE = 'preservar_p', preserving active power in the local
%   projection and clipping Q when feasible. Fixed-PDC converters default to
%   PROJECTION_MODE = 'radial', preserving power factor unless OPT overrides
%   the mode.
%
%   OPT can be a struct with MODE or CAPABILITY_VSC_MODE, a cell/vector for
%   per-converter values, or a scalar string/char mode.
%
% See also vsc_capability_curve, vsc_capability_geometry.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 2 || isempty(opt)
    opt = struct();
elseif ischar(opt) || isstring(opt)
    opt = struct('mode', char(opt));
end
if nargin < 3 || isempty(k)
    k = 1;
end
if nargin < 4 || isempty(kk)
    kk = k;
end

c = idx_vsc;
[ac_mode, dc_mode] = vsc_modes(vsc_row, c);
raw_mode = policy_option(opt, {'mode', 'capability_vsc_mode', ...
    'projection_mode'}, k, kk, []);
if isempty(raw_mode)
    if dc_mode == c.VSC_DC_VDC
        projection_mode = 'preservar_p';
        reason = 'dc_slack_default_preservar_p';
    elseif dc_mode == c.VSC_DC_DROOP
        projection_mode = 'preservar_p';
        reason = 'dc_droop_default_preservar_p';
    else
        projection_mode = 'radial';
        reason = 'fixed_pdc_default_radial';
    end
else
    projection_mode = normalize_projection_mode(raw_mode);
    reason = 'configured';
end

target_if_p_changed = c.VSC_AC_PQ;
if ac_mode == c.VSC_AC_PV || ac_mode == c.VSC_AC_PQ
    target_if_p_preserved = c.VSC_AC_PQ;
else
    target_if_p_preserved = c.VSC_AC_Q;
end
if strcmp(projection_mode, 'radial')
    target_ac_mode_if_saturated = target_if_p_changed;
else
    target_ac_mode_if_saturated = target_if_p_preserved;
end

policy = struct( ...
    'type',                         'vsc_capability_policy', ...
    'projection_mode',              projection_mode, ...
    'target_ac_mode_if_saturated',  target_ac_mode_if_saturated, ...
    'target_ac_mode_if_p_preserved', target_if_p_preserved, ...
    'target_ac_mode_if_p_changed',  target_if_p_changed, ...
    'reason',                       reason, ...
    'ac_mode',                      ac_mode, ...
    'dc_mode',                      dc_mode, ...
    'preserves_active_power',       strcmp(projection_mode, 'preservar_p'), ...
    'preserves_power_factor',       strcmp(projection_mode, 'radial') );


function [ac_mode, dc_mode] = vsc_modes(vsc_row, c)
ac_mode = NaN;
dc_mode = NaN;
if isempty(vsc_row) || ~isnumeric(vsc_row) || isscalar(vsc_row) || ...
        size(vsc_row, 1) ~= 1
    return;
end
if size(vsc_row, 2) >= c.AC_MODE
    ac_mode = vsc_row(c.AC_MODE);
end
if size(vsc_row, 2) >= c.DC_MODE
    dc_mode = vsc_row(c.DC_MODE);
end


function val = policy_option(opt, names, k, kk, default)
val = default;
if ~isstruct(opt)
    return;
end
for ii = 1:length(names)
    name = names{ii};
    if isfield(opt, name) && ~isempty(opt.(name))
        val = indexed_option(opt.(name), k, kk, name);
        return;
    end
end


function val = indexed_option(raw, k, kk, name)
if iscell(raw)
    if isscalar(raw)
        val = raw{1};
    elseif numel(raw) >= k
        val = raw{k};
    elseif numel(raw) >= kk
        val = raw{kk};
    else
        error('vsc_capability_policy: option %s has invalid length', name);
    end
elseif isnumeric(raw) && ~isempty(raw) && ~isscalar(raw)
    if numel(raw) >= k
        val = raw(k);
    elseif numel(raw) >= kk
        val = raw(kk);
    else
        error('vsc_capability_policy: option %s has invalid length', name);
    end
else
    val = raw;
end


function mode = normalize_projection_mode(mode)
if isstring(mode)
    mode = char(mode);
end
if ~ischar(mode)
    error('vsc_capability_policy: mode must be radial or preservar_p');
end
switch lower(strtrim(mode))
    case {'radial', 'factor-potencia', 'fp'}
        mode = 'radial';
    case {'preservar-p', 'preservar_p', 'preserve-p', 'preserve_p', ...
            'preservep'}
        mode = 'preservar_p';
    otherwise
        error('vsc_capability_policy: mode must be radial or preservar_p');
end
