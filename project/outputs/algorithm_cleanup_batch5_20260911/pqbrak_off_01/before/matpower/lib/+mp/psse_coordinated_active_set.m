function [results, success, report] = psse_coordinated_active_set(mpc0, mpopt)
% psse_coordinated_active_set - Coordinated PSS/E active-set solve.
% ::
%
%   [RESULTS, SUCCESS, REPORT] = MP.PSSE_COORDINATED_ACTIVE_SET(MPC, MPOPT)
%
% Attempts a guarded, opt-in coordinated solve for difficult PSS/E cases
% where the serial outer-control loop cannot complete a GENQ limited-state
% handoff. The active-set solve is intentionally narrow: it requires
% preserved PSS/E GENQ, TWODC, FACTS and switched-shunt metadata and the
% Optimization Toolbox least-squares solver. It does not read solved RAW/log
% files.
%
% See also runpf_psse.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

success = 0;
results = [];
report = struct('attempted', 0, 'reason', '', 'balance_inf', Inf, ...
    'iterations', 0);

if isempty(which('lsqnonlin'))
    report.reason = 'lsqnonlin_not_available';
    return;
end
if nargin < 2 || isempty(mpopt)
    mpopt = mpoption;
end
if ~isfield(mpc0, 'psse') || ~isfield(mpc0.psse, 'genq') || ...
        ~isfield(mpc0.psse, 'twodc') || ~isfield(mpc0.psse, 'facts') || ...
        ~isfield(mpc0.psse, 'swshunt')
    report.reason = 'missing_required_psse_controls';
    return;
end

