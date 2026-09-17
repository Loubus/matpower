function varargout = psse_unified_active_set(op, varargin)
%PSSE_UNIFIED_ACTIVE_SET Shared PSS/E unified active-set utilities.

switch lower(op)
    case 'signature'
        varargout{1} = active_set_signature(varargin{:});
    case 'has_control_data'
        varargout{1} = has_control_data(varargin{:});
    case 'family_present'
        varargout{1} = family_present(varargin{:});
    case 'control_case_from_unified_result'
        varargout{1} = control_case_from_unified_result(varargin{:});
    case 'copy_original_active_set_to_ac'
        varargout{1} = copy_original_active_set_to_ac(varargin{:});
    case 'report_has_unsatisfied_controls'
        varargout{1} = report_has_unsatisfied_controls(varargin{:});
    case 'control_violations'
        varargout{1} = control_violations(varargin{:});
    case 'control_cycles'
        varargout{1} = control_cycles(varargin{:});
    case 'control_report_count'
        varargout{1} = control_report_count(varargin{:});
    case 'load_equiv_changed'
        varargout{1} = load_equiv_changed(varargin{:});
    case 'has_genq_control'
        varargout{1} = has_genq_control(varargin{:});
    case 'copy_control_fields'
        varargout{1} = copy_control_fields(varargin{:});
    otherwise
        error('mp:psse_unified_active_set:unknown_op', ...
            'Unknown PSS/E active-set utility ''%s''.', op);
end


