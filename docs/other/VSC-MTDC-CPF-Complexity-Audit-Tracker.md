# VSC-MTDC CPF Complexity Audit Tracker

Date: 2026-06-15

This tracker captures the current Continuation Power Flow complexity audit and
turns it into a one-by-one remediation list. It is intentionally narrower than
`VSC-MTDC-Audit-Resolution-Plan.md`: this document focuses on the current
`runcpf_vsc_mtdc` complexity spike, the failing focused regression, and the
steps needed to make the CPF algorithm easier to reason about again.

## Current State

- `runcpf_vsc_mtdc.m` has been reduced to 4,648 lines and 164 local
  functions after the completed CPF-CX-002 decomposition checkpoint.
- The unified VSC-MTDC CPF path now combines continuation logic, PSS/E
  active-set settling, VSC capability, generator capability, HVDC derating,
  full-curve tracing, profiling, event packaging, and internal test dispatch.
- A small smoke run still succeeds for the default unified CPF, the
  paper-control capability case, and the paper-control FULL trace case.
- CPF-CX-001 is fixed and guarded: `t_vsc_mtdc(1)` now directly exercises
  `runcpf_vsc_mtdc('__cpf_system', args)` with profiling disabled before the
  internal CPF Jacobian helper path.
- CPF-CX-011 is fixed: the generator capability freeze assertions now pass.
- CPF-CX-012 is fixed: the focused suite expectations now match the current
  FULL CPF and unified-voltage PSS/E control semantics.
- CPF-CX-004 is fixed: unified CPF results now include
  `cpf.active_set_failure_policy` metadata with declared and observed active-set
  semantics for PSS/E controls, VSC capability, generator capability, and HVDC
  derating.
- CPF-CX-006 is fixed: the internal `__cpf_system` derivative seam now routes
  through an explicit nested setup contract for required cases, option defaults,
  dispatch policy, policy state, transfer validation, contexts, and CPF
  derivative defaults.
- CPF-CX-013 is fixed: incremental CPF policy cases now evaluate loads as
  direct multiplicative functions of lambda and apply generator/HVDC redispatch
  from accepted-point active-load changes.

## Status Legend

- Open: confirmed issue, not started.
- Ready: next safe issue to implement.
- In Progress: currently being worked.
- Done: fixed and validated.
- Deferred: intentionally postponed with a reason.

## Issue Tracker

