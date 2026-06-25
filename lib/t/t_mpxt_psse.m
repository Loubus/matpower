function t_mpxt_psse(quiet)
% t_mpxt_psse - Tests mp.xt_psse extension.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 1
    quiet = 0;
end

num_tests = 477;

t_begin(num_tests, quiet);

[PQ, ~, ~, ~, ~, BUS_TYPE, PD, QD, ~, BS, ~, VM, VA] = idx_bus;
[~, ~, BR_R, BR_X, ~, ~, ~, ~, TAP] = idx_brch;
[GEN_BUS, PG, QG, ~, ~, ~, ~, GEN_STATUS, PMAX, PMIN] = idx_gen;
dci = idx_dcline;
mpopt = mpoption('verbose', 0, 'out.all', 0);

%% runpf_psse uses PSS/E task and matches runpf without PSS/E data
r0 = runpf('case9', mpopt);
r = runpf_psse('case9', mpopt);
t_ok(r.success, 'runpf_psse(case9) success');
t_ok(isa(r.task, 'mp.task_pf_psse'), 'runpf_psse uses mp.task_pf_psse');
t_is(r.bus(:, VM), r0.bus(:, VM), 10, 'runpf_psse matches runpf VM without psse data');
t_is(r.gen(:, QG), r0.gen(:, QG), 10, 'runpf_psse matches runpf QG without psse data');

%% runcpf_psse uses PSS/E CPF task and preserves native CPF packaging
[r, success] = runcpf_psse('case9', 'case9target', mpopt);
t_ok(success, 'runcpf_psse(case9, case9target) success');
t_ok(isfield(r, 'psse') && isfield(r.psse, 'cpf'), ...
    'runcpf_psse reports PSS/E CPF metadata');
t_ok(strcmp(r.psse.cpf.task_class, 'mp.task_cpf_psse'), ...
    'runcpf_psse uses mp.task_cpf_psse');

%% CPF with PSS/E control callbacks, fixed-lambda warmstarts and trace compaction
mpc = psse_case2_cpf_pqbrak();
target = mpc;
target.bus(2, [PD QD]) = [100 65];
target.gen(1, PG) = 100;
mpopt_cpf = mpoption(mpopt, 'cpf.step', 0.15, 'cpf.stop_at', 'FULL');
[r, success] = runcpf_psse(mpc, target, mpopt_cpf);
t_ok(success, 'runcpf_psse PSS/E control CPF success');
t_ok(strcmp(r.psse.cpf.task_class, 'mp.task_cpf_psse'), ...
    'PSS/E control CPF keeps CPF task class');
event_names = {};
if isfield(r, 'cpf') && isfield(r.cpf, 'events')
    event_names = {r.cpf.events.name};
end
t_ok(any(strncmp(event_names, 'PSSE_', 5)), ...
    'PSS/E control CPF logs PSSE events');
t_ok(any(abs(diff(r.cpf.lam)) <= 1e-10), ...
    'PSS/E control CPF repeats lambda for warmstart re-correction');
has_pqbrak = isfield(r, 'psse') && isfield(r.psse, 'pqbrak') && ...
    isfield(r.psse.pqbrak, 'control');
t_ok(has_pqbrak, 'PSS/E control CPF exposes PQBRAK report');
if has_pqbrak
    pq = r.psse.pqbrak.control;
else
    pq = struct('scale', 1);
end
t_ok(any(pq.scale < 1), 'PSS/E control CPF applies low-voltage load scaling');
t_ok(isfield(r, 'cpf_psse_compact') && ...
    r.cpf_psse_compact.compaction.removed_points > 0, ...
    'PSS/E control CPF compact trace removes repeated lambda points');
t_is(r.psse.cpf.compact_trace.removed_points, ...
    r.cpf_psse_compact.compaction.removed_points, 10, ...
    'PSS/E control CPF reports compact trace metadata');

%% PSS/E CPF generator redispatch uses dynamic technology participation
mpcr = loadcase('case9');
mpcr.gen = [mpcr.gen; mpcr.gen(2, :); mpcr.gen(2, :)];
mpcr.gen(:, GEN_BUS) = [1; 2; 3; 5; 6];
mpcr.gen(:, PG) = [80; 40; 50; 20; 30];
mpcr.gen(:, PMAX) = [250; 100; 50; 70; 200];
mpcr.gen(:, PMIN) = 0;
mpcr.gen(:, GEN_STATUS) = 1;
mpcr.bus(5, BUS_TYPE) = 2;
mpcr.bus(6, BUS_TYPE) = 2;
targetr = mpcr;
targetr.bus(:, PD) = targetr.bus(:, PD) + 10;
currentr = mpcr;
currentr.bus(:, PD) = mpcr.bus(:, PD) + ...
    0.1 * (targetr.bus(:, PD) - mpcr.bus(:, PD));
tech = repmat({'thermal'}, size(mpcr.gen, 1), 1);
tech([2 3 4 5]) = {'hydraulic'; 'combined_cycle'; 'thermal'; 'wind'};
mpcr.cpf_policies.gen = struct( ...
    'policy', 'technology_dynamic_participation', ...
    'rho', 0.40, ...
    'gens', [2; 3; 4; 5], ...
    'technology', {tech}, ...
    'technology_weights', struct('hydraulic', 0.40, ...
        'combined_cycle', 0.35, 'thermal', 0.15, ...
        'gas_small', 0.10, 'wind', 0), ...
    'exclude_technologies', {{'wind'}});
[srcr, ~, str, changed, changed_idx] = ...
    cpf_gen_redispatch_policy_state('apply', ...
    mpcr, currentr, targetr, mpopt, [], 0.1);
delta_pg = srcr.gen(:, PG) - currentr.gen(:, PG);
expected_delta = zeros(size(mpcr.gen, 1), 1);
expected_delta(2) = 3.6 * 0.40 / (0.40 + 0.15);
expected_delta(4) = 3.6 * 0.15 / (0.40 + 0.15);
t_ok(changed, 'CPF technology redispatch helper changes PG');
t_is(changed_idx, [2; 4], 12, ...
    'CPF technology redispatch skips exhausted and wind technologies');
t_is(str.last_report.dP_load, 9, 12, ...
    'CPF technology redispatch uses accepted active-load increment');
t_is(str.last_report.scheduled_mw, 3.6, 12, ...
    'CPF technology redispatch applies rho to load increment');
t_is(delta_pg, expected_delta, 12, ...
    'CPF technology redispatch reallocates by available technology');

mpcm = loadcase('case9');
mpcm.gen = [mpcm.gen; mpcm.gen(2, :); mpcm.gen(2, :)];
mpcm.gencost = [mpcm.gencost; mpcm.gencost(2, :); mpcm.gencost(2, :)];
mpcm.gen(:, GEN_BUS) = [1; 2; 3; 5; 6];
mpcm.gen(:, PG) = [80; 40; 0; 20; 20];
mpcm.gen(:, PMAX) = [250; 100; 50; 100; 100];
mpcm.gen(:, PMIN) = 0;
mpcm.gen(:, GEN_STATUS) = [1; 1; 0; 1; 1];
mpcm.bus(5, BUS_TYPE) = 2;
mpcm.bus(6, BUS_TYPE) = 2;
targetm = mpcm;
targetm.bus(:, PD) = targetm.bus(:, PD) + 10;
currentm = mpcm;
currentm.bus(:, PD) = mpcm.bus(:, PD) + ...
    0.1 * (targetm.bus(:, PD) - mpcm.bus(:, PD));
mpcm.cpf_policies.gen = struct( ...
    'policy', 'technology_dynamic_participation', ...
    'rho', 0.40, ...
    'technology', {{'slack'; 'hydraulic'; 'thermal'; ...
        'wind'; 'thermal'}}, ...
    'technology_weights', struct('slack', 0, 'hydraulic', 0.40, ...
        'thermal', 0.15, 'wind', 0), ...
    'exclude_technologies', {{'wind'}});
targetm.cpf_policies = mpcm.cpf_policies;
currentm.cpf_policies = mpcm.cpf_policies;
mpcm_i = ext2int(mpcm);
currentm_i = ext2int(currentm);
targetm_i = ext2int(targetm);
[srcm_i, ~, ~, changed, changed_idx] = ...
    cpf_gen_redispatch_policy_state('apply', ...
    mpcm_i, currentm_i, targetm_i, mpopt, [], 0.1);
on = mpcm_i.order.gen.status.on(mpcm_i.order.gen.i2e);
wind_i = find(on == 4);
thermal_i = find(on == 5);
t_ok(changed, ...
    'CPF technology redispatch ext2int remapping applies redispatch');
t_ok(~ismember(wind_i, changed_idx) && ismember(thermal_i, changed_idx), ...
    'CPF technology redispatch ext2int remapping keeps wind excluded');
t_is(srcm_i.gen(wind_i, PG), currentm_i.gen(wind_i, PG), 12, ...
    'CPF technology redispatch ext2int remapping leaves wind PG fixed');

mpcr = loadcase('case9');
targetr = loadcase('case9target');
targetr.gen(:, PG) = mpcr.gen(:, PG);
mpcr.cpf_policies.gen = struct( ...
    'policy', 'technology_dynamic_participation', ...
    'rho', 0.40, ...
    'gens', [2; 3], ...
    'technology', {{'slack'; 'hydraulic'; 'wind'}}, ...
    'technology_weights', struct('hydraulic', 0.40, ...
        'combined_cycle', 0.35, 'thermal', 0.15, ...
        'gas_small', 0.10, 'wind', 0), ...
    'exclude_technologies', {{'wind'}});
targetr.cpf_policies = mpcr.cpf_policies;
mpopt_redisp = mpoption(mpopt, 'cpf.stop_at', 0.1, ...
    'cpf.step', 0.05, 'cpf.step_max', 0.05, 'cpf.adapt_step', 0);
[rredisp, success] = runcpf_psse(mpcr, targetr, mpopt_redisp);
event_names = {rredisp.cpf.events.name};
t_ok(success, 'runcpf_psse technology redispatch CPF succeeds');
t_ok(any(strcmp(event_names, 'PSSE_GEN_REDISPATCH')), ...
    'runcpf_psse logs generator redispatch events');
t_is(rredisp.psse.gen_redispatch.last_report.rho, 0.40, 12, ...
    'runcpf_psse generator redispatch reports rho');
t_is(rredisp.gen(3, PG), mpcr.gen(3, PG), 10, ...
    'runcpf_psse generator redispatch leaves wind PG fixed');
t_is(rredisp.gen(2, PG) - mpcr.gen(2, PG), ...
    rredisp.psse.gen_redispatch.applied_total_mw, 8, ...
    'runcpf_psse generator redispatch reports applied PG');
t_ok(rredisp.psse.gen_redispatch.applied_total_mw > 0, ...
    'runcpf_psse generator redispatch moves eligible generation');

%% Non-VSC CPF generator capability separates P and Q freezes
mpcg = loadcase('case9');
targetg = loadcase('case9target');
mpcg.gen_capability.Snom = [999; 220; 999];
targetg.gen_capability.Snom = mpcg.gen_capability.Snom;
mpcg.gen_capability.type = {'thermal'; 'thermal'; 'thermal'};
targetg.gen_capability.type = mpcg.gen_capability.type;
mpopt_gcap = mpoption(mpopt, 'cpf.stop_at', 'FULL', ...
    'cpf.step', 0.02, 'cpf.step_max', 0.02, ...
    'cpf.enforce_q_lims', 0);
mpopt_gcap.vsc_mtdc.capability_gen_enforce = 1;
[rgcap, success] = runcpf_psse(mpcg, targetg, mpopt_gcap);
gcap_state = rgcap.psse.gen_capability;
t_ok(success, ...
    'runcpf_psse non-VSC gen capability traces FULL continuation');