function sig = active_set_signature(mpc)
[~, ~, ~, ~, ~, BUS_TYPE, PD, QD, GS, BS] = idx_bus;
[~, ~, ~, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;
[~, ~, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS] = idx_brch;
bus_cols = existing_cols([BUS_TYPE PD QD GS BS], mpc.bus, mpc.bus);
gen_cols = existing_cols([QMAX QMIN VG GEN_STATUS], mpc.gen, mpc.gen);
branch_cols = existing_cols([BR_R BR_X BR_B RATE_A RATE_B RATE_C ...
    TAP SHIFT BR_STATUS], mpc.branch, mpc.branch);
vals = [
    reshape(mpc.bus(:, bus_cols), [], 1);
    reshape(mpc.gen(:, gen_cols), [], 1);
    reshape(mpc.branch(:, branch_cols), [], 1);
    control_lockout_values(mpc)
];
sig = sprintf('%.9g,', round(vals(:)' * 1e9) / 1e9);


function vals = control_lockout_values(mpc)
vals = [];
if ~isfield(mpc, 'psse') || ~isfield(mpc.psse, 'control_lockout') || ...
        isempty(mpc.psse.control_lockout)
    return;
end
families = {'xfmr', 'swshunt'};
for ff = 1:length(families)
    name = families{ff};
    if isfield(mpc.psse.control_lockout, name)
        vals = [vals; logical(mpc.psse.control_lockout.(name)(:))]; %#ok<AGROW>
    end
end


function TorF = has_control_data(mpc, mode)
if nargin < 2
    mode = 'family_present';
end
TorF = 0;
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    return;
end
families = {'pqbrak', 'xfmr', 'genq', 'twodc', 'swshunt', 'facts'};
for ff = 1:length(families)
    if strcmpi(mode, 'raw')
        present = isfield(mpc.psse, families{ff}) && ...
            ~isempty(mpc.psse.(families{ff}));
    else
        present = family_present(mpc, families{ff});
    end
    if present
        TorF = 1;
        return;
    end
end


function TorF = family_present(mpc, name)
TorF = isfield(mpc, 'psse') && isfield(mpc.psse, name) && ...
    ~isempty(mpc.psse.(name));
if TorF && isstruct(mpc.psse.(name)) && ...
        isfield(mpc.psse.(name), 'num') && isempty(mpc.psse.(name).num)
    TorF = 0;
end


function ac = control_case_from_unified_result(r)
ac = r.ac;
drop = {'busdc', 'branchdc', 'vsc', 'vsc_state', 'cpf', ...
    'om', 'order', 'et', 'success', 'iterations', 'convergence'};
for dd = 1:length(drop)
    if isfield(ac, drop{dd})
        ac = rmfield(ac, drop{dd});
    end
end


function ac = copy_original_active_set_to_ac(ac, mpc)
[~, ~, ~, ~, BUS_I, BUS_TYPE, PD, QD, GS, BS] = idx_bus;
[~, ~, QG, QMAX, QMIN, VG, ~, GEN_STATUS] = idx_gen;
[~, ~, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS] = idx_brch;

for kk = 1:size(mpc.bus, 1)
    row = find(ac.bus(:, BUS_I) == mpc.bus(kk, BUS_I), 1);
    if ~isempty(row)
        bus_cols = existing_cols([BUS_TYPE PD QD GS BS], ac.bus, mpc.bus);
        ac.bus(row, bus_cols) = mpc.bus(kk, bus_cols);
    end
end
ng = min(size(mpc.gen, 1), size(ac.gen, 1));
gen_cols = existing_cols([QG QMAX QMIN VG GEN_STATUS], ac.gen, mpc.gen);
ac.gen(1:ng, gen_cols) = mpc.gen(1:ng, gen_cols);
nb = min(size(mpc.branch, 1), size(ac.branch, 1));
branch_cols = existing_cols([BR_R BR_X BR_B RATE_A RATE_B RATE_C ...
    TAP SHIFT BR_STATUS], ac.branch, mpc.branch);
ac.branch(1:nb, branch_cols) = mpc.branch(1:nb, branch_cols);
ac = copy_control_fields(ac, mpc);


function TorF = report_has_unsatisfied_controls(report)
TorF = isfield(report, 'control_violations') && ...
    report.control_violations > 0;


function n = control_violations(mpc)
n = control_report_count(mpc, 'xfmr', 'below_band') + ...
    control_report_count(mpc, 'xfmr', 'above_band') + ...
    control_report_count(mpc, 'swshunt', 'below_band') + ...
    control_report_count(mpc, 'swshunt', 'above_band');


function n = control_cycles(mpc)
n = control_report_count(mpc, 'xfmr', 'cycle_detected') + ...
    control_report_count(mpc, 'swshunt', 'cycle_detected');


function n = control_report_count(mpc, family, field)
n = 0;
if isfield(mpc, 'psse') && isfield(mpc.psse, family) && ...
        isfield(mpc.psse.(family), 'control') && ...
        isfield(mpc.psse.(family).control, field)
    val = mpc.psse.(family).control.(field);
    n = nnz(val);
end


function TorF = load_equiv_changed(ac)
TorF = 0;
if ~isfield(ac, 'psse') || isempty(ac.psse)
    return;
end
if isfield(ac.psse, 'pqbrak') && isfield(ac.psse.pqbrak, 'scale') && ...
        any(abs(ac.psse.pqbrak.scale(:) - 1) > 1e-10)
    TorF = 1;
    return;
end
if isfield(ac.psse, 'pqbrak') && ...
        isfield(ac.psse.pqbrak, 'changed_last') && ...
        any(ac.psse.pqbrak.changed_last(:))
    TorF = 1;
    return;
end
if isfield(ac.psse, 'facts')
    if isfield(ac.psse.facts, 'qinj') && ...
            any(abs(ac.psse.facts.qinj(:)) > 1e-10)
        TorF = 1;
        return;
    elseif isfield(ac.psse.facts, 'control') && ...
            isfield(ac.psse.facts.control, 'qinj') && ...
            any(abs(ac.psse.facts.control.qinj(:)) > 1e-10)
        TorF = 1;
        return;
    end
end
if isfield(ac.psse, 'twodc') && isfield(ac.psse.twodc, 'control')
    ctrl = ac.psse.twodc.control;
    if (isfield(ctrl, 'apply_model') && any(ctrl.apply_model(:))) || ...
            (isfield(ctrl, 'apply_q') && any(ctrl.apply_q(:)))
        TorF = 1;
    end
end


function TorF = has_genq_control(mpc)
TorF = isfield(mpc, 'psse') && family_present(mpc, 'genq');


function mpc = copy_control_fields(mpc, ac)
if ~isfield(ac, 'psse') || isempty(ac.psse)
    return;
end
if ~isfield(mpc, 'psse') || isempty(mpc.psse)
    mpc.psse = struct();
end
families = {'xfmr', 'genq', 'twodc', 'swshunt', 'facts', ...
    'pqbrak', 'solver_options', 'control_failure', ...
    'coordinated_active_set', 'control_lockout'};
for ff = 1:length(families)
    name = families{ff};
    if isfield(ac.psse, name)
        mpc.psse.(name) = ac.psse.(name);
    end
end


function cols = existing_cols(cols, a, b)
cols = cols(cols <= size(a, 2) & cols <= size(b, 2));