| ID | Status | Priority | Area | Issue | Evidence | Desired Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| CPF-CX-001 | Done | P0 | Regression | Internal `__cpf_system` dispatch can call profiling helpers before `profile_timing` exists. | Fixed by initializing disabled `profile_timing` before early internal dispatch; `t_vsc_mtdc(1)` no longer fails with missing `profile_timing`. | Internal dispatch initializes or safely bypasses profiling state; `t_vsc_mtdc(1)` reaches the next failure or passes. |
| CPF-CX-002 | Done | P1 | Architecture | `runcpf_vsc_mtdc.m` is still the lower-level unified CPF solver, but the behavior-preserving decomposition checkpoint is complete. Phase 1 extracted generic event-list utilities, Phase 2a shared pure PSS/E active-set/report helper implementations with PF, Phase 3a extracted pure VSC capability event payload helpers, Phase 4a shared generator capability metadata/default helpers, Phase 4b extracted pure generator capability event payload helpers, Phase 5 extracted pure HVDC derating report/event helpers, Phase 6 isolated incremental CPF policy-state helpers, Phase 8 shared the local active-set rollback bundle, and Phase 9 aligned the docs. The earlier Phase 7 FULL-trace helper was removed by CPF-CX-005 to return `cpf.stop_at = 'FULL'` to regular CPF target-lambda semantics. | Phase 1 moved `append_event`, `is_duplicate_event`, `is_duplicate_recovery_event`, and `add_missing_event_fields` to `lib/vsc_mtdc_cpf_*` helpers. Phase 2a added `lib/+mp/psse_unified_active_set.m`; Phase 3a added `lib/vsc_mtdc_cpf_vsc_capability_event.m`; Phase 4a added `lib/gen_capability_default_smax.m` and `lib/gen_capability_metadata_or_option_value.m`; Phase 4b added `lib/vsc_mtdc_cpf_gen_capability_event.m`; Phase 5 added `lib/vsc_mtdc_cpf_hvdc_derating.m`; Phase 6 added `lib/vsc_mtdc_cpf_policy_state.m`; Phase 8 added local `active_set_stage_snapshot` and `restore_active_set_stage_snapshot` helpers; Phase 9 updated this tracker and the architecture decision. The remaining local seams are tracked by narrower items for active-set control flow, profiling, event centralization, internal dispatch, and research-policy semantics. | Largest safe pure helper seams are separated, with solver-local orchestration responsibilities documented and preserved for narrower follow-up issues. |
| CPF-CX-003 | Done | P1 | Control Flow | The accepted-point loop now routes PSS/E controls, VSC capability, generator capability, and HVDC derating through the local `run_active_set_stage` helper. | The helper owns active-set stage snapshot/restore, stage dispatch, retry-step metadata/logging, VSC re-correction failure profiling, event return, and aggregate active-set changed tracking for tangent invalidation. Policy-specific freeze/stop/recovery tails remain local by design. | A shared local active-set stage runner removes the repeated rollback/retry plumbing without changing stage policies, event payloads, or regular `NOSE`/`FULL` CPF behavior. |
| CPF-CX-004 | Done | P1 | Semantics | Enabled active-set features now report explicit failure semantics without changing event payloads or solver behavior. | `cpf.active_set_failure_policy` reports each unified active-set feature's `declared_policy`, `observed_policy`, `enabled` flag, source option/policy, event count, and last matching event. PSS/E, VSC capability, and generator capability declare `stop` or `freeze`; VSC experimental relief tails report `experimental` when their events occur; HVDC derating declares `warn-and-disable` and reports it when `HVDC_DERATING_SKIPPED` disables the derating policy. | Result metadata makes the active-set policy contract explicit while preserving the local `run_active_set_stage` boundary, event order/payloads, and regular `NOSE`/`FULL` CPF tracing. |
| CPF-CX-005 | Done | P1 | FULL Trace | `cpf.stop_at = 'FULL'` now follows regular CPF semantics instead of a VSC-specific arc/voltage/decreasing-lambda state machine. | Removed the hidden FULL state variables, deleted `lib/vsc_mtdc_cpf_full_trace_state.m`, dropped `NOSE_STALL`/`FULL_SWITCH_*`/`FULL_TRACE_LIMIT` events, and removed custom `parameterization_mode`/`voltage_bus` trace fields. The paper-control FULL stress case now follows the ordinary arc-length trace to the configured step limit instead of force-closing the lower branch. | `cpf.stop_at = 'NOSE'` reports the localized `NOSE` event; `cpf.stop_at = 'FULL'` continues with ordinary CPF arc-length tracing and uses the regular target-lambda closure only when the trace reaches lambda zero. |
| CPF-CX-006 | Done | P2 | Internal API | Internal `__cpf_system` dispatch now has an explicit nested setup contract without moving production CPF orchestration. | `internal_cpf_setup` requires only base and target cases, accepts optional `mpopt`, `x`, `lam`, `parameterization`, `z`, `h`, `xprev`, and `lamprev`, and owns the internal seam's option normalization, dispatch policy application, incremental policy-state initialization, transfer validation, context setup, and derivative defaults. Focused tests cover both dispatch-policy propagation and base/target-only defaults. | Internal derivative/test helpers have a documented, minimal dependency contract while production solver behavior remains unchanged. |
| CPF-CX-007 | Open | P2 | Profiling | Profiling instrumentation is cross-cutting and now touches many helper paths, including internal test helpers. | `profile_time_scope()` is called throughout solver, active-set, event, and mismatch helpers. | Profiling becomes optional, safe by default, and cannot change profile-off behavior or test-only helper behavior. |
| CPF-CX-008 | Open | P2 | Research Policy | Experiment-specific relief policies are embedded in the solver loop. | VSC capability limit relief can increase saturation margin, release AC control, saturate slack Q, freeze transfer, or back off frozen transfer. | Keep research policies available, but route them through an explicit policy layer outside the core CPF iteration. |
| CPF-CX-009 | Open | P2 | Events | Event construction and deduplication are scattered across the loop and active-set helpers. | `append_event`, `is_duplicate_event`, `is_duplicate_recovery_event`, and many ad hoc event structs live in the same file. | Central event builders provide stable fields for PSS/E, VSC, generator, HVDC derating, `NOSE`, and `TARGET_LAM`. |
| CPF-CX-010 | Done | P3 | Documentation | The architecture doc needed to distinguish the supported PSS/E-aware entry points from the lower-level unified CPF solver and its implementation helper boundaries. | `VSC-MTDC-Architecture-Decision.md` now records the completed CPF-CX-002 helper boundaries and the solver-local responsibilities that remain internal implementation details. | Documentation matches the final CPF-CX-002 architecture. |
| CPF-CX-011 | Done | P0 | Regression | Generator capability freeze regression blocked the focused suite after CPF-CX-001. | Diagnosed as a fixture/semantics mismatch: `Snom = 70` now triggers base-point generator capability re-correction before CPF starts, so no CPF events exist. Raising the focused fixture to `Snom = 90` keeps the base point feasible and still records `GEN_CAPABILITY_FREEZE` with `frozen_gen_idx = 2`. | The expected `GEN_CAPABILITY_FREEZE` event is recorded with the intended generator redispatch participant. |
| CPF-CX-012 | Done | P0 | Regression | Focused suite exposed downstream FULL CPF and PSS/E control assertion drift after CPF-CX-011. | Targeted probes showed current semantics are consistent: paper-control FULL CPF follows the regular arc-length trace until the configured bound; unified CPF switched shunt uses the monolithic-voltage active set `BS/BINIT = 6` while standalone PF still uses AC-only `BS/BINIT = 9`; stop-mode PSS/E loading limit now localizes at `max_lam = 1.34315939841` with `BS = 15` and tap `0.95`. | Focused assertions match the current validated trace semantics without changing solver behavior. |
| CPF-CX-013 | Done | P1 | Research Policy | Incremental CPF policies needed explicit multiplicative load scaling and accepted-point active-load-change redispatch semantics. | `vsc_mtdc_cpf_policy_state.m` resolves a load multiplier `k`, evaluates `PD_i(lambda)=PD_i0*(1+lambda*k_i)` and `QD_i(lambda)=QD_i0*(1+lambda*k_i)`, and applies generator/HVDC/QAC redispatch from signed `dP_load` between the requested lambda and the previous accepted policy anchor. The sequential accept path now refreshes the incremental policy anchor after accepted points. | Policy cases separate direct lambda load scaling from stateful accepted-point generator and HVDC redispatch while legacy target-case CPF interpolation remains unchanged. |

