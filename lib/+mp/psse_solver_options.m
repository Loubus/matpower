function [mpopt, policy, mpc] = psse_solver_options(mpopt, mpc)
% psse_solver_options - Applies and reports PSS/E SYSTEM-WIDE solver options.
% ::
%
%   [MPOPT, POLICY, MPC] = MP.PSSE_SOLVER_OPTIONS(MPOPT, MPC)
%
% Reads PSS/E SYSTEM-WIDE records preserved in ``mpc.psse.system`` and
% classifies relevant effective parameters as applied, ignored, unsupported
% or fallback. The supported solver-level mappings are applied centrally
% before ``runpf_psse`` builds the MP-Core task.
%
% See also runpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

policy = empty_policy();
policy.raw.general = system_section(mpc, 'general');
policy.raw.solver = system_section(mpc, 'solver');
policy.raw.newton = system_section(mpc, 'newton');
policy.raw.adjust = system_section(mpc, 'adjust');

[mpopt, mpc] = apply_solver_options(mpopt, mpc, policy.raw);

sections = {'general', 'solver', 'newton', 'adjust'};
for s = 1:length(sections)
    section = sections{s};
    raw = policy.raw.(section);
    names = fieldnames(raw);
    for k = 1:length(names)
        name = upper(names{k});
        value = raw.(names{k});
        [category, status, target, reason] = classify_param(section, name, value);
        if strcmp(category, 'ignored') && strcmp(status, 'unrecognized')
            policy = add_entry(policy, category, section, name, value, ...
                'raw_explicit', status, target, reason, false);
            policy.warnings{end+1} = sprintf( ...
                'Unrecognized PSS/E SYSTEM-WIDE %s.%s preserved without mapping.', ...
                upper(section), name);
        else
            policy = add_entry(policy, category, section, name, value, ...
                'raw_explicit', status, target, reason, true);
        end
    end
end
policy = add_default_effective_entries(policy);

function [mpopt, mpc] = apply_solver_options(mpopt, mpc, raw)
[has_method, method] = field_value(raw.solver, 'METHOD');
if has_method && strcmpi(strtrim(char_value(method)), 'FNSL')
    mpopt = mpoption(mpopt, 'pf.alg', 'NR', ...
        'pf.current_balance', 0, 'pf.v_cartesian', 0);
end

[has_itmxn, itmxn] = field_value(raw.newton, 'ITMXN');
if has_itmxn
    max_it = numeric_scalar(itmxn);
    if ~isempty(max_it) && max_it >= 0
        mpopt = mpoption(mpopt, 'pf.nr.max_it', fix(max_it));
    end
end

[has_flatst, flatst] = field_value(raw.solver, 'FLATST');
if has_flatst && ~is_zero_value(flatst)
    mpc = apply_flat_start(mpc);
end