t_ok(gcap_state.frozen_p(2), ...
    'runcpf_psse non-VSC gen capability freezes active dispatch at P limit');
t_ok(gcap_state.frozen_q(2), ...
    'runcpf_psse non-VSC gen capability later freezes reactive dispatch at Q limit');
t_is(rgcap.gen(2, PG), 176, 8, ...
    'runcpf_psse non-VSC gen capability clamps PG at P boundary');
t_is(rgcap.gen(2, QG), 132, 8, ...
    'runcpf_psse non-VSC gen capability clamps QG at Q boundary');
t_ok(rgcap.bus(2, BUS_TYPE) == PQ, ...
    'gen capability Q-limited bus is converted to PQ');

%% CPF target sync preserves active dcline transfer deltas
base_ref = psse_case4_twodc_current_mode(0);
base = base_ref;
base.dcline(1, [dci.PF dci.PT]) = [30 29.9];
target = base_ref;
target.dcline(1, [dci.PF dci.PT]) = ...
    base_ref.dcline(1, [dci.PF dci.PT]) + [7 6.5];
target = mp.psse_sync_cpf_target(base, target, base_ref);
t_is(target.dcline(1, [dci.PF dci.PT]), [37 36.4], 10, ...
    'psse_sync_cpf_target preserves active dcline CPF delta');
t_is(target.psse.cpf_dcline_delta, [7 6.5], 10, ...
    'psse_sync_cpf_target records active dcline CPF delta');

%% SWDEV expansion restores CPF voltage traces to original bus topology
swres = psse_swdev_expand_fixture();
expanded = mp.psse_swdev_expand(swres.results, swres.state);
t_is(size(expanded.bus, 1), 3, 10, 'SWDEV expansion restores bus rows');
t_is(size(expanded.branch, 1), 2, 10, 'SWDEV expansion restores branch rows');
t_is(size(expanded.cpf.V, 1), 3, 10, 'SWDEV expansion restores cpf.V rows');
t_is(expanded.cpf.V(3, :), swres.results.cpf.V(2, :), 10, ...
    'SWDEV expansion maps collapsed cpf.V row');
t_is(expanded.cpf.V_hat(3, :), swres.results.cpf.V_hat(2, :), 10, ...
    'SWDEV expansion maps collapsed cpf.V_hat row');

%% General THRSHZ branch collapse solves internally and expands for reporting
mpc = psse_case3_low_z_branch();
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'runpf_psse succeeds with FLATST after THRSHZ branch collapse');
t_is(size(r.bus, 1), 3, 10, 'branch collapse expansion restores bus rows');
t_is(size(r.branch, 1), 2, 10, 'branch collapse expansion restores branch rows');
t_ok(isfield(r.psse, 'branch_collapsed') && r.psse.branch_collapsed.active, ...
    'runpf_psse reports THRSHZ branch collapse');
t_is(r.bus(2, VM), r.bus(3, VM), 10, ...
    'collapsed low-impedance buses share solved voltage after expansion');

mpc = psse_case3_low_z_branch_with_xfmr_bus();
[mpc2, collapse_state] = mp.psse_branch_collapse(mpc);
t_ok(~collapse_state.active, ...
    'branch collapse skips low-Z branches touching transformer metadata buses');
t_is(size(mpc2.bus, 1), 3, 10, ...
    'transformer-protected low-Z branch does not remove bus rows');
t_is(size(mpc2.branch, 1), 2, 10, ...
    'transformer-protected low-Z branch does not remove branch rows');

%% PSS/E SYSTEM-WIDE solver option policy report
mpc = loadcase('case9');
mpc.psse.rev = 34;
mpc.psse.system.solver = struct('METHOD', 'FNSL', 'ACTAPS', 0, ...
    'AREAIN', 0, 'PHSHFT', 0, 'DCTAPS', 1, 'SWSHNT', 2, ...
    'FLATST', 0, 'VARLIM', 0, 'NONDIV', 0);
mpc.psse.system.newton = struct('ITMXN', 40, 'ACCN', 0.5, ...
    'TOLN', 1.0, 'VCTOLQ', 0.1, 'VCTOLV', 1e-5, ...
    'DVLIM', 0.99, 'NDVFCT', 0.99);
mpc.psse.system.adjust = struct('ADJTHR', 0.005, 'ACCTAP', 1.0, ...
    'TAPLIM', 0.05, 'SWVBND', 100.0, 'MXTPSS', 99, 'MXSWIM', 10);
r = runpf_psse(mpc, mpopt);
policy = r.psse.solver_options;
t_ok(isfield(r, 'psse') && isfield(r.psse, 'solver_options'), ...
    'runpf_psse reports PSS/E SYSTEM-WIDE solver options');
t_ok(isfield(policy, 'raw') && isfield(policy.raw, 'solver'), ...
    'solver_options preserves raw sections');
t_is(policy.raw.solver.SWSHNT, 2, 12, 'solver_options raw SOLVER.SWSHNT');
t_is(policy.raw.newton.ITMXN, 40, 12, 'solver_options raw NEWTON.ITMXN');
t_is(policy.raw.adjust.MXTPSS, 99, 12, 'solver_options raw ADJUST.MXTPSS');
t_ok(isfield(policy, 'effective'), ...
    'solver_options reports effective PSS/E SYSTEM-WIDE parameters');
t_ok(psse_policy_has(policy.effective, 'general', 'THRSHZ'), ...
    'solver_options effective includes GENERAL.THRSHZ default');
t_is(psse_policy_value(policy.effective, 'general', 'THRSHZ'), 0.0001, 12, ...
    'solver_options effective GENERAL.THRSHZ default value');
t_is(psse_policy_value(policy.effective, 'newton', 'TOLN'), 1.0, 12, ...
    'solver_options effective NEWTON.TOLN uses RAW explicit value');
t_is(psse_policy_value(policy.effective, 'adjust', 'MXTPSS'), 99, 12, ...
    'solver_options effective ADJUST.MXTPSS uses RAW explicit value');
t_ok(strcmp(psse_policy_origin(policy.effective, 'newton', 'TOLN'), ...
        'raw_explicit'), ...
    'solver_options effective marks explicit RAW origin');
t_ok(strcmp(psse_policy_origin(policy.effective, 'general', 'THRSHZ'), ...
        'psse_default'), ...
    'solver_options effective marks PSS/E default origin');
t_ok(psse_policy_has(policy.applied, 'solver', 'METHOD'), ...
    'solver_options classifies SOLVER.FNSL as applied');
t_ok(psse_policy_has(policy.applied, 'solver', 'ACTAPS'), ...
    'solver_options classifies SOLVER.ACTAPS as applied');
t_ok(psse_policy_has(policy.applied, 'solver', 'AREAIN'), ...
    'solver_options classifies SOLVER.AREAIN=0 as applied inactive');
t_ok(psse_policy_has(policy.applied, 'solver', 'PHSHFT'), ...
    'solver_options classifies SOLVER.PHSHFT=0 as applied inactive');
t_ok(psse_policy_has(policy.applied, 'solver', 'DCTAPS'), ...
    'solver_options classifies SOLVER.DCTAPS as applied');
t_ok(psse_policy_has(policy.applied, 'solver', 'SWSHNT'), ...
    'solver_options classifies SOLVER.SWSHNT as applied');
t_ok(psse_policy_has(policy.applied, 'solver', 'FLATST'), ...
    'solver_options classifies SOLVER.FLATST=0 as applied');
t_ok(psse_policy_has(policy.applied, 'solver', 'VARLIM'), ...
    'solver_options classifies SOLVER.VARLIM as applied');
t_ok(psse_policy_has(policy.applied, 'solver', 'NONDIV'), ...
    'solver_options classifies SOLVER.NONDIV=0 as applied inactive');
t_ok(psse_policy_has(policy.applied, 'newton', 'VCTOLV'), ...
    'solver_options classifies NEWTON.VCTOLV as applied');
t_ok(psse_policy_has(policy.applied, 'newton', 'VCTOLQ'), ...
    'solver_options classifies NEWTON.VCTOLQ as applied');
t_ok(psse_policy_has(policy.applied, 'adjust', 'MXTPSS'), ...
    'solver_options classifies ADJUST.MXTPSS as applied');
t_ok(psse_policy_has(policy.applied, 'newton', 'ITMXN'), ...
    'solver_options classifies NEWTON.ITMXN as applied');
t_ok(psse_policy_has(policy.fallback, 'newton', 'TOLN'), ...
    'solver_options classifies NEWTON.TOLN as fallback');
t_ok(psse_policy_has(policy.ignored, 'newton', 'ACCN'), ...
    'solver_options classifies NEWTON.ACCN as ignored');
t_ok(psse_policy_has(policy.ignored, 'adjust', 'ADJTHR'), ...
    'solver_options classifies ADJUST.ADJTHR as ignored');
t_ok(psse_policy_has(policy.ignored, 'adjust', 'ACCTAP'), ...
    'solver_options classifies ADJUST.ACCTAP as ignored');
t_ok(psse_policy_has(policy.ignored, 'adjust', 'TAPLIM'), ...
    'solver_options classifies ADJUST.TAPLIM as ignored');
t_ok(psse_policy_has(policy.ignored, 'adjust', 'SWVBND'), ...
    'solver_options classifies ADJUST.SWVBND as ignored');
t_ok(psse_policy_has(policy.unsupported, 'newton', 'DVLIM'), ...
    'solver_options classifies NEWTON.DVLIM as unsupported');
t_ok(psse_policy_has(policy.unsupported, 'newton', 'NDVFCT'), ...
    'solver_options classifies NEWTON.NDVFCT as unsupported');
t_ok(psse_policy_has(policy.unsupported, 'adjust', 'MXSWIM'), ...
    'solver_options classifies ADJUST.MXSWIM as unsupported');
mpc.psse.system.solver.PHSHFT = 1;
mpc.psse.system.solver.AREAIN = 1;
mpc.psse.system.solver.FLATST = 1;
mpc.psse.system.solver.NONDIV = 1;
[~, policy2] = mp.psse_solver_options(mpopt, mpc);
t_ok(psse_policy_has(policy2.unsupported, 'solver', 'PHSHFT'), ...
    'solver_options classifies active PHSHFT as unsupported');
t_ok(psse_policy_has(policy2.unsupported, 'solver', 'AREAIN'), ...
    'solver_options classifies active AREAIN as unsupported');
t_ok(psse_policy_has(policy2.applied, 'solver', 'FLATST'), ...
    'solver_options classifies FLATST=1 as applied');
t_ok(psse_policy_has(policy2.unsupported, 'solver', 'NONDIV'), ...
    'solver_options classifies active NONDIV as unsupported');

mpc_map = mpc;
mpc_map.psse.system.solver.PHSHFT = 0;
mpc_map.psse.system.solver.AREAIN = 0;
mpc_map.psse.system.solver.FLATST = 0;
mpc_map.psse.system.solver.NONDIV = 0;
[mpopt_map, ~] = mp.psse_solver_options( ...
    mpoption(mpopt, 'pf.alg', 'FDXB', 'pf.nr.max_it', 10), mpc_map);
t_ok(strcmpi(mpopt_map.pf.alg, 'NR'), ...
    'solver_options maps SOLVER.FNSL to NR');
t_is(mpopt_map.pf.nr.max_it, 40, 12, ...
    'solver_options maps NEWTON.ITMXN to pf.nr.max_it');

mpc_flat = mpc_map;
mpc_flat.psse.system.solver.FLATST = 1;
mpc_flat.bus(:, VM) = 0.9 + (1:size(mpc_flat.bus, 1))' / 100;
mpc_flat.bus(:, VA) = (-1:-1:-size(mpc_flat.bus, 1))';
vm0 = mpc_flat.bus(:, VM);
is_pq = mpc_flat.bus(:, BUS_TYPE) == PQ;
[~, ~, mpc_flat] = mp.psse_solver_options(mpopt, mpc_flat);
t_is(mpc_flat.bus(:, VA), zeros(size(mpc_flat.bus, 1), 1), 12, ...
    'solver_options FLATST=1 zeros initial voltage angles');