## Complexity Order

This orders the issues by estimated implementation complexity, from least to
most complex. It is not the same as the recommended solve order; regressions can
still be urgent even when they are relatively small.

1. `CPF-CX-010` - Documentation alignment. Low code risk, but should be
   finalized after the implementation direction is settled.
2. `CPF-CX-001` - Profiling-state regression in internal dispatch. Done with
   one localized initialization fix.
3. `CPF-CX-007` - Profiling hardening. Done by routing profiling helpers
   through a safe enabled predicate and guarding profile-off/profile-on result
   metadata behavior.
4. `CPF-CX-006` - Internal API cleanup. Done with a nested setup contract for
   the derivative-focused `__cpf_system` seam.
5. `CPF-CX-011` - Generator freeze regression. Moderate until diagnosed because
   the failure is localized, but the missing event may reflect changed
   semantics in accepted-point handling.
6. `CPF-CX-009` - Event builders and deduplication. Mostly structural cleanup,
   with moderate regression risk around expected event fields and order.
7. `CPF-CX-004` - Active-set failure semantics. Requires policy decisions and
   result metadata design before implementation.
8. `CPF-CX-003` - Shared active-set stage runner. Done with a nested runner
   that keeps policy-specific freeze/stop/recovery tails local while sharing
   rollback, retry metadata, event return, and tangent invalidation plumbing.
9. `CPF-CX-005` - FULL trace state machine removal. Done by deleting the custom
   arc/voltage/decreasing-lambda path and preserving regular CPF `FULL`
   target-lambda closure when the trace reaches lambda zero.