function mpc = apply_flat_start(mpc)
[PQ, ~, ~, ~, ~, BUS_TYPE, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
if isfield(mpc, 'bus') && ~isempty(mpc.bus)
    mpc.bus(:, VA) = 0;
    pq = mpc.bus(:, BUS_TYPE) == PQ;
    mpc.bus(pq, VM) = 1;
end

function policy = empty_policy()
entry = struct('section', {}, 'name', {}, 'value', {}, ...
    'origin', {}, 'category', {}, 'status', {}, 'target', {}, ...
    'reason', {});
policy = struct();
policy.raw = struct('general', struct(), 'solver', struct(), ...
    'newton', struct(), 'adjust', struct());
policy.effective = entry;
policy.applied = entry;
policy.ignored = entry;
policy.unsupported = entry;
policy.fallback = entry;
policy.warnings = {};

function section = system_section(mpc, name)
section = struct();
if isfield(mpc, 'psse') && isfield(mpc.psse, 'system') && ...
        isfield(mpc.psse.system, name) && isstruct(mpc.psse.system.(name))
    section = mpc.psse.system.(name);
end

function [category, status, target, reason] = classify_param(section, name, value)
category = 'ignored';
status = 'preserved';
target = '';
reason = 'Preserved from PSS/E SYSTEM-WIDE data; no runpf_psse mapping is defined.';

switch lower(section)
    case 'general'
        [category, status, target, reason] = classify_general(name);
    case 'solver'
        [category, status, target, reason] = classify_solver(name, value);
    case 'newton'
        [category, status, target, reason] = classify_newton(name);
    case 'adjust'
        [category, status, target, reason] = classify_adjust(name);
end

function [category, status, target, reason] = classify_general(name)
switch name
    case 'PQBRAK'
        category = 'applied';
        status = 'active';
        target = 'mp.psse_pqbrak_prepare';
        reason = 'Used by the PSS/E low-voltage load scaling helper.';
    case 'THRSHZ'
        category = 'fallback';
        status = 'deferred';
        target = 'branch zero-impedance handling';
        reason = 'PSS/E zero-impedance threshold is reported; runpf_psse leaves the current MATPOWER branch model unchanged.';
    otherwise
        category = 'ignored';
        status = 'unrecognized';
        target = '';
        reason = 'Preserved from PSS/E GENERAL data; no runpf_psse mapping is defined.';
end

function [category, status, target, reason] = classify_solver(name, value)
switch name
    case 'METHOD'
        method = strtrim(char_value(value));
        target = 'mpopt.pf.alg';
        if strcmpi(method, 'FNSL')
            category = 'applied';
            status = 'active';
            reason = 'FNSL is mapped explicitly to MATPOWER Newton power-balance polar PF.';
        else
            category = 'unsupported';
            status = 'unsupported_method';
            reason = 'Only FNSL is currently recognized for PSS/E solver-method reporting.';
        end
    case 'ACTAPS'
        category = 'applied';
        status = active_status(value);
        target = 'mp.psse_xfmr_states';
        reason = 'Used as the global gate for PSS/E AC transformer tap adjustment.';
    case 'DCTAPS'
        category = 'applied';
        status = active_status(value);
        target = 'mp.psse_twodc_states';
        reason = 'Used as the global gate for PSS/E two-terminal DC tap adjustment.';
    case 'SWSHNT'
        category = 'applied';
        status = active_status(value);
        target = 'mp.psse_swshunt_states';
        reason = 'Used as the global gate for PSS/E switched-shunt adjustment.';
    case 'VARLIM'
        category = 'applied';
        status = active_status(value);
        target = 'mp.psse_genq_states';
        reason = 'Used by the PSS/E generator Q/voltage-control policy, not blindly mapped to pf.enforce_q_lims.';
    case 'FACTS'
        category = 'applied';
        status = active_status(value);
        target = 'mp.psse_facts_states';
        reason = 'Used as the global gate for FACTS STATCON control.';
    case 'FLATST'
        target = 'mpc.bus(:, VM/VA)';
        if is_zero_value(value)
            category = 'applied';
            status = 'inactive';
            reason = 'FLATST=0 preserves RAW voltage initial conditions, matching current runpf_psse behavior.';
        else
            category = 'applied';
            status = 'active';
            reason = 'FLATST=1 zeros bus voltage angles and flat-starts PQ-bus voltage magnitudes.';
        end
    case 'PHSHFT'
        target = 'mpc.branch(:, SHIFT)';
        if is_zero_value(value)
            category = 'applied';
            status = 'inactive';
            reason = 'PHSHFT=0 means no automatic phase-shifter adjustment; fixed ANG fields are already converted as branch shifts.';
        else
            category = 'unsupported';
            status = 'unsupported_control';
            reason = 'Automatic phase-shifter control is not implemented; fixed branch shifts remain preserved.';
        end
    case 'AREAIN'
        target = 'area interchange control';
        if is_zero_value(value)
            category = 'applied';
            status = 'inactive';
            reason = 'AREAIN=0 disables automatic area-interchange adjustment.';
        else
            category = 'unsupported';
            status = 'unsupported_control';
            reason = 'Automatic area-interchange adjustment is not implemented in runpf_psse.';
        end
    case 'NONDIV'
        target = 'Newton non-divergent step control';
        if is_zero_value(value)
            category = 'applied';
            status = 'inactive';
            reason = 'NONDIV=0 disables PSS/E non-divergent Newton behavior.';
        else
            category = 'unsupported';
            status = 'unsupported_algorithm';
            reason = 'PSS/E non-divergent Newton behavior is not implemented in MATPOWER.';
        end
    otherwise
        category = 'ignored';
        status = 'unrecognized';
        target = '';
        reason = 'Preserved from PSS/E SOLVER data; no runpf_psse mapping is defined.';
end

function [category, status, target, reason] = classify_newton(name)
switch name
    case 'ITMXN'
        category = 'applied';
        status = 'active';
        target = 'mpopt.pf.nr.max_it';
        reason = 'Mapped explicitly to MATPOWER Newton maximum iteration count.';
    case 'TOLN'
        category = 'fallback';
        status = 'deferred';
        target = 'mpopt.pf.tol';
        reason = 'MATPOWER mismatch tolerance remains in effect until PSS/E TOLN units/scaling are validated.';
    case 'ACCN'
        category = 'ignored';
        status = 'deferred';
        target = 'PSS/E voltage-control setpoint acceleration';
        reason = 'ACCN is not a simple Newton damping factor; it is preserved for future control-specific mapping.';
    case 'VCTOLQ'
        category = 'applied';
        status = 'active';
        target = 'mp.psse_genq_states';
        reason = 'Used as the generator Q/voltage-control reactive tolerance.';
    case 'VCTOLV'
        category = 'applied';
        status = 'active';
        target = 'PSS/E voltage-control helpers';
        reason = 'Used as the voltage tolerance for existing runpf_psse controls.';
    case 'DVLIM'
        category = 'unsupported';
        status = 'unsupported_algorithm';
        target = 'Newton voltage-step limiting';
        reason = 'MATPOWER Newton does not currently apply the PSS/E voltage-step limit.';
    case 'NDVFCT'
        category = 'unsupported';
        status = 'unsupported_algorithm';
        target = 'Newton non-divergent step control';
        reason = 'NDVFCT is tied to PSS/E non-divergent Newton behavior, which is not implemented.';
    otherwise
        category = 'ignored';
        status = 'unrecognized';
        target = '';
        reason = 'Preserved from PSS/E NEWTON data; no runpf_psse mapping is defined.';
end

function [category, status, target, reason] = classify_adjust(name)
switch name
    case 'MXTPSS'
        category = 'applied';
        status = 'active';
        target = 'PSS/E iterative control helpers';
        reason = 'Used as the maximum number of PSS/E external-control adjustment cycles.';
    case 'ADJTHR'
        category = 'ignored';
        status = 'deferred';
        target = 'tap/shunt adjustment threshold';
        reason = 'Adjustment threshold mapping is deferred until small PSS/E cases establish trajectory semantics.';
    case 'ACCTAP'
        category = 'ignored';
        status = 'deferred';
        target = 'AC transformer tap movement damping';
        reason = 'AC tap acceleration/damping is preserved for a future validated transformer-control phase.';
    case 'TAPLIM'
        category = 'ignored';
        status = 'deferred';
        target = 'per-cycle tap movement limit';
        reason = 'Tap movement limiting is preserved for a future validated transformer-control phase.';
    case 'SWVBND'
        category = 'ignored';
        status = 'deferred';
        target = 'switched-shunt violation-band selection';
        reason = 'Switched-shunt band selection is preserved for a future validated shunt-control phase.';
    case 'MXSWIM'
        category = 'unsupported';
        status = 'unsupported_model';
        target = 'induction-machine switching';
        reason = 'MATPOWER runpf_psse has no PSS/E induction-machine switching model.';
    otherwise
        category = 'ignored';
        status = 'unrecognized';
        target = '';
        reason = 'Preserved from PSS/E ADJUST data; no runpf_psse mapping is defined.';
end

function policy = add_default_effective_entries(policy)
defs = default_effective_specs();
for k = 1:length(defs)
    d = defs(k);
    if effective_has(policy, d.section, d.name)
        continue;
    end
    [category, status, target, reason] = classify_param( ...
        d.section, d.name, d.value);
    if strcmpi(d.section, 'solver') && strcmpi(d.name, 'METHOD')
        category = 'fallback';
        status = 'deferred';
        target = 'mpopt.pf.alg';
        reason = ['PSS/E CLI default method is reported as FNSL; ' ...
            'runpf_psse leaves MATPOWER pf.alg unchanged unless RAW ' ...
            'explicitly declares SOLVER.METHOD.'];
    elseif strcmpi(d.section, 'solver') && ...
            any(strcmpi(d.name, {'ACTAPS', 'AREAIN', 'PHSHFT', ...
                'DCTAPS', 'SWSHNT', 'VARLIM'}))
        category = 'fallback';
        status = 'deferred';
        reason = ['PSS/E CLI effective default is reported; the ' ...
            'corresponding runpf_psse gate keeps historical behavior unless ' ...
            'RAW explicitly declares this option.'];
    elseif strcmpi(d.section, 'newton') && strcmpi(d.name, 'ITMXN')
        category = 'fallback';
        status = 'deferred';
        target = 'mpopt.pf.nr.max_it';
        reason = ['PSS/E CLI effective default is reported; runpf_psse ' ...
            'maps ITMXN only when RAW explicitly declares it.'];
    elseif strcmpi(d.section, 'adjust') && strcmpi(d.name, 'MXTPSS')
        category = 'applied';
        status = 'active';
        reason = ['PSS/E CLI effective default is reported as 100; ' ...
            'manual RAW/default evidence may show 99, and explicit RAW ' ...
            'MXTPSS always takes priority.'];
    end
    policy = add_entry(policy, category, d.section, d.name, d.value, ...
        d.origin, status, target, reason, true);
end

function defs = default_effective_specs()
defs = mp.psse_system_defaults();

function tf = effective_has(policy, section, name)
tf = false;
for k = 1:length(policy.effective)
    if strcmpi(policy.effective(k).section, section) && ...
            strcmpi(policy.effective(k).name, name)
        tf = true;
        return;
    end
end

function policy = add_entry(policy, category, section, name, value, origin, ...
        status, target, reason, add_effective)
entry = struct( ...
    'section', section, ...
    'name', name, ...
    'value', value, ...
    'origin', origin, ...
    'category', category, ...
    'status', status, ...
    'target', target, ...
    'reason', reason);
policy.(category)(end+1) = entry;
if add_effective
    policy.effective(end+1) = entry;
end

function status = active_status(value)
if is_zero_value(value)
    status = 'inactive';
else
    status = 'active';
end

function tf = is_zero_value(value)
if isnumeric(value) && isscalar(value)
    tf = value == 0;
else
    tf = strcmp(strtrim(char_value(value)), '0');
end

function txt = char_value(value)
if ischar(value)
    txt = value;
elseif isa(value, 'string') && isscalar(value)
    txt = char(value);
elseif isnumeric(value) && isscalar(value)
    txt = sprintf('%.15g', value);
else
    txt = '';
end

function [has_value, value] = field_value(s, name)
has_value = 0;
value = [];
if isstruct(s)
    names = fieldnames(s);
    idx = find(strcmpi(names, name), 1);
    if ~isempty(idx)
        has_value = 1;
        value = s.(names{idx});
    end
end

function value = numeric_scalar(raw)
value = [];
if isnumeric(raw) && isscalar(raw)
    value = raw;
else
    txt = char_value(raw);
    if ~isempty(txt)
        value = str2double(txt);
        if isnan(value)
            value = [];
        end
    end
end