t_is(mpc_flat.bus(is_pq, VM), ones(sum(is_pq), 1), 12, ...
    'solver_options FLATST=1 uses 1.0 pu for PQ buses');
t_is(mpc_flat.bus(~is_pq, VM), vm0(~is_pq), 12, ...
    'solver_options FLATST=1 preserves voltage-controlled magnitudes');

mpc_default = loadcase('case9');
mpc_default.psse.rev = 34;
[~, policy_default] = mp.psse_solver_options(mpopt, mpc_default);
mpc_default.psse.solver_options = policy_default;
defs = mp.psse_system_defaults();
t_is(psse_default_value(defs, 'adjust', 'MXTPSS'), 100, 12, ...
    'psse_system_defaults documents ADJUST.MXTPSS CLI default');
t_is(psse_default_value(defs, 'general', 'PQBRAK'), 0.7, 12, ...
    'psse_system_defaults documents GENERAL.PQBRAK default');
t_ok(psse_policy_has(policy_default.effective, 'general', 'THRSHZ'), ...
    'solver_options defaults appear without RAW SYSTEM-WIDE records');
t_is(psse_policy_value(policy_default.effective, 'newton', 'ACCN'), 1, 12, ...
    'solver_options default NEWTON.ACCN');
t_is(psse_policy_value(policy_default.effective, 'solver', 'ACTAPS'), 1, 12, ...
    'solver_options default SOLVER.ACTAPS');
t_is(psse_policy_value(policy_default.effective, 'newton', 'ITMXN'), 20, 12, ...
    'solver_options default NEWTON.ITMXN');
t_is(psse_policy_value(policy_default.effective, 'newton', 'TOLN'), 0.1, 12, ...
    'solver_options default NEWTON.TOLN');
t_is(psse_policy_value(policy_default.effective, 'newton', 'DVLIM'), 0.99, 12, ...
    'solver_options default NEWTON.DVLIM');
t_is(psse_policy_value(policy_default.effective, 'adjust', 'MXTPSS'), 100, 12, ...
    'solver_options effective ADJUST.MXTPSS runner default');
t_ok(strcmp(psse_policy_origin(policy_default.effective, 'adjust', 'MXTPSS'), ...
        'psse_default'), ...
    'solver_options default ADJUST.MXTPSS origin');
t_is(mp.psse_system_value(mpc_default, 'adjust', 'MXTPSS', 99), 100, 12, ...
    'psse_system_value uses effective ADJUST.MXTPSS default');
t_is(mp.psse_system_value(mpc_default, 'newton', 'VCTOLV', 0), 1e-5, 12, ...
    'psse_system_value uses effective NEWTON.VCTOLV default');
t_is(mp.psse_system_value(mpc_default, 'newton', 'VCTOLQ', 0), 0.1, 12, ...
    'psse_system_value uses effective NEWTON.VCTOLQ default');
t_ok(isnan(mp.psse_system_value(mpc_default, 'solver', 'ACTAPS', NaN, 0)), ...
    'psse_system_value can skip effective default for sensitive gates');
mpc_default.psse.system.solver.ACTAPS = 0;
t_is(mp.psse_system_value(mpc_default, 'solver', 'ACTAPS', NaN, 0), 0, 12, ...
    'psse_system_value raw-only mode keeps explicit sensitive gate value');
mpc_default.psse.system.adjust.MXTPSS = 25;
t_is(mp.psse_system_value(mpc_default, 'adjust', 'MXTPSS', 99), 25, 12, ...
    'psse_system_value keeps explicit RAW priority');
t_ok(psse_policy_has(policy_default.applied, 'general', 'THRSHZ'), ...
    'solver_options classifies default GENERAL.THRSHZ as applied');
t_ok(psse_policy_has(policy_default.fallback, 'solver', 'ACTAPS'), ...
    'solver_options classifies default SOLVER.ACTAPS as fallback');
t_ok(psse_policy_has(policy_default.fallback, 'solver', 'DCTAPS'), ...
    'solver_options classifies default SOLVER.DCTAPS as fallback');
t_ok(psse_policy_has(policy_default.fallback, 'solver', 'SWSHNT'), ...
    'solver_options classifies default SOLVER.SWSHNT as fallback');
t_ok(psse_policy_has(policy_default.fallback, 'solver', 'VARLIM'), ...
    'solver_options classifies default SOLVER.VARLIM as fallback');
t_ok(psse_policy_has(policy_default.ignored, 'newton', 'ACCN'), ...
    'solver_options classifies default NEWTON.ACCN as ignored');
t_ok(psse_policy_has(policy_default.fallback, 'newton', 'TOLN'), ...
    'solver_options classifies default NEWTON.TOLN as fallback');
t_ok(psse_policy_has(policy_default.unsupported, 'newton', 'DVLIM'), ...
    'solver_options classifies default NEWTON.DVLIM as unsupported');
t_ok(psse_policy_has(policy_default.ignored, 'adjust', 'ADJTHR'), ...
    'solver_options classifies default ADJUST.ADJTHR as ignored');
t_ok(psse_policy_has(policy_default.unsupported, 'adjust', 'MXSWIM'), ...
    'solver_options classifies default ADJUST.MXSWIM as unsupported');
t_ok(psse_policy_has(policy_default.applied, 'newton', 'VCTOLV'), ...
    'solver_options classifies default NEWTON.VCTOLV as applied');
t_ok(psse_policy_has(policy_default.applied, 'adjust', 'MXTPSS'), ...
    'solver_options classifies default ADJUST.MXTPSS as applied');

mpc_sw_default = psse_case9_swshunt(1, 1, 0, 1.03, 0.99, 9, 0, [1 10], 1);
mpc_sw_default.psse.system.adjust = struct();
[~, policy_sw_default] = mp.psse_solver_options(mpopt, mpc_sw_default);
mpc_sw_default.psse.solver_options = policy_sw_default;
state_sw_default = mp.psse_swshunt_states(mpc_sw_default);
t_is(state_sw_default.max_iter, 100, 12, ...
    'switched shunt state uses effective ADJUST.MXTPSS default');
mpc_sw_explicit = psse_case9_swshunt(1, 1, 0, 1.03, 0.99, 9, 0, [1 10], 1);
[~, policy_sw_explicit] = mp.psse_solver_options(mpopt, mpc_sw_explicit);
mpc_sw_explicit.psse.solver_options = policy_sw_explicit;
state_sw_explicit = mp.psse_swshunt_states(mpc_sw_explicit);
t_is(state_sw_explicit.max_iter, 10, 12, ...
    'switched shunt state keeps explicit ADJUST.MXTPSS value');

%% PSS/E GENERATOR DATA Q limits and remote regulation validation RAWs
genq_dir = psse_genq_audit_dir();
t_ok(exist(genq_dir, 'dir') == 7, 'GENQ PSS/E validation directory exists');
genq_cases = psse_genq_validation_cases();
if exist(genq_dir, 'dir') ~= 7
    t_skip(18 * length(genq_cases), 'GENQ PSS/E validation directory missing');
else
    for k = 1:length(genq_cases)
        tc = genq_cases{k};
        raw_file = fullfile(genq_dir, tc.raw);
        if exist(raw_file, 'file') ~= 2
            t_skip(18, sprintf('%s missing', tc.name));
            continue;
        end
        mpc = psse2mpc(raw_file, 0, 34);
        r = runpf_psse(mpc, mpopt);
        psse_check_genq_case(r, tc);
    end

    %% VARLIM = 0 still enables PSS/E generator reactive limit handling
    tc = genq_cases{4};
    raw_file = fullfile(genq_dir, tc.raw);
    if exist(raw_file, 'file') ~= 2
        t_skip(18, sprintf('%s VARLIM=0 missing', tc.name));
    else
        mpc = psse2mpc(raw_file, 0, 34);
        mpc.psse.system.solver.VARLIM = 0;
        tc.name = [tc.name ' VARLIM=0'];
        r = runpf_psse(mpc, mpopt);
        psse_check_genq_case(r, tc);
    end

    %% GENQ must not assume external bus numbers are consecutive row indices
    tc = genq_cases{6};
    raw_file = fullfile(genq_dir, tc.raw);
    if exist(raw_file, 'file') ~= 2
        t_skip(18, sprintf('%s external bus numbering missing', tc.name));
    else
        old_bus = (1:4)';
        new_bus = [101; 203; 307; 409];
        mpc = psse2mpc(raw_file, 0, 34);
        mpc = psse_remap_bus_numbers(mpc, old_bus, new_bus);
        tc.name = [tc.name ' external bus numbering'];
        tc.bus_ext = psse_remap_values(tc.bus_ext, old_bus, new_bus);
        tc.reg_bus_ext = psse_remap_values(tc.reg_bus_ext, old_bus, new_bus);
        r = runpf_psse(mpc, mpopt);
        psse_check_genq_case(r, tc);
    end
end

%% coordinated active-set fallback is explicit and reported for coupled cases
cas_raw = psse_auditoria_case_file(fullfile( ...
    'psse_validation_cases_integrated', 'psse_integrated_controls_40bus.raw'));
if exist(cas_raw, 'file') ~= 2 || isempty(which('lsqnonlin'))
    t_skip(5, 'coordinated active-set fixture or lsqnonlin missing');
else
    mpc = psse2mpc(cas_raw, 0, 34);
    mpopt_cas = mpopt;
    mpopt_cas.exp.psse_coordinated_active_set = 1;
    r = psse_runpf_quiet_singular(mpc, mpopt_cas);
    has_cas = isfield(r, 'psse') && ...
        isfield(r.psse, 'coordinated_active_set');
    t_ok(r.success, 'coordinated active-set integrated 40bus success');
    t_ok(has_cas && r.psse.coordinated_active_set.attempted == 1, ...
        'coordinated active-set report attempted');
    if has_cas
        cas = r.psse.coordinated_active_set;
    else
        cas = struct('trigger', '', 'iterations', 0, 'balance_inf', Inf);
    end
    t_ok(strcmp(cas.trigger, 'genq_post_control_power_flow'), ...
        'coordinated active-set records GENQ trigger');
    t_ok(cas.iterations > 0 && cas.balance_inf < 1e-6, ...
        'coordinated active-set converges tightly');
    t_ok(isfield(cas, 'original_control_failure') && ...
        isfield(cas.original_control_failure, 'stage'), ...
        'coordinated active-set preserves original failure diagnostics');
end

%% MODSW = 1, BINIT = 0, creates a shunt row through data model rebuild
mpc = psse_case9_swshunt(1, 1, 0, 1.02, 1.01, 9, 0, [2 25], 1);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'MODSW=1 success');
t_is(r.psse.swshunt.num(1, 10), 25, 10, 'MODSW=1 switched one capacitor step');
t_is(r.bus(9, BS), 25, 10, 'MODSW=1 updates bus BS from BINIT=0');
t_ok(r.psse.swshunt.control.inside_band == 1, 'MODSW=1 reaches voltage band');

mpc = psse_case2_swshunt_discrete();
r = runpf_psse(mpc, mpopt);
t_is(r.psse.swshunt.control.num_adjustments, 6, 10, ...
    'MODSW=1 ADJM=0 advances one block per adjustment');

%% SWSHNT = 0 disables automatic control
mpc = psse_case9_swshunt(1, 1, 0, 1.02, 1.01, 9, 0, [2 25], 0);
r = runpf_psse(mpc, mpopt);
t_is(r.psse.swshunt.num(1, 10), 0, 10, 'SWSHNT=0 leaves BINIT unchanged');
t_is(r.bus(9, BS), 0, 10, 'SWSHNT=0 leaves bus BS unchanged');
t_ok(~r.psse.swshunt.control.enabled, 'SWSHNT=0 report disabled');