10. `CPF-CX-008` - Research policy layer. High complexity because it separates
   domain-specific relief behavior from the core solver without changing
   validated traces.
11. `CPF-CX-002` - Monolith decomposition. Highest complexity because it is the
    umbrella refactor that depends on the smaller extractions above. Phase 1
    completed the generic event-list utility extraction; Phase 2a shared pure
    PSS/E active-set/report helpers with PF; Phase 3a extracted pure VSC
    capability event payload helpers; Phase 4a shared generator capability
    metadata/default helpers; Phase 4b extracted pure generator capability
    event payload helpers; Phase 5 extracted HVDC derating report/event
    helpers; Phase 6 isolated incremental policy state; Phase 7 was superseded
    by CPF-CX-005's FULL state-machine removal; Phase 8 shared the local
    active-set rollback bundle; Phase 9 aligned the tracker and architecture
    docs.

## Suggested Order

1. Treat CPF-CX-002 as complete for the current decomposition checkpoint and
   use its helper boundaries as the baseline for future solver work.
2. Extract or harden profiling state before changing algorithm behavior.
3. Deepen the active-set stage abstraction only when it can own solve/re-correct
   timing without changing event order or traces.
4. Keep `cpf.stop_at = 'FULL'` aligned with regular CPF target-lambda
   semantics; do not reintroduce VSC-specific FULL transition modes.
5. Move experimental relief/derating policy behavior behind explicit policy
   functions and document their result semantics.

## Resolution Log

- 2026-06-15 - CPF-CX-001 Done. Initialized disabled `profile_timing` before
  internal dispatch in `runcpf_vsc_mtdc.m`; analyzer remains clean except for
  the existing preallocation info note; profile-off/profile-on smoke passes;
  focused regression now reaches CPF-CX-011.
- 2026-06-19 - CPF-CX-001 Guard Added. `t_vsc_mtdc(1)` now has a direct
  internal-dispatch regression guard that calls
  `runcpf_vsc_mtdc('__cpf_system', args)` with profiling disabled and asserts
  that the augmented CPF system is returned without profiling metadata.
- 2026-06-19 - CPF-CX-006 Done. Added the nested `internal_cpf_setup` contract
  in `runcpf_vsc_mtdc.m` for the derivative/test-only `__cpf_system` seam. The
  setup path explicitly handles required base/target cases, `mpopt` defaults,
  dispatch policy application, incremental CPF policy-state initialization,
  transfer validation, context setup, and derivative defaults for `lam`,
  `parameterization`, `z`, `h`, `xprev`, and `lamprev`. Focused tests now cover
  base/target-only defaults in addition to dispatch-policy propagation and the
  profiling-off guard.
- 2026-06-15 - CPF-CX-011 Done. Targeted probe showed the failing run stopped
  before CPF with `Base case generator capability re-correction did not
  converge.` and zero events. The focused generator-freeze fixture now uses
  generator `Snom = 90`, avoiding base-point capability clamping while still
  producing `GEN_CAPABILITY_FREEZE` at the continuation limit for generator 2.
- 2026-06-16 - CPF-CX-012 Done. Targeted probes showed the five failing
  assertions were stale expectations after solver semantics changed: FULL CPF
  now closes the curve, unified CPF switched shunt settles to `BS/BINIT = 6`,
  and stop-mode PSS/E loading limit localizes at lambda `1.34315939841`.
- 2026-06-17 - CPF-CX-002 Phase 1 Done. Extracted the generic event-list
  mechanics from `runcpf_vsc_mtdc.m` into
  `vsc_mtdc_cpf_append_event`, `vsc_mtdc_cpf_is_duplicate_event`,
  `vsc_mtdc_cpf_is_duplicate_recovery_event`, and
  `vsc_mtdc_cpf_add_missing_event_fields`. Local function count dropped from
  204 to 200. `checkcode`, `t_vsc_mtdc(1)`, and `git diff --check` passed;
  baseline-vs-after snapshots matched exactly for the small wrapper CPF,
  paper-control capability stop run, and paper-control FULL trace smoke.