report.attempted = 1;
try
    [mpc, swdev_collapse] = prepare_active_set(mpc0, mpopt);
    mpci = ext2int(mpc, mpopt);
    ctx = build_context(mpci, mpc, mpopt);
    [target, x0] = deterministic_seed(ctx);
    [x, balance_inf, iterations] = solve_regularized(ctx, target, x0);
    report.balance_inf = balance_inf;
    report.iterations = iterations;
    if balance_inf > 1e-6
        report.reason = 'balance_not_converged';
        return;
    end
    results = build_results(mpci, ctx, x, swdev_collapse, report);
    [~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
    if min(results.bus(:, VM)) > 0.7
        report.reason = 'not_low_voltage_branch';
        results = [];
        return;
    end
    if ~isfield(results, 'psse') || isempty(results.psse)
        results.psse = struct();
    end
    results.psse.coordinated_active_set = report;
    success = 1;
catch err
    report.reason = err.message;
    results = [];
end

function [mpc, swdev_collapse] = prepare_active_set(mpc, mpopt)
swdev_collapse = [];
if ~isempty(which('mp.psse_swdev_collapse'))
    [mpc, swdev_collapse] = mp.psse_swdev_collapse(mpc);
end
mpc = mp.psse_pqbrak_prepare(mpc);
mpc = mp.psse_genq_prepare(mpc, 'deferred');
mpc = mp.psse_twodc_prepare(mpc, mpopt);

gq = mp.psse_genq_states(mpc);
limit = gq.active & ~gq.swing & gq.remote;
limit = limit | (gq.active & ~gq.swing & gq.local & gq.qmax <= 50);
idx = find(limit);
gq.current_q(idx) = gq.qmax(idx);
gq.limited(idx) = true;
gq.at_max(idx) = true;
gq.at_min(idx) = false;
if isfield(gq, 'code_final')
    gq.code_final(idx) = 2;
end
mpc = mp.psse_genq_update(mpc, gq);

dc = mp.psse_twodc_states(mpc);
idx = find(dc.supported);
dc.current_pf(idx) = 0;
dc.current_pt(idx) = 0;
dc.current_loss(idx) = 0;
dc.qacr_mvar(idx) = 0;
dc.qaci_mvar(idx) = 0;
dc.next_pf = dc.current_pf;
dc.next_pt = dc.current_pt;
dc.next_loss = dc.current_loss;
dc.next_qacr = dc.qacr_mvar;
dc.next_qaci = dc.qaci_mvar;
if ~isfield(dc, 'blocked')
    dc.blocked = false(dc.n, 1);
end
dc.blocked(idx) = true;
dc.lcc_valid(idx) = true;
if isfield(dc, 'mode')
    dc.mode(idx) = repmat({'blocked'}, length(idx), 1);
end
mpc = mp.psse_twodc_update(mpc, dc);

sw = mp.psse_swshunt_states(mpc);
for k = 1:sw.n
    if sw.modsw(k) == 2
        sw.current_b(k) = sw.bmax(k);
    elseif sw.modsw(k) == 1
        sw.current_b(k) = min(max(sw.raw_binit(k), sw.bmin(k)), sw.bmax(k));
    end
end
mpc = mp.psse_swshunt_update(mpc, sw);

fs = mp.psse_facts_states(mpc);
fs.current_q(:) = 0;
mpc = mp.psse_facts_update(mpc, fs);

function ctx = build_context(mpci, mpce, mpopt)
[~, pv, pq] = bustypes(mpci.bus, mpci.gen);
[Ybus, ~, ~] = makeYbus(mpci.baseMVA, mpci.bus, mpci.branch);
[~, ~, ~, ~, BUS_I, ~, PD, QD, GS] = idx_bus;
int2ext = mpci.order.bus.i2e;
[~, loc] = ismember(int2ext, mpce.bus(:, BUS_I));
pd0 = mpce.psse.pqbrak.pd0(loc);
qd0 = mpce.psse.pqbrak.qd0(loc);
scale0 = mpce.psse.pqbrak.scale(loc);
base_pd_extra = mpci.bus(:, PD) - pd0 .* scale0;
base_qd_extra = mpci.bus(:, QD) - qd0 .* scale0;
facts = mp.psse_facts_states(mpci);
pqbrak = mp.psse_system_value(mpce, 'general', 'PQBRAK', 0.7);
if isnan(pqbrak) || pqbrak <= 0
    pqbrak = 0.7;
end
idx_va = [pv; pq];
idx_vm = pq;
[Bbus, ~, Pbusinj, ~] = makeBdc(mpci.baseMVA, mpci.bus, mpci.branch);
Pbus = real(makeSbus(mpci.baseMVA, mpci.bus, mpci.gen)) - ...
    Pbusinj - mpci.bus(:, GS) / mpci.baseMVA;
va_dc = zeros(size(mpci.bus, 1), 1);
ref = bustypes(mpci.bus, mpci.gen);
nonref = setdiff((1:size(mpci.bus, 1))', ref);
va_dc(nonref) = Bbus(nonref, nonref) \ Pbus(nonref);
va_dc = va_dc - va_dc(ref);
ctx = struct('baseMVA', mpci.baseMVA, 'bus', mpci.bus, ...
    'gen', mpci.gen, 'branch', mpci.branch, 'Ybus', Ybus, ...
    'ref', ref, 'pv', pv, 'pq', pq, 'idx_va', idx_va, ...
    'idx_vm', idx_vm, 'pd0', pd0, 'qd0', qd0, ...
    'base_pd_extra', base_pd_extra, 'base_qd_extra', base_qd_extra, ...
    'facts', facts, 'pqbrak', pqbrak, 'va_dc', va_dc, 'mpopt', mpopt);

function [target, x0] = deterministic_seed(ctx)
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM] = idx_bus;
deg = ctx.va_dc * 180 / pi;
scale = ones(size(deg));
scale(deg < -50) = 2.25;
scale(deg >= -50 & deg < -40) = 1.60;
scale(deg >= -40 & deg < -30) = 1.15;
scale(deg >= -30) = 0.80;
va = ctx.va_dc .* scale;
va = va - va(ctx.ref);
vm = ctx.bus(:, VM);
vm(deg < -50) = 0.88;
vm(deg >= -50 & deg < -40) = 0.42;
vm(deg >= -40 & deg < -30) = 0.55;
vm(deg >= -30) = min(vm(deg >= -30), 0.95);
vm(ctx.ref) = ctx.bus(ctx.ref, VM);
target = [va(ctx.idx_va); vm(ctx.idx_vm)];
x0 = target;

function [x, balance_inf, total_it] = solve_regularized(ctx, target, x0)
nva = length(ctx.idx_va);
nvm = length(ctx.idx_vm);
lb = [-pi * ones(nva, 1); 0.08 * ones(nvm, 1)];
ub = [ pi * ones(nva, 1); 1.50 * ones(nvm, 1)];
opt = optimoptions('lsqnonlin', 'Display', 'off', ...
    'MaxIterations', 300, 'MaxFunctionEvaluations', 80000, ...
    'FunctionTolerance', 1e-12, 'StepTolerance', 1e-12, ...
    'OptimalityTolerance', 1e-12);
x = x0;
total_it = 0;
weights = [10 3 1 0.3 0.1 0.03 0.01 0.003 0.001 0];
for kk = 1:length(weights)
    w = weights(kk);
    if w > 0
        fcn = @(z) [active_set_mismatch(z, ctx); sqrt(w) * (z - target)];
    else
        fcn = @(z) active_set_mismatch(z, ctx);
    end
    [x, ~, ~, ~, out] = lsqnonlin(fcn, x, lb, ub, opt);
    if isfield(out, 'iterations')
        total_it = total_it + out.iterations;
    end
end
balance_inf = max(abs(active_set_mismatch(x, ctx)));

function F = active_set_mismatch(x, ctx)
[V, bus] = unpack_solution(x, ctx.bus, ctx.idx_va, ctx.idx_vm);
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
vm = abs(V);
scale = mp.psse_pqbrak_scale(vm, ctx.pqbrak);
bus(:, PD) = ctx.pd0 .* scale + ctx.base_pd_extra;
bus(:, QD) = ctx.qd0 .* scale + ctx.base_qd_extra;
for kk = find(ctx.facts.controllable(:))'
    ib = ctx.facts.bus_idx(kk);
    rb = ctx.facts.reg_bus_idx(kk);
    if ib > 0 && rb > 0 && ib <= length(vm) && rb <= length(vm)
        qlim = ctx.facts.shmx(kk) * vm(ib);
        direction = sign(ctx.facts.vset(kk) - vm(rb));
        if direction == 0
            direction = 1;
        end
        bus(ib, QD) = bus(ib, QD) - direction * qlim;
    end
end
Sbus = makeSbus(ctx.baseMVA, bus, ctx.gen);
mis = V .* conj(ctx.Ybus * V) - Sbus;
F = [real(mis([ctx.pv; ctx.pq])); imag(mis(ctx.pq))];

function results = build_results(mpci, ctx, x, swdev_collapse, report)
[V, bus] = unpack_solution(x, ctx.bus, ctx.idx_va, ctx.idx_vm);
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
vm = abs(V);
scale = mp.psse_pqbrak_scale(vm, ctx.pqbrak);
bus(:, PD) = ctx.pd0 .* scale + ctx.base_pd_extra;
bus(:, QD) = ctx.qd0 .* scale + ctx.base_qd_extra;
facts = ctx.facts;
facts.current_q(:) = 0;
for kk = find(facts.controllable(:))'
    ib = facts.bus_idx(kk);
    rb = facts.reg_bus_idx(kk);
    qlim = facts.shmx(kk) * vm(ib);
    direction = sign(facts.vset(kk) - vm(rb));
    if direction == 0
        direction = 1;
    end
    facts.current_q(kk) = direction * qlim;
end
mpci.bus = bus;
mpci.psse.pqbrak.scale = scale;
mpci.psse.pqbrak.iterations = report.iterations;
mpci.psse.pqbrak.changed_last = nnz(scale < 1);
mpci = mp.psse_facts_update(mpci, facts);
[Ybus, Yf, Yt] = makeYbus(mpci.baseMVA, mpci.bus, mpci.branch);
[bus, gen, branch] = pfsoln(mpci.baseMVA, mpci.bus, mpci.gen, ...
    mpci.branch, Ybus, Yf, Yt, V, ctx.ref, ctx.pv, ctx.pq, ctx.mpopt);
mpci.bus = bus;
mpci.gen = gen;
mpci.branch = branch;
mpci.success = 1;
mpci.iterations = report.iterations;
mpci.et = 0;
results = int2ext(mpci);
if ~isempty(swdev_collapse) && isfield(swdev_collapse, 'active') && ...
        swdev_collapse.active && ~isempty(which('mp.psse_swdev_expand'))
    results = mp.psse_swdev_expand(results, swdev_collapse);
end

function [V, bus] = unpack_solution(x, bus, idx_va, idx_vm)
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
va = bus(:, VA) * pi / 180;
vm = bus(:, VM);
va(idx_va) = x(1:length(idx_va));
vm(idx_vm) = x(length(idx_va)+1:end);
V = vm .* exp(1j * va);
bus(:, VM) = vm;
bus(:, VA) = va * 180 / pi;