%% SWSHNT = 2 controls continuous shunts, but leaves MODSW = 1 fixed
mpc = psse_case9_swshunt(1, 1, 0, 1.02, 1.01, 9, 0, [2 25], 2);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'SWSHNT=2 MODSW=1 success');
t_is(r.psse.swshunt.num(1, 10), 0, 10, 'SWSHNT=2 leaves MODSW=1 BINIT unchanged');
t_is(r.bus(9, BS), 0, 10, 'SWSHNT=2 leaves MODSW=1 bus BS unchanged');
t_is(r.psse.swshunt.control.controllable, 0, 10, 'SWSHNT=2 does not control MODSW=1');

%% MODSW = 0 and STAT = 0 remain fixed
mpc = psse_case9_swshunt(0, 1, 15, 1.02, 1.01, 9, 15, [2 25], 2);
r = runpf_psse(mpc, mpopt);
t_is(r.psse.swshunt.num(1, 10), 15, 10, 'MODSW=0 leaves BINIT fixed');
t_is(r.bus(9, BS), 15, 10, 'MODSW=0 leaves bus BS fixed');

mpc = psse_case9_swshunt(1, 0, 25, 1.02, 1.01, 9, 0, [2 25], 2);
r = runpf_psse(mpc, mpopt);
t_is(r.bus(9, BS), 0, 10, 'STAT=0 contributes no bus BS');
t_is(r.psse.swshunt.control.controllable, 0, 10, 'STAT=0 is not controllable');

%% MODSW = 2 is continuous within physical range
mpc = psse_case9_swshunt(2, 1, 0, 1.02, 1.02, 9, 0, [1 40], 2);
r = runpf_psse(mpc, mpopt);
b = r.psse.swshunt.num(1, 10);
t_ok(b > 0 && b < 40, 'MODSW=2 uses continuous B within range');

%% multiple shunts regulating the same bus are controlled as a group
rows = [
    8 1 0 1 1.02 1.01 9 100 0 0 1 25 0
    9 1 0 1 1.02 1.01 9 100 0 0 1 25 0
];
mpc = psse_case9_swshunts(rows, 1, 10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'grouped RMPCT success');
t_is(r.psse.swshunt.control.num_groups, 1, 10, 'grouped RMPCT has one regulated bus group');
t_is(r.psse.swshunt.control.multi_shunt_groups, 1, 10, 'grouped RMPCT reports multi-shunt group');
t_is(r.psse.swshunt.control.max_group_rmpct_sum, 200, 10, 'grouped RMPCT preserves literal sum');
t_is(r.psse.swshunt.num(:, 10), [25; 25], 10, 'grouped RMPCT moves both shunts together');

%% repeated BINIT states are resolved by selecting the best visited state
rows = [9 1 0 1 1.03 1.03 9 100 0 0 1 50 0];
mpc = psse_case9_swshunts(rows, 1, 10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'cycle memory success');
t_ok(r.psse.swshunt.control.cycle_detected, 'cycle memory detects repeated BINIT state');
t_ok(r.psse.swshunt.control.cycle_resolved, 'cycle memory resolves repeated BINIT state');
t_ok(r.psse.swshunt.control.cycle_resolution_changes > 0, ...
    'cycle memory applies best visited BINIT');

%% PSS/E FACTS MODE=1, J=0 STATCON control is opt-in via runpf_psse
mpc = psse_case3_facts_statcon(300, 0.98);
r0 = runpf(mpc, mpopt);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'FACTS STATCON success');
t_ok(r.bus(3, VM) > r0.bus(3, VM) + 1e-4, 'FACTS STATCON raises remote voltage');
t_is(r.bus(3, VM), 0.98, 4, 'FACTS STATCON reaches remote voltage target');
t_is(r.psse.facts.control.controllable, 1, 10, 'FACTS STATCON report controllable');
t_is(r.psse.facts.control.remote_regulated, 1, 10, 'FACTS STATCON report remote control');
t_ok(r.psse.facts.control.qinj(1) > 0, 'FACTS STATCON injects reactive power');
t_is(r.bus(2, QD), -r.psse.facts.control.qinj(1), 10, ...
    'FACTS STATCON applies reactive injection through bus QD');

mpc = psse_case3_facts_statcon(5, 1.05);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'FACTS STATCON limited success');
t_ok(r.psse.facts.control.at_max(1), 'FACTS STATCON upper SHMX limit reported');
t_ok(r.psse.facts.control.limited(1), 'FACTS STATCON reports voltage limited by SHMX');
t_ok(r.psse.facts.control.qinj(1) <= r.psse.facts.control.qmax(1) + 1e-7, ...
    'FACTS STATCON respects SHMX reactive limit');

%% PSS/E transformer tap control is gated by ACTAPS and COD
mpc = psse_case2_xfmr_tap(1, 1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'COD=1 transformer tap success');
t_is(r.branch(1, TAP), 0.95, 10, 'COD=1 transformer tap moves one step');
t_is(r.psse.xfmr.two.num(1, 24), 0.95, 10, 'COD=1 transformer WINDV updated');
t_ok(r.psse.xfmr.control.inside_band == 1, 'COD=1 transformer reaches voltage band');

mpc = psse_case2_xfmr_tap(1, 1, -2, 1.00, 1.10, 1.08, 1.2, 0.8, 9, 100, 50);
mpc.psse.system.adjust.MXTPSS = 1;
r = runpf_psse(mpc, mpopt);
t_ok(~r.success, 'unsettled transformer tap control fails runpf_psse');
t_ok(r.psse.xfmr.control.control_failed, 'unsettled transformer control reported failed');
t_ok(strcmp(r.psse.xfmr.control.failure_reason, 'max_iter_unresolved_violations'), ...
    'unsettled transformer control reports max-iteration reason');
t_ok(isfield(r.psse, 'control_failure') && ...
    strcmp(r.psse.control_failure.stage, 'control_settlement'), ...
    'unsettled transformer control records control-settlement failure');
t_ok(r.psse.control_failure.last_violations > 0, ...
    'unsettled transformer control reports remaining violations');

mpc = psse_case2_xfmr_tap(1, 1, -2, 1.00, 1.03, 0.95, 1.1, 0.9, 10, 0, 0);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'in-band off-grid transformer tap success');
t_is(r.branch(1, TAP), 1.011111111111111, 10, ...
    'in-band off-grid transformer tap snaps to grid');
t_is(r.psse.xfmr.two.num(1, 24), 1.011111111111111, 10, ...
    'in-band off-grid transformer WINDV snaps to grid');
t_ok(r.psse.xfmr.control.inside_band == 1, ...
    'in-band snapped transformer reports inside band');

mpc = psse_case2_xfmr_tab();
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TAB transformer correction success');
t_is(r.branch(1, TAP), 0.95, 10, 'TAB transformer tap moves one step');
t_is(r.branch(1, [BR_R BR_X]), [0.0095 0.095], 10, 'TAB updates branch R/X from corrected tap');
t_is(r.psse.xfmr.control.tab_corrected, 1, 10, 'TAB correction reported');

mpc = psse_case3_xfmr_tap_remote();
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.05, 10, 'remote transformer tap reaches voltage band');
t_ok(r.psse.xfmr.control.inside_band == 1, 'remote transformer reaches voltage band');

mpc = psse_case3_xfmr_tap_remote_limit();
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.10, 10, 'remote transformer tap reaches upper limit');
t_is(r.psse.xfmr.control.at_max, 1, 10, 'remote transformer upper limit reported');

mpc = psse_case3_xfmr_tap_remote_cont_pos();
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 0.95, 10, 'positive CONT remote transformer tap matches PSS/E direction');
t_ok(r.psse.xfmr.control.inside_band == 1, 'positive CONT remote transformer reaches voltage band');

mpc = psse_case2_xfmr_tap(1, 1, 2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 0.95, 10, 'positive CONT terminal transformer tap matches PSS/E direction');
t_ok(r.psse.xfmr.control.inside_band == 1, 'positive CONT terminal transformer reaches voltage band');

mpc = psse_case2_xfmr_tap(1, 1, 2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
mpc.branch(1, 1:2) = [2 1];
mpc.psse.xfmr.two.num(1, 1:2) = [2 1];
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.05, 10, 'positive CONT own-side transformer tap matches PSS/E direction');
t_ok(r.psse.xfmr.control.inside_band == 1, 'positive CONT own-side transformer reaches voltage band');

mpc = psse_case2_xfmr_tap(0, 1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.00, 10, 'ACTAPS=0 leaves transformer tap fixed');
t_ok(~r.psse.xfmr.control.enabled, 'ACTAPS=0 report disabled');

mpc = psse_case2_xfmr_tap(1, -1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 1.00, 10, 'COD=-1 suppresses automatic tap adjustment');
t_is(r.psse.xfmr.control.suppressed_auto, 1, 10, 'COD=-1 reported suppressed');

mpc = psse_case2_xfmr_tap(1, 1, -2, 0.90, 1.09, 1.08, 1.1, 0.9, 5, 100, 50);
r = runpf_psse(mpc, mpopt);
t_is(r.branch(1, TAP), 0.90, 10, 'transformer tap lower limit is respected');
t_is(r.psse.xfmr.control.at_min, 1, 10, 'transformer lower limit reported');

%% PSS/E two-terminal DC MDC=0 remains blocked
mpc = psse_case4_twodc_blocked();
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC MDC=0 success');
t_is(r.psse.twodc.control.active, 0, 10, 'TWO DC MDC=0 has no active links');
t_is(r.psse.twodc.control.supported, 0, 10, 'TWO DC MDC=0 has no supported control');
t_is(r.dcline(1, [dci.PF dci.PT dci.LOSS0]), [0 0 0], 10, ...
    'TWO DC MDC=0 keeps dcline blocked');
psse_is_close([r.psse.twodc.control.idc_ka(1) ...
        r.psse.twodc.control.qacr_mvar(1) ...
        r.psse.twodc.control.qaci_mvar(1) ...
        r.psse.twodc.control.vdcr_kv(1) ...
        r.psse.twodc.control.vdci_kv(1)], zeros(1, 5), 1e-10, ...
    'TWO DC MDC=0 reports zero DC quantities');
psse_is_close([r.psse.twodc.control.alpha_deg(1) ...
        r.psse.twodc.control.gamma_deg(1)], [90 90], 1e-10, ...
    'TWO DC MDC=0 reports PSS/E blocking angles');

mpc = psse_case4_twodc_unsupported_xcap();
base_dcline = mpc.dcline(1, [dci.PF dci.PT dci.LOSS0]);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC unsupported active row success');
t_is(r.psse.twodc.control.active, 1, 10, ...
    'TWO DC unsupported active row remains active');
t_is(r.psse.twodc.control.supported, 0, 10, ...
    'TWO DC unsupported active row is not modeled as LCC');
t_ok(strcmp(r.psse.twodc.control.control_flag{1}, 'NA'), ...
    'TWO DC unsupported active row is reported as not applied');
t_is(r.dcline(1, [dci.PF dci.PT dci.LOSS0]), base_dcline, 10, ...
    'TWO DC unsupported active row preserves the static dcline equivalent');

%% failed initial PQ probe defers TWODC without marking physical blocking
mpc = psse_case4_twodc_current_mode(0);
mpopt_bad_probe = mpoption(mpopt, 'pf.alg', 'NO_SUCH_ALG');
mpc_prep = mp.psse_twodc_prepare(mpc, mpopt_bad_probe);
t_ok(strcmp(mpc_prep.psse.twodc.prepare_mode, 'deferred_pq'), ...
    'TWO DC failed PQ probe uses deferred prepare mode');