- 2026-06-18 - CPF-CX-002 Phase 2a Done. Added
  `lib/+mp/psse_unified_active_set.m` and routed duplicated CPF/PF pure
  PSS/E active-set/report helper bodies through it while preserving local
  wrappers, CPF profiling scopes, active-set loops, auxiliary-control policy,
  and apply/update semantics. `checkcode` passed for CPF, PF, and the new
  helper; `t_vsc_mtdc(1)`, `t_mpxt_psse(1)`, `t_psse(1)`, and
  `git diff --check` passed. Baseline-vs-after snapshots matched exactly for
  small PSS/E CPF, all-controls PSS/E PF, and all-controls PSS/E CPF runs.
- 2026-06-18 - CPF-CX-002 Phase 3a Done. Added
  `lib/vsc_mtdc_cpf_vsc_capability_event.m` and routed VSC capability event
  construction, completion, and lambda interpolation through it while
  preserving local profiling wrappers, report construction, active-set loops,
  cached policy/parameter ownership, recorded-event ownership, and
  relief/freeze behavior. `checkcode`, `t_vsc_mtdc(1)`, and
  `git diff --check` passed. Baseline-vs-after snapshots matched exactly for
  VSC capability stop/freeze runs, including full event structs, event
  names/order/counts, success flags, max lambda, iterations, and final
  AC/DC/VSC matrices.
- 2026-06-18 - CPF-CX-002 Phase 4a Done. Added
  `lib/gen_capability_default_smax.m` and
  `lib/gen_capability_metadata_or_option_value.m`, then routed duplicated
  generator capability default, metadata, option, and indexing logic in CPF
  and `check_gen_capability.m` through them. Generator event construction,
  event completion, previous-margin lookup, localization/retry, and active-set
  update behavior remain local. `checkcode`, `t_vsc_mtdc(1)`, `t_cpf(1)`,
  and `git diff --check` passed. Baseline-vs-after snapshots matched exactly
  for active generator capability and generator freeze runs, including full
  event structs, success flags, max lambda, iterations, and final matrices.
- 2026-06-18 - CPF-CX-002 Phase 4b Done. Added
  `lib/vsc_mtdc_cpf_gen_capability_event.m` and routed pure generator
  capability event construction/completion through it while preserving
  localization, retry solving, previous-margin lookup, active-set mutation,
  freeze/limit events, and policy behavior locally. `checkcode`,
  `t_vsc_mtdc(1)`, and `git diff --check` passed. Baseline-vs-after snapshots
  matched exactly for active generator capability and generator freeze runs,
  including full event structs, success flags, max lambda, iterations, and
  final matrices.
- 2026-06-19 - CPF-CX-002 Phase 5 Done. Added
  `lib/vsc_mtdc_cpf_hvdc_derating.m` and routed pure HVDC derating
  empty-report, utilization-report, utilization-copy, backoff-lambda,
  derating-floor, event construction/completion, skipped-event construction,
  and active-set signature helpers through it while preserving the derating
  settle loop, update logic, retry rollback, policy disable behavior, context
  rebuilds, and incremental policy state mutation locally. `checkcode`,
  `t_vsc_mtdc(1)`, and `git diff --check` passed. Baseline-vs-after snapshots
  matched exactly for small wrapper CPF, paper-control stop, and HVDC derating
  stress runs, including full event structs, success flags, max lambda,
  iterations, touched CPF report fields, and final matrices.
- 2026-06-19 - CPF-CX-002 Phase 6 Done. Added
  `lib/vsc_mtdc_cpf_policy_state.m` and routed incremental CPF policy-state
  initialization, policy metadata parsing, current-MPC construction,
  load/gen/HVDC incremental application, selector/weight validation, dispatch
  reports, participant-row queries, lambda-definition lookup, and vector-limit
  helpers through it while preserving mutable state ownership, anchor refresh
  timing, freeze/relief decisions, active-set rollback, and explicit
  `mpopt.vsc_mtdc.dispatch_policy` report behavior locally. `checkcode`,
  `t_vsc_mtdc(1)`, `t_cpf(1)`, and `git diff --check` passed.
  Baseline-vs-after snapshots matched exactly for small default CPF,
  paper-control stop/freeze, generator freeze, and HVDC derating stress runs,
  including full event structs, success flags, max lambda, iterations, touched
  CPF report fields, and final matrices.
