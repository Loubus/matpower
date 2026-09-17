function bus = psse_expand_bus_controls(results, state, bus)
%PSSE_EXPAND_BUS_CONTROLS Restore device states without copying group totals.
% Original per-bus loads/fixed shunts are retained. Switched-shunt deltas are
% attributed by original device bus; any remaining aggregate delta is placed
% once at the representative bus. This is an expansion of an already solved
% equivalent, not a new control decision or a distribution of group totals.
[PQ, PV, REF, ~, BUS_I, BUS_TYPE, PD, QD, GS, BS] = idx_bus;
[GEN_BUS, ~, ~, QMAX, QMIN, ~, ~, GEN_STATUS] = idx_gen;
bus0 = state.original_bus;
cols = [PD QD GS BS];
bus(:, cols) = bus0(:, cols);

if isfield(state, 'original_swshunt') && isfield(results, 'psse') && ...
        isfield(results.psse, 'swshunt')
    old = state.original_swshunt;
    new = results.psse.swshunt;
    % Device rows are not reordered by topology collapse or the controllers.
    if size(old.num, 1) ~= size(new.num, 1)
        error('mp:psse_expand_bus_controls:shunt_rows', ...
            'Switched-shunt row identity changed during topology expansion.');
    end
    ic = find(strcmpi(old.colnames, 'I'), 1);
    if ~isempty(ic)
        [mapped, row] = ismember(old.num(:, ic), bus0(:, BUS_I));
        delta = active_b(new) - active_b(old);
        for k = find(mapped(:))'
            bus(row(k), BS) = bus(row(k), BS) + delta(k);
        end
    end
end

% Identify original generator locations, including offline rows. A group
% may contain several original voltage controllers but only one reference.
ng = 0;
if isfield(results, 'gen') && isfield(state, 'original_gen')
    ng = min(size(state.original_gen, 1), size(results.gen, 1));
end
if ng == 0
    results.gen = zeros(0, GEN_STATUS);
    state.original_gen = zeros(0, GEN_BUS);
end
on = results.gen(1:ng, GEN_STATUS) > 0;
voltage_gen = on & results.gen(1:ng, QMAX) > results.gen(1:ng, QMIN);
if isfield(results, 'psse') && isfield(results.psse, 'genq') && ...
        isfield(results.psse.genq, 'control')
    gq = results.psse.genq.control;
    if isfield(gq, 'gen_idx') && isfield(gq, 'limited')
        for k = 1:length(gq.gen_idx)
            g = gq.gen_idx(k);
            if isfield(results, 'order') && g > 0 && ...
                    g <= length(results.order.gen.i2e)
                g = results.order.gen.status.on(results.order.gen.i2e(g));
            end
            if g > 0 && g <= ng && (gq.limited(k) || ...
                    (isfield(gq, 'remote_mask') && gq.remote_mask(k)))
                voltage_gen(g) = false;
            end
        end
    end
end
gen_bus = state.original_gen(1:ng, GEN_BUS);
roots = unique(state.roots(:));
for r = roots'
    members = find(state.roots == r);
    solved_row = find(results.bus(:, BUS_I) == bus0(r, BUS_I), 1);
    if isempty(solved_row), continue; end
    % Do not repeat the solved aggregate at every original member.
    delta = results.bus(solved_row, cols) - sum(bus(members, cols), 1);
    bus(r, cols) = bus(r, cols) + delta;
    if isscalar(members)
        bus(r, BUS_TYPE) = results.bus(solved_row, BUS_TYPE);
        continue;
    end
    with_gen = ismember(bus0(members, BUS_I), gen_bus(on));
    was_regulated = bus0(members, BUS_TYPE) == PV | bus0(members, BUS_TYPE) == REF;
    bus(members(with_gen | was_regulated), BUS_TYPE) = PQ;
    solved_type = results.bus(solved_row, BUS_TYPE);
    if solved_type == PV || solved_type == REF
        regulators = members(ismember(bus0(members, BUS_I), gen_bus(voltage_gen)) & was_regulated);
        if isempty(regulators)
            regulators = members(ismember(bus0(members, BUS_I), gen_bus(voltage_gen)));
        end
        if isempty(regulators)
            % Preserve a solved voltage constraint even in a source without
            % generator metadata (e.g. an externally supplied equivalent).
            regulators = members(was_regulated);
        end
        if isempty(regulators), regulators = r; end
        bus(regulators, BUS_TYPE) = PV;
        if solved_type == REF
            ref = regulators(bus0(regulators, BUS_TYPE) == REF);
            if isempty(ref), ref = regulators(1); end
            bus(ref(1), BUS_TYPE) = REF;
        end
    end
end
end

function b = active_b(sw)
b = sw.num(:, sw.binit_col);
b(~isfinite(b)) = 0;
sc = find(strcmpi(sw.colnames, 'STAT') | strcmpi(sw.colnames, 'ST'), 1);
if ~isempty(sc), b(sw.num(:, sc) == 0) = 0; end
end