t_is(mpc_prep.psse.twodc.prepare_deferred, 1, 10, ...
    'TWO DC failed PQ probe records deferred prepare flag');
t_is(mpc_prep.psse.twodc.pq_model_deferred, 1, 10, ...
    'TWO DC failed PQ probe records deferred PQ model flag');
t_is(double(mpc_prep.psse.twodc.initial_blocked), 0, 10, ...
    'TWO DC failed PQ probe does not mark initial block');
state_prep = mp.psse_twodc_states(mpc_prep);
t_is(double(state_prep.initial_blocked), 0, 10, ...
    'TWO DC state keeps deferred prepare separate from blocking');
t_is(double(state_prep.apply_model), 1, 10, ...
    'TWO DC deferred prepare keeps supported row modeled');

%% PSS/E two-terminal DC MDC=1 falls back to current control via VCMOD
mpc = psse_case4_twodc_mdc2_current_mode(0);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC MDC=2 current control success');
t_ok(strcmp(r.psse.twodc.control.mode{1}, 'current'), ...
    'TWO DC MDC=2 reports current mode');
t_is(r.psse.twodc.control.idc_ka(1), 0.1, 10, ...
    'TWO DC MDC=2 uses SETVL amps as current');
psse_is_close([r.dcline(1, dci.PF) -r.dcline(1, dci.PT)], ...
    [29.1 -29.1], 0.5, 'TWO DC MDC=2 no-loss PAC matches PSS/E current target');
psse_is_close([r.psse.twodc.control.tapr(1) ...
        r.psse.twodc.control.tapi(1)], ...
    [1.0125 0.9660], 5e-5, 'TWO DC MDC=2 taps match PSS/E current target');
psse_is_close([r.psse.twodc.control.alpha_deg(1) ...
        r.psse.twodc.control.gamma_deg(1)], ...
    [16.02 17.00], 0.1, 'TWO DC MDC=2 firing angles match PSS/E current target');

mpc = psse_case4_twodc_current_mode(0);
r0 = runpf(mpc, mpopt);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC current control success');
t_ok(r.psse.twodc.control.current_limited == 1, 'TWO DC current mode reported');
t_ok(r.dcline(1, dci.PF) < r0.dcline(1, dci.PF), ...
    'TWO DC current mode lowers active power from static setpoint');
t_is(r.dcline(1, dci.PF), r.psse.twodc.control.pf(1), 10, ...
    'TWO DC dcline result synchronized with control report');
t_is(r.psse.twodc.control.idc_ka(1), 0.1, 10, ...
    'TWO DC current mode uses SETVL/VSCHD scheduled current');
psse_is_close([r.dcline(1, dci.PF) -r.dcline(1, dci.PT)], ...
    [29.1 -29.1], 0.5, 'TWO DC no-loss PAC matches PSS/E');
psse_is_close([r.psse.twodc.control.qacr_mvar(1) ...
        r.psse.twodc.control.qaci_mvar(1)], ...
    [8.5 9.1], 0.5, 'TWO DC no-loss QAC matches PSS/E');
psse_is_close([r.psse.twodc.control.vdcr_kv(1) ...
        r.psse.twodc.control.vdci_kv(1) ...
        r.psse.twodc.control.vcomp_kv(1)], ...
    [290.9 290.9 290.9], 0.5, 'TWO DC no-loss VDC/VCOMP matches PSS/E');
psse_is_close(r.psse.twodc.control.loss_mw(1), 0, 1e-10, ...
    'TWO DC no-loss reports zero loss');
psse_is_close([r.psse.twodc.control.tapr(1) ...
        r.psse.twodc.control.tapi(1)], ...
    [1.0125 0.9660], 5e-5, 'TWO DC no-loss taps match PSS/E');
psse_is_close([r.psse.twodc.control.alpha_deg(1) ...
        r.psse.twodc.control.gamma_deg(1)], ...
    [16.02 17.00], 0.1, 'TWO DC no-loss firing angles match PSS/E');

mpc = psse_case4_twodc_current_mode(10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC current control loss success');
t_is(r.dcline(1, dci.PF) - r.dcline(1, dci.PT), 0.1, 8, ...
    'TWO DC current control applies RDC loss');
t_ok(r.psse.twodc.control.vdci_kv(1) < r.psse.twodc.control.vcmod_kv(1), ...
    'TWO DC VCMOD threshold reported');
psse_is_close(r.psse.twodc.control.idc_ka(1), 0.1, 1e-10, ...
    'TWO DC loss current matches PSS/E');
psse_is_close([r.dcline(1, dci.PF) -r.dcline(1, dci.PT)], ...
    [29.2 -29.1], 0.5, 'TWO DC loss PAC matches PSS/E');
psse_is_close(r.psse.twodc.control.loss_mw(1), 0.10, 1e-10, ...
    'TWO DC loss reports RDC loss');
psse_is_close([r.psse.twodc.control.qacr_mvar(1) ...
        r.psse.twodc.control.qaci_mvar(1)], ...
    [8.2 9.1], 0.5, 'TWO DC loss QAC matches PSS/E');
psse_is_close([r.psse.twodc.control.vdcr_kv(1) ...
        r.psse.twodc.control.vdci_kv(1) ...
        r.psse.twodc.control.vcomp_kv(1)], ...
    [291.9 290.9 291.9], 0.5, 'TWO DC loss VDC/VCOMP matches PSS/E');
psse_is_close([r.psse.twodc.control.tapr(1) ...
        r.psse.twodc.control.tapi(1)], ...
    [1.0125 0.9660], 5e-5, 'TWO DC loss taps match PSS/E');
psse_is_close([r.psse.twodc.control.alpha_deg(1) ...
        r.psse.twodc.control.gamma_deg(1)], ...
    [15.38 17.00], 0.1, 'TWO DC loss firing angles match PSS/E');

mpc = psse_case4_twodc_current_mode(10);
dcraw = mpc.psse.twodc.num;
dcraw(1, mpc.psse.twodc.col.setvl) = -50;
dcline = psse_convert_hvdc(dcraw, mpc.bus);
t_is(dcline(1, [dci.PF dci.PT dci.LOSS0]), [50.1 50 0.1], 10, ...
    'TWO DC negative SETVL converts as inverter received power');

%% PSS/E two-terminal DC LCC model for active V26p-style link
mpc = psse_case5_twodc_v26p_active();
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC V26p active LCC success');
t_ok(strcmp(r.psse.twodc.control.mode{1}, 'power'), ...
    'TWO DC V26p active remains in power mode');
t_ok(r.psse.twodc.control.current_limited == 0, ...
    'TWO DC V26p active does not trigger VCMOD current mode');
psse_is_close([r.dcline(1, dci.PF) -r.dcline(1, dci.PT) ...
        r.psse.twodc.control.loss_mw(1)], ...
    [825 -804.1 20.91], 0.5, 'TWO DC V26p PAC and loss match PSS/E');
psse_is_close(r.psse.twodc.control.idc_ka(1), 1.4132, 5e-4, ...
    'TWO DC V26p current matches PSS/E');
psse_is_close([r.psse.twodc.control.qacr_mvar(1) ...
        r.psse.twodc.control.qaci_mvar(1)], ...
    [379.4 367.5], 0.5, 'TWO DC V26p QAC matches PSS/E');
psse_is_close([r.psse.twodc.control.vdcr_kv(1) ...
        r.psse.twodc.control.vdci_kv(1) ...
        r.psse.twodc.control.vcomp_kv(1)], ...
    [583.8 569.0 583.8], 0.5, 'TWO DC V26p VDC/VCOMP matches PSS/E');
psse_is_close([r.psse.twodc.control.tapr(1) ...
        r.psse.twodc.control.tapi(1)], ...
    [1.0125 0.9660], 5e-5, 'TWO DC V26p taps match PSS/E');
psse_is_close([r.psse.twodc.control.alpha_deg(1) ...
        r.psse.twodc.control.gamma_deg(1)], ...
    [16.75 17.00], 0.1, 'TWO DC V26p firing angles match PSS/E');
t_is(r.bus(2, QD), r.psse.twodc.control.qacr_mvar(1), 8, ...
    'TWO DC V26p active applies rectifier Q as bus demand');
t_is(r.bus(4, QD), r.psse.twodc.control.qaci_mvar(1), 8, ...
    'TWO DC V26p active applies inverter Q as bus demand');
t_is(r.dcline(1, [dci.QF dci.QT]), ...
    -[r.psse.twodc.control.qacr_mvar(1) r.psse.twodc.control.qaci_mvar(1)], 8, ...
    'TWO DC V26p active reports converter Q on dcline');

mpc = psse_case5_twodc_v26p_inverter_power();
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC V26p negative SETVL success');
t_ok(strcmp(r.psse.twodc.control.mode{1}, 'power'), ...
    'TWO DC V26p negative SETVL remains in power mode');
psse_is_close([r.dcline(1, dci.PF) r.dcline(1, dci.PT) ...
        r.psse.twodc.control.loss_mw(1)], ...
    [825 804.1 20.91], 0.5, ...
    'TWO DC negative SETVL PAC and loss match inverter target');
psse_is_close(r.psse.twodc.control.idc_ka(1), 1.4132, 5e-4, ...
    'TWO DC negative SETVL current matches PSS/E target');
psse_is_close([r.psse.twodc.control.tapr(1) ...
        r.psse.twodc.control.tapi(1)], ...
    [1.0125 0.9660], 5e-5, ...
    'TWO DC negative SETVL taps match PSS/E target');

%% PSS/E parallel two-terminal DC links are modeled independently
mpc = psse_case4_twodc_parallel_current_mode(10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'TWO DC parallel current links success');
t_is(r.psse.twodc.control.supported, 2, 10, ...
    'TWO DC parallel links are reported as supported LCC rows');
t_is(r.psse.twodc.control.apply_model, [1; 1], 10, ...
    'TWO DC parallel links actively update each dcline row');
t_is(r.psse.twodc.control.apply_q, [1; 1], 10, ...
    'TWO DC parallel links actively apply converter Q');
psse_is_close(sum(r.dcline(:, dci.PF)), sum(r.psse.twodc.control.pf), ...
    1e-8, 'TWO DC parallel PF is accumulated from active rows');
psse_is_close(sum(r.dcline(:, dci.PT)), sum(r.psse.twodc.control.pt), ...
    1e-8, 'TWO DC parallel PT is accumulated from active rows');
psse_is_close(r.bus(2, QD), sum(r.psse.twodc.control.qacr_mvar), ...
    1e-6, 'TWO DC parallel rectifier Q is accumulated at the AC bus');
psse_is_close(r.bus(3, QD), sum(r.psse.twodc.control.qaci_mvar), ...
    1e-6, 'TWO DC parallel inverter Q is accumulated at the AC bus');

%% PQBRAK scales only native load while preserving TWO DC equivalent demand
mpc = psse_case4_twodc_pqbrak_current_mode(10);
r = runpf_psse(mpc, mpopt);
t_ok(r.success, 'PQBRAK with TWO DC current control success');
has_pqbrak = isfield(r, 'psse') && isfield(r.psse, 'pqbrak') && ...
    isfield(r.psse.pqbrak, 'control');
t_ok(has_pqbrak, 'PQBRAK with TWO DC exposes control report');
has_twodc = isfield(r, 'psse') && isfield(r.psse, 'twodc') && ...
    isfield(r.psse.twodc, 'control');
t_ok(has_twodc, 'PQBRAK with TWO DC exposes TWO DC report');
if has_pqbrak
    pq = r.psse.pqbrak.control;
else
    pq = struct('scale', ones(4, 1), 'pd0', nan(4, 1), 'qd0', nan(4, 1), ...
        'pd', nan(4, 1), 'qd', nan(4, 1));
end
if has_twodc
    tw = r.psse.twodc.control;
else
    tw = struct('qacr_mvar', nan, 'qaci_mvar', nan, 'pf', nan, 'pt', nan);
end
t_ok(any(pq.scale < 1), 'PQBRAK scales low-voltage native load');
t_is(pq.qd0(2:3), [8; 12], 10, 'PQBRAK native converter-bus QD base');
t_is(r.bus(2, QD), pq.qd(2) + tw.qacr_mvar(1), 8, ...
    'PQBRAK preserves TWO DC rectifier Q demand');
t_is(r.bus(3, QD), pq.qd(3) + tw.qaci_mvar(1), 8, ...
    'PQBRAK preserves TWO DC inverter Q demand');
t_is(r.bus(2, PD), pq.pd(2) + tw.pf(1), 8, ...
    'PQBRAK preserves TWO DC rectifier P demand');
t_is(r.bus(3, PD), pq.pd(3) - tw.pt(1), 8, ...
    'PQBRAK preserves TWO DC inverter P injection');
t_is(r.dcline(1, [dci.PF dci.PT]), [tw.pf(1) tw.pt(1)], 10, ...
    'PQBRAK preserves TWO DC active dcline equivalent');

t_end;

function psse_is_close(actual, expected, tol, msg)
t_ok(all(abs(actual(:) - expected(:)) <= tol), ...
    sprintf('%s (abs tol %.6g)', msg, tol));

function psse_check_genq_case(r, tc)
[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, VM, VA] = idx_bus;
[~, PG, QG] = idx_gen;

t_ok(r.success, [tc.name ' success']);
psse_is_close(r.bus(:, VM), tc.vm, 5e-4, [tc.name ' VM matches PSS/E']);
psse_is_close(r.bus(:, VA), tc.va, 0.15, [tc.name ' VA matches PSS/E']);

has_control = isfield(r, 'psse') && isfield(r.psse, 'genq') && ...
    isfield(r.psse.genq, 'control');
t_ok(has_control, [tc.name ' exposes results.psse.genq.control']);
fields = {'code', 'qgen', 'qmax', 'qmin', 'vsched', 'vact', ...
    'rmpct', 'pct_q', 'reg_bus_ext', 'bus_ext', 'limited', ...
    'at_min', 'at_max'};
if has_control
    c = r.psse.genq.control;
    has_fields = all(isfield(c, fields));
else
    c = struct();
    has_fields = false;
end
t_ok(has_fields, [tc.name ' genq control fields']);
if ~has_fields
    c = psse_empty_genq_control(length(tc.bus_ext));
end

t_is(c.bus_ext(:), tc.bus_ext, 12, [tc.name ' control bus_ext']);
t_is(c.reg_bus_ext(:), tc.reg_bus_ext, 12, [tc.name ' regulated bus']);
t_is(c.code(:), tc.code, 12, [tc.name ' final CODE']);
psse_is_close([r.gen(:, PG) r.gen(:, QG)], [tc.pgen tc.qgen], 0.5, ...
    [tc.name ' PGEN/QGEN match PSS/E']);
psse_is_close(c.qgen(:), tc.qgen, 0.5, [tc.name ' control QGEN']);
psse_is_close([c.qmax(:) c.qmin(:)], [tc.qmax tc.qmin], 0.15, ...
    [tc.name ' Q limits']);
psse_is_close(c.vsched(:), tc.vsched, 5e-4, [tc.name ' VSCHED']);
psse_is_close(c.vact(:), tc.vact, 5e-4, [tc.name ' VACT']);
psse_is_close(c.rmpct(:), tc.rmpct, 1e-10, [tc.name ' RMPCT']);
psse_is_close(c.pct_q(:), tc.pct_q, 1e-10, [tc.name ' PCT Q']);
t_is(double(c.limited(:)), double(tc.limited), 12, [tc.name ' limited flags']);
t_is(double(c.at_min(:)), double(tc.at_min), 12, [tc.name ' at_min flags']);
t_is(double(c.at_max(:)), double(tc.at_max), 12, [tc.name ' at_max flags']);

function c = psse_empty_genq_control(n)
empty = nan(n, 1);
c = struct( ...
    'code', empty, ...
    'qgen', empty, ...
    'qmax', empty, ...
    'qmin', empty, ...
    'vsched', empty, ...
    'vact', empty, ...
    'rmpct', empty, ...
    'pct_q', empty, ...
    'reg_bus_ext', empty, ...
    'bus_ext', empty, ...
    'limited', empty, ...
    'at_min', empty, ...
    'at_max', empty ...
);

function mpc = psse_case2_cpf_pqbrak()
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 55 35 0 0 1 0.99 0 230 1 1.1 0.9
];
mpc.gen = [
    1 55 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.02 0.15 0 200 200 200 0 0 1 -360 360
];

cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
row = nan(1, 27);
row([1:8 10:14 27]) = [2 1 0 1 1.03 0.99 2 100 0 2 10 0 0 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = 1;
mpc.psse.system.adjust.MXTPSS = 20;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', row, ...
    'txt', {cell(1, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case3_low_z_branch()
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 55 30 0 0 1 0.92 -20 230 1 1.1 0.9
    3 2 0 0 0 0 1 0.985 15 230 1 1.1 0.9
];
mpc.gen = [
    1 20 0 300 -300 1.00 100 1 300 -300 0 0 0 0 0 0 0 0 0 0 0
    3 35 0 300 -300 0.985 100 1 300 -300 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.02 0.15 0 200 200 200 0 0 1 -360 360
    2 3 0 0.0001 0 200 200 200 0 0 1 -360 360
];
mpc.psse.rev = 34;
mpc.psse.system.general.THRSHZ = 0.0001;
mpc.psse.system.solver = struct('METHOD', 'FNSL', 'FLATST', 1);
mpc.psse.system.newton.ITMXN = 40;

function mpc = psse_case3_low_z_branch_with_xfmr_bus()
mpc = psse_case3_low_z_branch();
mpc.psse.xfmr.two = struct( ...
    'branch_idx', 1, ...
    'num', [2 1 0], ...
    'col', struct('i', 1, 'j', 2, 'cont1', 3) );
mpc.psse.xfmr.three = struct('branch_idx', [], 'num', [], 'col', struct());

function fx = psse_swdev_expand_fixture()
[~, ~, ~, ~, ~, BUS_TYPE, PD, QD, GS, BS] = idx_bus;

bus0 = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 30 15 0 0 1 0.98 0 230 1 1.1 0.9
    3 1 10 5 0 0 1 0.97 0 230 1 1.1 0.9
];
branch0 = [
    1 2 0.01 0.10 0 200 200 200 0 0 1 -360 360
    2 3 0.00 0.00 0 200 200 200 0 0 1 -360 360
];
results = struct();
results.bus = bus0(1:2, :);
results.bus(2, [BUS_TYPE PD QD GS BS]) = ...
    bus0(2, [BUS_TYPE PD QD GS BS]);
results.branch = branch0(1, :);
results.cpf = struct( ...
    'V', [1.00 0.99 0.98; 0.98 0.97 0.96], ...
    'V_hat', [1.01 1.00 0.99; 0.99 0.98 0.97] );
state = struct( ...
    'active', true, ...
    'original_bus', bus0, ...
    'original_bus_name', [], ...
    'original_gen', [], ...
    'original_branch', branch0, ...
    'original_dcline', [], ...
    'bus_keep', [1; 2], ...
    'branch_keep', 1, ...
    'old_to_new_bus', [1; 2; 2], ...
    'old_to_new_branch', [1; 0], ...
    'roots', [1; 2; 2], ...
    'collapsed_branch_idx', 2 );
fx = struct('results', results, 'state', state);

function mpc = psse_remap_bus_numbers(mpc, old_bus, new_bus)
[~, ~, ~, ~, BUS_I] = idx_bus;
[GEN_BUS] = idx_gen;
[F_BUS, T_BUS] = idx_brch;

mpc.bus(:, BUS_I) = psse_remap_values(mpc.bus(:, BUS_I), old_bus, new_bus);
mpc.gen(:, GEN_BUS) = psse_remap_values(mpc.gen(:, GEN_BUS), old_bus, new_bus);
mpc.branch(:, F_BUS) = psse_remap_values(mpc.branch(:, F_BUS), old_bus, new_bus);
mpc.branch(:, T_BUS) = psse_remap_values(mpc.branch(:, T_BUS), old_bus, new_bus);
if isfield(mpc, 'psse') && isfield(mpc.psse, 'genq')
    gq = mpc.psse.genq;
    if isfield(gq, 'bus_ext')
        gq.bus_ext = psse_remap_values(gq.bus_ext, old_bus, new_bus);
    end
    if isfield(gq, 'reg_bus_ext')
        gq.reg_bus_ext = psse_remap_values(gq.reg_bus_ext, old_bus, new_bus);
    end
    if isfield(gq, 'num') && isfield(gq, 'colnames')
        i_col = psse_test_col(gq.colnames, 'I');
        ireg_col = psse_test_col(gq.colnames, 'IREG');
        if i_col
            gq.num(:, i_col) = psse_remap_values(gq.num(:, i_col), old_bus, new_bus);
        end
        if ireg_col
            gq.num(:, ireg_col) = psse_remap_values(gq.num(:, ireg_col), old_bus, new_bus);
        end
    end
    mpc.psse.genq = gq;
end

function values = psse_remap_values(values, old_bus, new_bus)
sgn = sign(values);
sgn(sgn == 0) = 1;
abs_values = abs(values);
for kk = 1:length(old_bus)
    idx = abs_values == old_bus(kk);
    values(idx) = sgn(idx) .* new_bus(kk);
end

function col = psse_test_col(cols, name)
col = find(strcmpi(cols, name), 1);
if isempty(col)
    col = 0;
end

function ok = psse_policy_has(entries, section, name)
ok = false;
for kk = 1:length(entries)
    if strcmpi(entries(kk).section, section) && strcmpi(entries(kk).name, name)
        ok = true;
        return;
    end
end

function value = psse_policy_value(entries, section, name)
value = NaN;
for kk = 1:length(entries)
    if strcmpi(entries(kk).section, section) && strcmpi(entries(kk).name, name)
        value = entries(kk).value;
        return;
    end
end

function origin = psse_policy_origin(entries, section, name)
origin = '';
for kk = 1:length(entries)
    if strcmpi(entries(kk).section, section) && strcmpi(entries(kk).name, name)
        origin = entries(kk).origin;
        return;
    end
end

function value = psse_default_value(entries, section, name)
value = NaN;
for kk = 1:length(entries)
    if strcmpi(entries(kk).section, section) && strcmpi(entries(kk).name, name)
        value = entries(kk).value;
        return;
    end
end

function genq_dir = psse_genq_audit_dir()
genq_dir = '';
root = fileparts(which('t_mpxt_psse'));
for k = 1:8
    candidate = fullfile(root, 'auditoria_psse_matpower', ...
        'psse_validation_cases_genq');
    if exist(candidate, 'dir') == 7
        genq_dir = candidate;
        return;
    end
    parent = fileparts(root);
    if isempty(parent) || strcmp(parent, root)
        break;
    end
    root = parent;
end

candidate = fullfile(pwd, 'auditoria_psse_matpower', ...
    'psse_validation_cases_genq');
if exist(candidate, 'dir') == 7
    genq_dir = candidate;
end

function case_file = psse_auditoria_case_file(rel_path)
case_file = '';
root = fileparts(which('t_mpxt_psse'));
for k = 1:8
    candidate = fullfile(root, 'auditoria_psse_matpower', rel_path);
    if exist(candidate, 'file') == 2
        case_file = candidate;
        return;
    end
    parent = fileparts(root);
    if isempty(parent) || strcmp(parent, root)
        break;
    end
    root = parent;
end

candidate = fullfile(pwd, 'auditoria_psse_matpower', rel_path);
if exist(candidate, 'file') == 2
    case_file = candidate;
end

function r = psse_runpf_quiet_singular(mpc, mpopt)
warn_nearly = warning('off', 'MATLAB:nearlySingularMatrix');
warn_singular = warning('off', 'MATLAB:singularMatrix');
try
    r = runpf_psse(mpc, mpopt);
catch err
    warning(warn_nearly);
    warning(warn_singular);
    rethrow(err);
end
warning(warn_nearly);
warning(warn_singular);

function cases = psse_genq_validation_cases()
cases = cell(9, 1);

cases{1} = psse_genq_case('psse_genq_3bus_local_inband.raw', ...
    'GENQ 3bus local inband', ...
    [1; 1.03000; 0.95181], [0; -1.4; -8.0], ...
    [1; 2], [1; 2], [3; 2], ...
    [22.7; 80.0], [-31.9; 88.8], ...
    [300.0; 100.0], [-300.0; -100.0], ...
    [1.0000; 1.0300], [1.0000; 1.0300], ...
    [100.0; 100.0], [100.0; 100.0], ...
    [0; 0], [0; 0], [0; 0]);

cases{2} = psse_genq_case('psse_genq_3bus_qmax.raw', ...
    'GENQ 3bus qmax', ...
    [1; 0.98026; 0.93974], [0; 0.1; -3.8], ...
    [1; 2], [1; 2], [3; -2], ...
    [0.5; 80.0], [32.9; 15.0], ...
    [300.0; 15.0], [-300.0; -100.0], ...
    [1.0000; 1.0500], [1.0000; 0.9803], ...
    [100.0; 100.0], [100.0; 100.0], ...
    [0; 1], [0; 0], [0; 1]);

cases{3} = psse_genq_case('psse_genq_3bus_qmin.raw', ...
    'GENQ 3bus qmin', ...
    [1; 1.07739; 1.17149], [0; -0.6; -5.9], ...
    [1; 2], [1; 2], [3; -2], ...
    [3.3; 80.0], [-77.7; -10.0], ...
    [300.0; 100.0], [-300.0; -10.0], ...
    [1.0000; 1.0000], [1.0000; 1.0774], ...
    [100.0; 100.0], [100.0; 100.0], ...
    [0; 1], [0; 1], [0; 0]);

cases{4} = psse_genq_case('psse_genq_3bus_qmin_qmax_zero.raw', ...
    'GENQ 3bus zero q limit', ...
    [1; 0.87454; 0.67593], [0; -1.0; -15.4], ...
    [1; 2], [1; 3], [3; -2], ...
    [27.1; 80.0], [122.9; 0.0], ...
    [300.0; 0.0], [-300.0; 0.0], ...
    [1.0000; 1.0400], [1.0000; 0.6759], ...
    [100.0; 100.0], [100.0; 100.0], ...
    [0; 1], [0; 1], [0; 1]);

cases{5} = psse_genq_case('psse_genq_3bus_slack_q_limit.raw', ...
    'GENQ 3bus slack q limit', ...
    [1; 0.95038; 0.88944], [0; -2.7; -6.8], ...
    1, 1, 3, ...
    81.3, 77.7, ...
    20.0, -20.0, ...
    1.0000, 1.0000, ...
    100.0, 100.0, ...
    0, 0, 0);

cases{6} = psse_genq_case('psse_genq_4bus_remote_single.raw', ...
    'GENQ 4bus remote single', ...
    [1; 1.06959; 1.04838; 1.02000], [0; -0.4; -1.9; -4.4], ...
    [1; 2], [1; 4], [3; 2], ...
    [1.7; 80.0], [-139.3; 196.7], ...
    [300.0; 300.0], [-300.0; -300.0], ...
    [1.0000; 1.0200], [1.0000; 1.0200], ...
    [100.0; 100.0], [100.0; 100.0], ...
    [0; 0], [0; 0], [0; 0]);

cases{7} = psse_genq_case('psse_genq_5bus_remote_group.raw', ...
    'GENQ 5bus remote group', ...
    [1; 1.07615; 1.06209; 1.05577; 1.02000], ...
    [0; 0.4; 0.5; -0.5; -3.6], ...
    [1; 2; 3], [1; 5; 5], [3; 2; 2], ...
    [-57.1; 80.0; 80.0], [-270.7; 209.9; 139.9], ...
    [400.0; 300.0; 300.0], [-400.0; -300.0; -300.0], ...
    [1.0000; 1.0200; 1.0200], [1.0000; 1.0200; 1.0200], ...
    [100.0; 60.0; 40.0], [100.0; 60.0; 40.0], ...
    [0; 0; 0], [0; 0; 0], [0; 0; 0]);

cases{8} = psse_genq_case('psse_genq_5bus_remote_group_all_limited.raw', ...
    'GENQ 5bus group all limited', ...
    [1; 0.98476; 0.98588; 0.96095; 0.89286], ...
    [0; 0.9; 0.9; -0.1; -3.8], ...
    [1; 2; 3], [1; 5; 5], [3; -2; -2], ...
    [-58.1; 80.0; 80.0], [65.1; 20.0; 25.0], ...
    [400.0; 20.0; 25.0], [-400.0; -200.0; -200.0], ...
    [1.0000; 1.0600; 1.0600], [1.0000; 0.8929; 0.8929], ...
    [100.0; 60.0; 40.0], [100.0; 60.0; 40.0], ...
    [0; 1; 1], [0; 0; 0], [0; 1; 1]);

cases{9} = psse_genq_case('psse_genq_5bus_remote_group_one_limited.raw', ...
    'GENQ 5bus group one limited', ...
    [1; 1.03716; 1.10138; 1.05588; 1.02000], ...
    [0; 0.6; 0.2; -0.6; -3.6], ...
    [1; 2; 3], [1; 5; 5], [3; -2; 2], ...
    [-56.1; 80.0; 80.0], [-271.3; 20.0; 339.5], ...
    [400.0; 20.0; 400.0], [-400.0; -200.0; -400.0], ...
    [1.0000; 1.0200; 1.0200], [1.0000; 1.0200; 1.0200], ...
    [100.0; 60.0; 40.0], [100.0; 60.0; 40.0], ...
    [0; 1; 0], [0; 0; 0], [0; 1; 0]);

function tc = psse_genq_case(raw, name, vm, va, bus_ext, reg_bus_ext, code, ...
        pgen, qgen, qmax, qmin, vsched, vact, rmpct, pct_q, ...
        limited, at_min, at_max)
tc = struct( ...
    'raw', raw, ...
    'name', name, ...
    'vm', vm(:), ...
    'va', va(:), ...
    'bus_ext', bus_ext(:), ...
    'reg_bus_ext', reg_bus_ext(:), ...
    'code', code(:), ...
    'pgen', pgen(:), ...
    'qgen', qgen(:), ...
    'qmax', qmax(:), ...
    'qmin', qmin(:), ...
    'vsched', vsched(:), ...
    'vact', vact(:), ...
    'rmpct', rmpct(:), ...
    'pct_q', pct_q(:), ...
    'limited', limited(:), ...
    'at_min', at_min(:), ...
    'at_max', at_max(:) ...
);

function mpc = psse_case9_swshunt(modsw, stat, binit, vswhi, vswlo, swreg, bus_bs, block, swshnt)
[~, ~, ~, ~, ~, ~, ~, ~, ~, BS] = idx_bus;
mpc = loadcase('case9');
mpc.bus(9, BS) = bus_bs;
cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
row = nan(1, 27);
row([1:8 10:12 27]) = [9 modsw 0 stat vswhi vswlo swreg 100 binit block 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = swshnt;
mpc.psse.system.adjust.MXTPSS = 10;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', row, ...
    'txt', {cell(1, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case9_swshunts(rows, swshnt, maxtpss)
[~, ~, ~, ~, ~, ~, ~, ~, ~, BS] = idx_bus;
mpc = loadcase('case9');
mpc.bus(:, BS) = 0;
cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
nr = size(rows, 1);
num = nan(nr, 27);
num(:, [1:12 27]) = rows;
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = swshnt;
mpc.psse.system.adjust.MXTPSS = maxtpss;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {cell(nr, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case2_swshunt_discrete()
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 70 45 0 0 1 0.96 0 230 1 1.1 0.9
];
mpc.gen = [
    1 70 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.02 0.15 0 200 200 200 0 0 1 -360 360
];
cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
    'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
    'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
    'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
row = nan(1, 27);
row([1:8 10:14 27]) = [2 1 0 1 1.03 0.99 2 100 0 6 10 0 0 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.SWSHNT = 1;
mpc.psse.system.adjust.MXTPSS = 20;
mpc.psse.swshunt = struct( ...
    'colnames', {cols}, ...
    'num', row, ...
    'txt', {cell(1, 27)}, ...
    'binit_col', 10, ...
    'status_col', 4 ...
);

function mpc = psse_case3_facts_statcon(shmx, vset)
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 0 0 0 0 1 1.00 0 115 1 1.1 0.9
    3 1 90 45 0 0 1 1.00 0 115 1 1.1 0.9
];
mpc.gen = [
    1 90 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.01 0.10 0 250 250 250 0 0 1 -360 360
    2 3 0.02 0.12 0 250 250 250 0 0 1 -360 360
];

cols = {'NAME', 'I', 'J', 'MODE', 'PDES', 'QDES', 'VSET', ...
    'SHMX', 'TRMX', 'VTMN', 'VTMX', 'VSMX', 'IMX', 'LINX', ...
    'RMPCT', 'OWNER', 'SET1', 'SET2', 'VSREF', 'FCREG', ...
    'MNAME', 'NREG'};
col = struct();
for k = 1:length(cols)
    col.(lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'))) = k;
end
num = nan(1, 22);
num([2:20 22]) = [2 0 1 0 0 vset shmx 9999 0.9 1.1 1 0 0.05 100 1 0 0 0 3 0];
txt = cell(1, 22);
txt{1} = 'FACTS 1     ';
txt{21} = '            ';
mpc.psse.rev = 34;
mpc.psse.system.newton.VCTOLV = 1e-5;
mpc.psse.system.adjust.MXTPSS = 20;
mpc.psse.facts = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {txt}, ...
    'col', col, ...
    'bus_idx', 2, ...
    'reg_bus_idx', 3 ...
);

function mpc = psse_case2_xfmr_tap(actaps, cod, cont, tap, vma, vmi, rma, rmi, ntp, pd, qd)
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 pd qd 0 0 1 1.00 0 115 1 1.1 0.9
];
mpc.gen = [
    1 pd 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.01 0.10 0 250 250 250 tap 0 1 -360 360
];

cols = {'I', 'J', 'K', 'CKT', 'CW', 'CZ', 'CM', 'MAG1', ...
    'MAG2', 'NMETR', 'NAME', 'STAT', 'O1', 'F1', 'O2', 'F2', ...
    'O3', 'F3', 'O4', 'F4', 'R1_2', 'X1_2', 'SBASE1_2', ...
    'WINDV1', 'NOMV1', 'ANG1', ...
    'RATE11', 'RATE21', 'RATE31', 'RATE41', 'RATE51', 'RATE61', ...
    'RATE71', 'RATE81', 'RATE91', 'RATE101', 'RATE111', 'RATE121', ...
    'COD1', 'CONT1', 'RMA1', 'RMI1', 'VMA1', 'VMI1', ...
    'NTP1', 'TAB1', 'CR1', 'CX1', 'CNXA1', 'NOD1', 'WINDV2', 'NOMV2'};
col = struct();
for k = 1:length(cols)
    col.(lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'))) = k;
end

num = nan(1, 52);
num([1 2 3 5 6 7 12 21 22 23 24 25 26 27:38 39 40 ...
        41 42 43 44 45 46 47 48 49 50 51 52]) = ...
    [1 2 0 1 1 1 1 0.01 0.10 100 tap 0 0 zeros(1, 12) ...
        cod cont rma rmi vma vmi ntp 0 0 0 0 0 1 0];
mpc.psse.rev = 34;
mpc.psse.system.solver.ACTAPS = actaps;
mpc.psse.system.adjust.MXTPSS = 10;
mpc.psse.xfmr.two = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {cell(1, 52)}, ...
    'branch_idx', 1, ...
    'col', col ...
);
mpc.psse.xfmr.three = struct( ...
    'colnames', {{}}, ...
    'num', zeros(0, 112), ...
    'txt', {cell(0, 112)}, ...
    'branch_idx', zeros(0, 3), ...
    'col', struct() ...
);

function mpc = psse_case2_xfmr_tab()
mpc = psse_case2_xfmr_tap(1, 1, -2, 1.00, 1.03, 0.97, 1.1, 0.9, 5, 100, 50);
mpc.psse.xfmr.two.num(1, 46) = 1;
mpc.psse.xfmr.two.tab_applied = true;
mpc.psse.xfmr.two.tab_factor = complex(1);
mpc.psse.xfmr.two.nominal_rx = mpc.branch(1, [3 4]);
mpc.psse.impcor = struct( ...
    'colnames', {{'I', 'T', 'RE', 'IM'}}, ...
    'num', [1 0.90 0.90 0; 1 1.10 1.10 0], ...
    'txt', {cell(2, 4)} ...
);

function mpc = psse_case3_xfmr_tap_remote()
mpc = psse_case2_xfmr_tap(1, 1, -3, 1.00, 0.98, 0.95, 1.1, 0.9, 5, 0, 0);
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 0 0 0 0 1 1.00 0 115 1 1.1 0.9
    3 1 80 35 0 0 1 1.00 0 115 1 1.1 0.9
];
mpc.gen(1, 2) = 80;
mpc.branch = [
    2 1 0.01 0.10 0 250 250 250 1.00 0 1 -360 360
    2 3 0.01 0.08 0 250 250 250 0 0 1 -360 360
];
mpc.psse.xfmr.two.num(1, 1:2) = [2 1];

function mpc = psse_case3_xfmr_tap_remote_limit()
mpc = psse_case3_xfmr_tap_remote();
mpc.branch = [
    1 2 0.01 0.10 0 250 250 250 1.00 0 1 -360 360
    2 3 0.01 0.08 0 250 250 250 0 0 1 -360 360
];
mpc.psse.xfmr.two.num(1, 1:2) = [1 2];

function mpc = psse_case3_xfmr_tap_remote_cont_pos()
mpc = psse_case3_xfmr_tap_remote_limit();
mpc.psse.xfmr.two.num(1, 40) = 3;

function mpc = psse_case4_twodc_current_mode(rdc, nlinks)
if nargin < 2
    nlinks = 1;
end
c = idx_dcline;
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    2 1 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    3 1 0 0 0 0 1 1.00 0 230 1 1.1 0.9
    4 1 80 30 0 0 1 1.00 0 230 1 1.1 0.9
];
mpc.gen = [
    1 80 0 300 -300 1 100 1 200 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 2 0.01 0.10 0 200 200 200 0 0 1 -360 360
    1 3 0.01 0.10 0 200 200 200 0 0 1 -360 360
    3 4 0.01 0.05 0 200 200 200 0 0 1 -360 360
];

idc = 50 / 500;
loss = rdc * idc^2;
mpc.dcline = zeros(1, c.LOSS1);
mpc.dcline(1, [c.F_BUS c.T_BUS c.BR_STATUS c.PF c.PT c.VF c.VT ...
        c.PMIN c.PMAX c.QMINF c.QMAXF c.QMINT c.QMAXT c.LOSS0 c.LOSS1]) = ...
    [2 3 1 50 50-loss 1 1 42.5 57.5 -100 100 -100 100 loss 0];
if nlinks > 1
    mpc.dcline = repmat(mpc.dcline, nlinks, 1);
end
mpc = toggle_dcline(mpc, 'on');

cols = {'NAME', 'MDC', 'RDC', 'SETVL', 'VSCHD', 'VCMOD', ...
    'RCOMP', 'DELTI', 'METER', 'DCVMIN', 'CCCITMX', 'CCCACC', ...
    'IPR', 'NBR', 'ANMXR', 'ANMNR', 'RCR', 'XCR', 'EBASR', ...
    'TRR', 'TAPR', 'TMXR', 'TMNR', 'STPR', 'ICR', 'IFR', ...
    'ITR', 'IDR', 'XCAPR', 'NDR', 'IPI', 'NBI', 'ANMXI', ...
    'ANMNI', 'RCI', 'XCI', 'EBASI', 'TRI', 'TAPI', 'TMXI', ...
    'TMNI', 'STPI', 'ICI', 'IFI', 'ITI', 'IDI', 'XCAPI', 'NDI'};
col = struct();
for k = 1:length(cols)
    col.(lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'))) = k;
end
num = nan(1, 48);
num(2:8) = [1 rdc 50 500 400 rdc 0.1];
num(10:12) = [0 20 1];
num(13:24) = [2 1 17.5 12.5 0 5 230 1 1 1.25 0.925 0.0125];
num(25:30) = 0;
num(31:42) = [3 1 17 17 0 5 230 1 1 1.305 0.966 0.0125];
num(43:48) = 0;
txt = cell(1, 48);
txt{1} = 'DC TEST     ';
txt{9} = 'R';
txt{28} = '1 ';
txt{46} = '1 ';
mpc.psse.rev = 34;
mpc.psse.system.solver.DCTAPS = 1;
mpc.psse.system.adjust.MXTPSS = 20;
mpc.psse.twodc = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {txt}, ...
    'col', col, ...
    'dcline_idx', 1, ...
    'rect_bus_idx', 2, ...
    'inv_bus_idx', 3, ...
    'loss_mw', loss ...
);
if nlinks > 1
    mpc.psse.twodc.num = repmat(mpc.psse.twodc.num, nlinks, 1);
    mpc.psse.twodc.txt = repmat(mpc.psse.twodc.txt, nlinks, 1);
    mpc.psse.twodc.dcline_idx = (1:nlinks)';
    mpc.psse.twodc.rect_bus_idx = 2 + zeros(nlinks, 1);
    mpc.psse.twodc.inv_bus_idx = 3 + zeros(nlinks, 1);
    mpc.psse.twodc.loss_mw = loss + zeros(nlinks, 1);
end

function mpc = psse_case4_twodc_blocked()
c = idx_dcline;
mpc = psse_case4_twodc_current_mode(0);
mpc.dcline(1, [c.BR_STATUS c.PF c.PT c.LOSS0 c.LOSS1]) = 0;
mpc.psse.twodc.num(1, mpc.psse.twodc.col.mdc) = 0;
mpc.psse.twodc.loss_mw = 0;

function mpc = psse_case4_twodc_mdc2_current_mode(rdc)
mpc = psse_case4_twodc_current_mode(rdc);
mpc.psse.twodc.num(1, mpc.psse.twodc.col.mdc) = 2;
mpc.psse.twodc.num(1, mpc.psse.twodc.col.setvl) = 100;

function mpc = psse_case4_twodc_unsupported_xcap()
mpc = psse_case4_twodc_current_mode(10);
mpc.psse.twodc.num(1, mpc.psse.twodc.col.xcapr) = 1;

function mpc = psse_case4_twodc_parallel_current_mode(rdc)
mpc = psse_case4_twodc_current_mode(rdc, 2);

function mpc = psse_case4_twodc_pqbrak_current_mode(rdc)
[~, ~, ~, ~, ~, ~, PD, QD] = idx_bus;
mpc = psse_case4_twodc_current_mode(rdc);
mpc.bus(2, [PD QD]) = [10 8];
mpc.bus(3, [PD QD]) = [15 12];
mpc.psse.system.general.PQBRAK = 1.1;

function mpc = psse_case5_twodc_v26p_active()
c = idx_dcline;
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1 3 0 0 0 0 1 1.00 0 500 1 1.1 0.9
    85 1 0 0 0 0 1 1.00 0 500 1 1.1 0.9
    5 3 0 0 0 0 1 1.00 0 345 1 1.1 0.9
    86 1 0 0 0 0 1 1.00 0 345 1 1.1 0.9
    4 1 900 250 0 0 1 1.00 0 345 1 1.1 0.9
];
mpc.gen = [
    1 825 0 800 -800 1 100 1 2000 0 0 0 0 0 0 0 0 0 0 0 0
    5 95 0 800 -800 1 100 1 2000 0 0 0 0 0 0 0 0 0 0 0 0
];
mpc.branch = [
    1 85 0.001 0.01 0 2000 2000 2000 0 0 1 -360 360
    5 86 0.001 0.01 0 2000 2000 2000 0 0 1 -360 360
    86 4 0.001 0.01 0 2000 2000 2000 0 0 1 -360 360
];

idc = 825 / 600;
loss = 10.47 * idc^2;
mpc.dcline = zeros(1, c.LOSS1);
mpc.dcline(1, [c.F_BUS c.T_BUS c.BR_STATUS c.PF c.PT c.VF c.VT ...
        c.PMIN c.PMAX c.QMINF c.QMAXF c.QMINT c.QMAXT c.LOSS0 c.LOSS1]) = ...
    [85 86 1 825 825-loss 1 1 701.25 948.75 -1000 1000 -1000 1000 loss 0];
mpc = toggle_dcline(mpc, 'on');

cols = {'NAME', 'MDC', 'RDC', 'SETVL', 'VSCHD', 'VCMOD', ...
    'RCOMP', 'DELTI', 'METER', 'DCVMIN', 'CCCITMX', 'CCCACC', ...
    'IPR', 'NBR', 'ANMXR', 'ANMNR', 'RCR', 'XCR', 'EBASR', ...
    'TRR', 'TAPR', 'TMXR', 'TMNR', 'STPR', 'ICR', 'IFR', ...
    'ITR', 'IDR', 'XCAPR', 'NDR', 'IPI', 'NBI', 'ANMXI', ...
    'ANMNI', 'RCI', 'XCI', 'EBASI', 'TRI', 'TAPI', 'TMXI', ...
    'TMNI', 'STPI', 'ICI', 'IFI', 'ITI', 'IDI', 'XCAPI', 'NDI'};
col = struct();
for k = 1:length(cols)
    col.(lower(regexprep(cols{k}, '[^A-Za-z0-9_]', '_'))) = k;
end
num = nan(1, 48);
num(2:8) = [1 10.47 825 600 558 10.47 0.1];
num(10:12) = [0 100 1];
num(13:24) = [85 4 17.5 12.5 0 6.134 500 0.2548 1.0375 1.25 0.925 0.0125];
num(25:30) = 0;
num(31:42) = [86 4 17 17 0 5.689 345 0.3536 1.066 1.305 0.966 0.0125];
num(43:48) = 0;
txt = cell(1, 48);
txt{1} = 'DC V26P     ';
txt{9} = 'R';
txt{28} = '1 ';
txt{46} = '1 ';
mpc.psse.rev = 34;
mpc.psse.system.solver.DCTAPS = 1;
mpc.psse.system.adjust.MXTPSS = 20;
mpc.psse.twodc = struct( ...
    'colnames', {cols}, ...
    'num', num, ...
    'txt', {txt}, ...
    'col', col, ...
    'dcline_idx', 1, ...
    'rect_bus_idx', 2, ...
    'inv_bus_idx', 4, ...
    'loss_mw', loss ...
);

function mpc = psse_case5_twodc_v26p_inverter_power()
mpc = psse_case5_twodc_v26p_active();
mpc.psse.twodc.num(1, mpc.psse.twodc.col.setvl) = -804.1;