- 2026-06-19 - CPF-CX-002 Phase 7 Done. Added
  `lib/vsc_mtdc_cpf_full_trace_state.m` and routed FULL-trace initial
  state/defaults plus pure voltage-parameterization candidate selection
  through it while preserving corrector calls, accepted-point mutation, event
  appends, and FULL mode-transition decisions locally. `checkcode`,
  `t_vsc_mtdc(1)`, `t_cpf(1)`, the profile-enabled Beerten 800 wrapper, and
  `git diff --check` passed. Baseline-vs-after snapshots matched exactly for
  paper-control FULL trace and Beerten NOSE trace runs, including full event
  structs, success flags, max lambda, iterations, FULL trace fields, and final
  matrices. This historical phase was superseded by CPF-CX-005, which removed
  the helper and the custom FULL state-machine behavior.
- 2026-06-19 - CPF-CX-002 Phase 8 Done. Added local
  `active_set_stage_snapshot` and `restore_active_set_stage_snapshot` helpers
  in `runcpf_vsc_mtdc.m`, then routed repeated active-set rollback bundles
  through them while preserving solve/re-correct calls, event timing,
  retry/step-halving decisions, tangent invalidation, freeze/stop semantics,
  and context rebuild behavior locally. `checkcode`, `t_vsc_mtdc(1)`,
  `t_cpf(1)`, `t_mpxt_psse(1)`, `t_psse(1)`, the profile-enabled Beerten 800
  wrapper, and `git diff --check` passed. Baseline-vs-after snapshots matched
  exactly for small default CPF, paper-control stop/freeze, generator freeze,
  HVDC derating stress, paper-control FULL trace, and Beerten NOSE trace runs.
- 2026-06-19 - CPF-CX-002 Phase 9 Done. Aligned this tracker, the
  decomposition plan, and `VSC-MTDC-Architecture-Decision.md` with the final
  Phase 8 code boundary. `CPF-CX-002` is now complete as a behavior-preserving
  decomposition checkpoint, and `CPF-CX-010` is closed because the architecture
  docs now match the implemented solver/helper split. `git diff --check` passed
  with no whitespace errors, aside from Git's existing LF-to-CRLF dirty-file
  warnings.
- 2026-06-19 - CPF-CX-005 Done. Removed the VSC-specific FULL trace
  state-machine path and returned `cpf.stop_at = 'FULL'` to the regular CPF
  contract: keep tracing with the arc-length predictor/corrector and use
  `TARGET_LAM` only when the trace reaches lambda zero. `cpf.stop_at = 'NOSE'` remains the only
  path that localizes and records a `NOSE` event. The custom
  `NOSE_STALL`, `FULL_SWITCH_TO_VOLTAGE`, `FULL_SWITCH_TO_LAMBDA`, and
  `FULL_TRACE_LIMIT` events, `parameterization_mode`/`voltage_bus` trace fields,
  and `lib/vsc_mtdc_cpf_full_trace_state.m` helper were removed.
- 2026-06-19 - CPF-CX-003 Done. Added local `run_active_set_stage` in
  `runcpf_vsc_mtdc.m` and routed the accepted-point PSS/E, VSC capability,
  generator capability, and HVDC derating stages through it. The helper owns
  snapshot/restore, stage dispatch, retry-step logging metadata, event return,
  and aggregate active-set changed tracking. Stage-specific freeze, stop,
  recovery, event payload construction, and policy mutation tails remain local;
  regular `NOSE` and `FULL` CPF behavior was not changed.
- 2026-06-19 - CPF-CX-004 Done. Added behavior-preserving
  `cpf.active_set_failure_policy` metadata from `runcpf_vsc_mtdc.m`, with
  focused `t_vsc_mtdc(1)` assertions for VSC stop/enforce reporting, generator
  freeze reporting, PSS/E stop/freeze reporting, and HVDC derating's
  `warn-and-disable` declaration. No active-set policies, events, or
  `NOSE`/`FULL` CPF trace behavior were changed.
- 2026-06-19 - CPF-CX-013 Done. Added explicit multiplicative load scaling
  fields in `lib/vsc_mtdc_cpf_policy_state.m`, preserving target-case inference
  for existing policy fixtures. Generator, PAC, and QAC redispatch now use
  signed accepted-point `dP_load` while per-lambda policy fields remain
  numerically compatible through the resolved load direction. Added focused
  `t_vsc_mtdc(1)` helper assertions for direct PD/QD scaling and forward/backoff
  accepted-point redispatch. `checkcode` passed for edited `.m` files;
  `t_vsc_mtdc(1)`, `t_cpf(1)`, and `git diff --check` passed, with only Git's
  existing LF-to-CRLF dirty-file warnings.
- 2026-06-22 - CPF-CX-007 Done. Hardened local profiling helpers in
  `runcpf_vsc_mtdc.m` behind a safe `profile_is_enabled()` predicate, added
  defensive profile counter initialization, and guarded profile-off/profile-on
  result metadata in `t_vsc_mtdc(1)`. Solver math, event order/payloads, and
  internal `__cpf_system` output fields were not changed. `checkcode` passed
  for `runcpf_vsc_mtdc.m`; `t_vsc_mtdc(1)`, `t_cpf(1)`, `t_mpxt_psse(1)`,
  `t_psse(1)`, a direct profile-enabled Beerten CPF smoke, and
  `git diff --check` passed, with only Git's existing LF-to-CRLF working-copy
  warnings.

## Validation Gates

Run these after every narrow fix unless the change is documentation-only.

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
```

Then run the broader ladder before treating a structural simplification as
complete.

```powershell
git diff --check
```

```matlab
matpower_project_startup
t_vsc_mtdc(1)
t_cpf(1)
t_mpxt_psse(1)
t_psse(1)
```

For performance-sensitive or Beerten trace-sensitive changes, also run:

```matlab
matpower_project_startup
mpopt = mpoption('out.all', 0, 'verbose', 0);
mpopt.vsc_mtdc.profile = 1;
results = run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve(800);
```

Compare at least:

- `success`
- `results.cpf.max_lam`
- `results.cpf.iterations`
- number and order of `results.cpf.events`
- key timing counters if profiling is enabled

## Non-Goals

- Do not change the mathematical VSC-MTDC formulation while fixing the tracker
  items unless an issue explicitly requires it.
- Do not broaden into OPF capability constraints.
- Do not rename the model as a native PSS/E VSC HVDC implementation.
- Do not do broad line-ending or style churn while solving individual issues.

## Audit Evidence Snapshot

Original commands/results from the 2026-06-15 audit:

- `check_matlab_code` on `runcpf_vsc_mtdc.m`: one info-level preallocation note
  in event appending; no blocking analyzer issues.
- `check_matlab_code` on `mp.psse_unified_control_update`: no issues.
- `git diff --check`: no whitespace errors, only LF-to-CRLF warnings for files
  already touched in the working tree.
- Smoke:
  - default unified CPF: `success=1`, `max_lam=1`, `method=unified_vsc_mtdc`.
  - paper-control capability smoke: `success=1`, one `VSC_CAPABILITY` event.
- CPF-CX-001 focused regression:
  - `t_vsc_mtdc(1)` no longer fails with missing `profile_timing` through
    `runcpf_vsc_mtdc('__cpf_system', args)`.
- Remaining focused regression at the time:
  - `t_vsc_mtdc(1)` failed later at line 913 with `Index exceeds array bounds`
    while asserting the generator capability freeze event. This is now fixed by
    CPF-CX-011.
- Profile smoke:
  - profile off: `success=1`, `max_lam=1`, `timing=0`.
  - profile on: `success=1`, `max_lam=1`, `timing=1`, `timing_enabled=1`.

Pre-CPF-CX-007 lightweight refresh on 2026-06-22:

- `git status --short` before the CPF-CX-007 implementation: clean.
- `git diff --check`: clean.
- Current `lib/runcpf_vsc_mtdc.m` metrics: 4,544 lines, 184 function
  definitions, 402 `if`/`elseif` branch tokens, and 46 `for`/`while` loop
  tokens.
- Open tracker items at that refresh: CPF-CX-007, CPF-CX-008, and CPF-CX-009.
- MATLAB validation was not rerun for this documentation-only refresh.
