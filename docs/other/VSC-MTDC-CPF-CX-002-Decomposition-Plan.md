# VSC-MTDC CPF-CX-002 Decomposition Plan

Date: 2026-06-16

This document plans how to tackle `CPF-CX-002` from
`VSC-MTDC-CPF-Complexity-Audit-Tracker.md`. It is intentionally a
behavior-preserving decomposition plan and now also records completed
implementation checkpoints.

## Scope

`CPF-CX-002` is the architecture issue for `lib/runcpf_vsc_mtdc.m`: the file
has become a large nested-workspace monolith that owns CPF orchestration,
PSS/E active-set handling, VSC capability handling, generator capability
handling, HVDC derating, regular CPF `FULL` target-lambda behavior, profiling, event construction,
incremental policy helpers, and internal test dispatch.

The goal is to make the solver easier to reason about without changing
validated solver behavior, event order, event payloads, CPF traces, or public
entry-point semantics.

## Current Metrics

The tracker snapshot was refreshed against the current checkout before writing
this plan, then refreshed again on 2026-06-22 after the later narrow CPF-CX
fixes. The current values below reflect the live checkout at that refresh.

| Metric | Current value |
| --- | ---: |
| Lines in `lib/runcpf_vsc_mtdc.m` | 4,544 |
| Function definitions | 184 |
| `if` / `elseif` branch tokens | 402 |
| `for` / `while` loop tokens | 46 |

Before Phase 1, the same checkout snapshot recorded 5,889 lines and 204
function definitions. The first slice removed four nested event-list helpers
without changing solver behavior.

Phase 2a added `lib/+mp/psse_unified_active_set.m` and routed the duplicated
pure PSS/E active-set/report helper implementations in CPF and PF through it.
The local CPF/PF helper names remain in place as compatibility/profiling shims,
so local function count is unchanged for this checkpoint.

Phase 3a added `lib/vsc_mtdc_cpf_vsc_capability_event.m` and routed the pure
VSC capability event payload construction, completion, and lambda interpolation
through it. The local CPF helper names remain as profiling shims, so local
function count is unchanged for this checkpoint.

Phase 4a added `lib/gen_capability_default_smax.m` and
`lib/gen_capability_metadata_or_option_value.m`, then routed duplicated
generator capability metadata/default/indexing logic in CPF and
`check_gen_capability.m` through those helpers. Generator event
construction/completion and localization remain local.

Phase 4b added `lib/vsc_mtdc_cpf_gen_capability_event.m` and routed pure
generator capability event construction/completion through it. Generator
localization, retry solving, previous-margin lookup, active-set mutation, and
freeze/limit events remain local.

Phase 5 added `lib/vsc_mtdc_cpf_hvdc_derating.m` and routed pure HVDC
derating report, event, backoff, floor, completion, and active-set signature
helpers through it. The HVDC derating settle loop, update logic, retry
rollback, policy disable behavior, and incremental policy state mutation remain
local.

Phase 6 added `lib/vsc_mtdc_cpf_policy_state.m` and routed incremental CPF
policy-state initialization, policy metadata parsing, current-MPC construction,
load/gen/HVDC incremental application, selector validation, participant-row
queries, report helpers, lambda-definition lookup, and vector-limit helpers
through it. The solver still owns the mutable `cpf_policy_state` variable,
anchor refresh timing, freeze/relief decisions, and active-set rollback.

Phase 7 briefly added a FULL-trace helper for the custom VSC
arc/voltage/decreasing-lambda state machine. CPF-CX-005 superseded that design:
`cpf.stop_at = 'FULL'` now follows regular CPF target-lambda semantics and the
helper was removed.

Phase 8 added local `active_set_stage_snapshot` and
`restore_active_set_stage_snapshot` helpers to share the repeated active-set
stage rollback bundle. The helpers intentionally remain nested because they
restore `mpcb`, `mpct`, `cpf_policy_state`, recorded-event indices, and context
state in the solver workspace.

Working-tree state is not a durable plan property; check `git status --short`
at the start of each implementation pass. Future implementation passes must
preserve any unrelated changes they find and avoid broad formatting or
line-ending churn.

## Current Structure

The current `runcpf_vsc_mtdc.m` responsibilities are roughly grouped as
follows.

| Area | Approximate lines | Local functions | Notes |
| --- | ---: | ---: | --- |
| Main unified CPF orchestration | 305-1336 | 3 | Accepted-point loop, base correction, stage sequencing, retry/failure policy, regular `FULL` target-lambda closure, and local active-set stage snapshot/restore. |
| Context build and PSS/E settle stage | 1338-1557 | 2 | Context rebuild, controlled initial guess, active-set loop, direct/auxiliary control update, fixed-lambda re-correction. |
| VSC capability | 1559-2164 | 25 | Active-set update, cache, prefilter, margin localization, event shim calls, and saturation/freeze policy. |
| Generator capability and HVDC derating | 2166-2765 | 32 | Generator active-set update, localization retry, HVDC derating update, helper-backed event/report shims, and active-set signatures. |
| PSS/E and shared control helpers | 2767-3556 | 39 | Control options, signatures, AC result extraction, PSS/E field copy/apply, active-set deltas, and recovery/freeze helpers. |
| CPF numeric helpers | 3582-4059 | 25 | Corrector/tangent/evaluation/nose helpers, context signatures, and result assembly. |
| Validation and incremental policy helpers | 4068-4343 | 24 | Output finalization, dispatch policy attachment, case validation, option parsing, helper-backed incremental policy shims, and original-solution stamping. |
| Trace, profiling, internal dispatch | 4352-4547 | 14 | CPF trace storage, profiling counters, and internal `__cpf_system` dispatch. Generic event-list helpers are now external helper files. |

## Coupling Assessment

The main risk is not just file size. The solver relies on a nested workspace
whose mutable state is shared across many helper groups.

High-coupling state includes:

- `mpcb`, `mpct`, `mpcb_transfer0`, `mpct_transfer0`
- `cpf_policy_state`
- `last`, `last_lam`
- `profile_timing`
- `unified_context_cache`
- `vsc_capability_param_cache`
- `vsc_capability_recorded_idx`, `gen_capability_recorded_idx`
- `psse_controls_frozen`
- `vsc_capability_transfer_frozen`
- `vsc_capability_transfer_backoff_count`
- `vsc_slack_q_backoff_count`
- `gen_capability_dispatch_frozen`

Helpers that directly mutate or depend on this state should stay local until
explicit state objects or narrow call contracts exist.

Helpers closest to pure functions or low-risk extraction include:

- generic event-list utilities, already extracted in Phase 1:
  `append_event`, `is_duplicate_event`,
  `is_duplicate_recovery_event`, `add_missing_event_fields`
- simple numeric utilities:
  `move_toward_origin`, `finite_or_zero`, `move_toward`
- active-set signatures:
  `psse_active_set_signature`, `vsc_capability_active_set_signature`,
  `gen_capability_active_set_signature`, `hvdc_derating_active_set_signature`
- event record builders that only consume explicit inputs, once profiling is
  either removed from them or passed through a safe no-op service
- shared metadata/index helpers that duplicate logic in
  `check_gen_capability.m` and `check_vsc_capability.m`

Helpers that should stay local until later include:

- `run_unified_monolithic_cpf`
- all stage settle loops
- `unified_vsc_capability_update`
- `unified_gen_capability_update`
- `unified_hvdc_derating_update`
- regular CPF `FULL` target-lambda closure
- relief and freeze helpers that mutate `cpf_policy_state`, `mpcb`, or `mpct`
- `retry_gen_capability_localized_solve`
- `build_unified_context_pair`, unless a context-cache object is introduced

## Existing Boundaries To Preserve

The current architecture decision says project-level user workflows go through
`runpf_psse` and `runcpf_psse`; `runpf_vsc_mtdc` and `runcpf_vsc_mtdc` remain
lower-level solver entry points used by wrappers and focused tests.

Adjacent modules give useful extraction boundaries:

- `runpf_vsc_mtdc_unified.m` already has a smaller PSS/E active-set loop and
  duplicated PSS/E active-set helpers.
- `lib/+mp/psse_unified_control_update.m` is the direct PSS/E control update
  seam and should remain the low-level direct-control helper.
- `check_vsc_capability.m`, `vsc_capability_params.m`, and
  `vsc_capability_policy.m` show the preferred split between audit,
  parameter resolution, and policy resolution.
- `enforce_vsc_capability_active_set.m` already computes the PF VSC active-set
  update, while its caller owns solve-check-re-solve behavior.
- `check_gen_capability.m` duplicates generator metadata/option resolution
  patterns that can later become shared helper code.

## Recommended Strategy

Do not decompose the main CPF loop first.

Start with small seams that reduce the nested workspace surface without
touching solver math, lambda stepping, active-set retry semantics, regular
`FULL` target-lambda behavior, or event payload contents. Then extract one domain boundary at
a time, validating after every small step.

The long-term target is:

- a small CPF core that owns continuation stepping and accepted-point state
- separate active-set controllers for PSS/E, VSC capability, generator
  capability, and HVDC derating
- regular CPF `FULL` target-lambda behavior
- event builders with stable payload contracts
- policy helpers separated from CPF numerical iteration
- profiling that is optional and profile-off neutral

## Phased Plan

### Phase 0: Baseline And Guardrails

Files likely touched:

- none initially
- optionally `docs/other/VSC-MTDC-CPF-Complexity-Audit-Tracker.md` after an
  implementation slice lands

Target:

- record refreshed metrics
- verify MATLAB path hygiene before trusting any validation
- establish the first unchanged-output baseline

Behavior protected:

- current focused `t_vsc_mtdc(1)` semantics
- CPF-CX-001, CPF-CX-011, and CPF-CX-012 fixes
- validated FULL trace and PSS/E control expectations

Expected validation:

```matlab
matpower_project_startup
which runcpf_vsc_mtdc -all
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
```

```powershell
git diff --check
```

Rollback risk:

- none

### Phase 1: Extract Generic Event-List Utilities

Status: done on 2026-06-17.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`
- new small helpers such as:
  - `lib/vsc_mtdc_cpf_append_event.m`
  - `lib/vsc_mtdc_cpf_is_duplicate_event.m`
  - `lib/vsc_mtdc_cpf_is_duplicate_recovery_event.m`
  - `lib/vsc_mtdc_cpf_add_missing_event_fields.m`

Extraction target:

- move only the generic event-list mechanics:
  `append_event`, `is_duplicate_event`, `is_duplicate_recovery_event`,
  `add_missing_event_fields`

Behavior protected:

- event order
- duplicate suppression
- widening heterogeneous event structs with missing fields
- all existing PSS/E, VSC, generator, HVDC, NOSE, and FULL event payloads

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
```

```powershell
git diff --check
```

Rollback risk:

- low; revert call sites to local nested functions if needed

Implementation result:

- Added `lib/vsc_mtdc_cpf_append_event.m`.
- Added `lib/vsc_mtdc_cpf_is_duplicate_event.m`.
- Added `lib/vsc_mtdc_cpf_is_duplicate_recovery_event.m`.
- Added `lib/vsc_mtdc_cpf_add_missing_event_fields.m`.
- Updated `lib/runcpf_vsc_mtdc.m` call sites to use the new helpers.
- Removed the four nested helper definitions from `runcpf_vsc_mtdc.m`.
- Local function count changed from 204 to 200.

Validation result:

```matlab
matpower_project_startup
which runcpf_vsc_mtdc -all
checkcode('lib/runcpf_vsc_mtdc.m')
checkcode('lib/vsc_mtdc_cpf_append_event.m')
checkcode('lib/vsc_mtdc_cpf_is_duplicate_event.m')
checkcode('lib/vsc_mtdc_cpf_is_duplicate_recovery_event.m')
checkcode('lib/vsc_mtdc_cpf_add_missing_event_fields.m')
t_vsc_mtdc(1)
```

```powershell
git diff --check
```

The MATLAB path resolved `runcpf_vsc_mtdc` and the new helpers from the live
`matpower\lib` directory. Analyzer output was clean. `t_vsc_mtdc(1)` passed.
`git diff --check` reported no whitespace errors, only existing Windows
line-ending warnings for dirty files.

Baseline-vs-after comparison matched exactly for:

- small wrapper CPF: `success = 1`, `max_lam = 1`, 4 CPF points,
  3 iterations, 0 events
- paper-control capability stop run: `success = 1`,
  `max_lam = 1.01312656412`, 173 CPF points, 172 iterations,
  one `VSC_CAPABILITY` event
- paper-control FULL trace smoke: `success = 1`,
  `max_lam = 2.88309325702`, 569 CPF points, 568 iterations,
  16 events, last event `TARGET_LAM`

The comparison checked success flags, `cpf.max_lam`, CPF point counts,
iterations, event names/order/payload structs, and final AC/DC/VSC matrices.

### Phase 2: Share PSS/E Active-Set Utilities With PF

Status: Phase 2a done on 2026-06-18.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`
- `lib/runpf_vsc_mtdc_unified.m`
- possibly a new helper such as `lib/+mp/psse_unified_active_set.m`

Extraction target:

- deduplicate pure PSS/E helper logic already mirrored between CPF and PF:
  - active-set signatures
  - AC result extraction
  - PSS/E control report counters
  - family/load-equivalent detection helpers
  - PSS/E field copy helpers

The Phase 2a implementation deliberately did not extract active-set delta or
apply/update helpers. CPF still owns base/target update semantics and PF still
owns single-case update semantics.

Keep local:

- CPF PSS/E settle loop
- CPF freeze/limit policy
- fixed-lambda re-correction and context rebuild behavior

Behavior protected:

- unified-voltage PSS/E active-set semantics
- conservative direct-update fallback
- auxiliary PF behavior when direct updates are insufficient
- switched-shunt and tap outcomes already reflected in focused tests

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
checkcode('lib/runpf_vsc_mtdc_unified.m')
checkcode('lib/+mp/psse_unified_active_set.m')
t_vsc_mtdc(1)
t_mpxt_psse(1)
t_psse(1)
```

```powershell
git diff --check
```

Rollback risk:

- medium, because both PF and CPF use the helpers

### Phase 3: Extract VSC Capability Event And Report Helpers

Status: Phase 3a done on 2026-06-18.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`
- `lib/vsc_mtdc_cpf_vsc_capability_event.m`
- review only, or narrowly reuse, `lib/enforce_vsc_capability_active_set.m`

Extraction target:

- event construction and completion, done in Phase 3a:
  - `vsc_capability_event_record`
  - `complete_vsc_capability_event`
- pure event lambda interpolation, done in Phase 3a:
  - `vsc_capability_event_lambda`
- pure saturation and prefilter helpers if they can accept all inputs
  explicitly

Keep local:

- `settle_unified_vsc_capability_controls`
- `unified_vsc_capability_update`
- cache ownership
- recorded-event index ownership
- relief/freeze behavior

Behavior protected:

- `P_candidate`, `Q_candidate`, `V_candidate`
- `P_projected`, `Q_projected`, `S_projected`
- `P_final`, `Q_final`, `V_final`
- `lambda_event`, `lambda_candidate`, `lambda_previous`
- margins and active-limit metadata
- projection mode and from/to AC modes

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
```

For profile-sensitive changes:

```matlab
matpower_project_startup
mpopt = mpoption('out.all', 0, 'verbose', 0);
mpopt.vsc_mtdc.profile = 1;
results = run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve(800);
```

Rollback risk:

- low to medium

### Phase 4: Extract Generator Capability Metadata And Event Helpers

Status: Phase 4b done on 2026-06-18.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`
- `lib/check_gen_capability.m`
- `lib/gen_capability_default_smax.m`
- `lib/gen_capability_metadata_or_option_value.m`
- `lib/vsc_mtdc_cpf_gen_capability_event.m`

Extraction target:

- duplicated metadata/option resolution, done in Phase 4a
- generator event construction/completion, done in Phase 4b
- pure margin and slack-exemption helpers where signatures are explicit

Keep local:

- `settle_unified_gen_capability_controls`
- `unified_gen_capability_update`
- `retry_gen_capability_localized_solve`
- access to `last` and `last_lam` until passed explicitly

Behavior protected:

- generator freeze semantics from CPF-CX-011
- slack generator exemption
- `Snom` / `Smax` metadata precedence
- event localization fields and bisection metadata

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
t_cpf(1)
```

```powershell
git diff --check
```

Rollback risk:

- medium

### Phase 5: Extract HVDC Derating Report And Policy Helpers

Status: done on 2026-06-19.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`
- `lib/vsc_mtdc_cpf_hvdc_derating.m`

Extraction target:

- empty report creation, done in Phase 5
- utilization report construction, done in Phase 5
- utilization report copy, done in Phase 5
- backoff-lambda calculation, done in Phase 5
- derating floor application, done in Phase 5
- event construction/completion, done in Phase 5
- active-set signature construction, done in Phase 5

Keep local:

- `settle_unified_hvdc_derating_controls`
- `unified_hvdc_derating_update`
- policy disable behavior on cycles or failed fractional backoff
- retry rollback, context rebuild, and incremental policy state mutation

Behavior protected:

- `HVDC_DERATING`
- `HVDC_DERATING_SKIPPED`
- fractional backoff
- derating floors
- warn-and-disable semantics

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
```

For trace-sensitive changes, compare Beerten output fields:

- `success`
- `results.cpf.max_lam`
- `results.cpf.iterations`
- number and order of `results.cpf.events`

Rollback risk:

- medium

Implementation result:

- Added `lib/vsc_mtdc_cpf_hvdc_derating.m`.
- Routed HVDC empty-report, utilization-report, utilization-copy,
  backoff-lambda, derating-floor, `HVDC_DERATING`,
  `HVDC_DERATING_SKIPPED`, event completion, and active-set signature helper
  calls through the new helper.
- Kept `settle_unified_hvdc_derating_controls` and
  `unified_hvdc_derating_update` local because they still own `mpcb`/`mpct`,
  `cpf_policy_state`, trial rollback, context rebuilds, and warn-disable
  semantics.
- Local function count changed from 195 to 188.

Validation result:

```matlab
matpower_project_startup
which runcpf_vsc_mtdc -all
checkcode('lib/runcpf_vsc_mtdc.m')
checkcode('lib/vsc_mtdc_cpf_hvdc_derating.m')
t_vsc_mtdc(1)
```

```powershell
git diff --check
```

The MATLAB path resolved `runcpf_vsc_mtdc` and the new helper from the live
`matpower\lib` directory. Analyzer output was clean. `t_vsc_mtdc(1)` passed.
`git diff --check` reported no whitespace errors, only existing Windows
line-ending warnings for dirty files.

Baseline-vs-after comparison matched exactly for:

- small wrapper CPF: `success = 1`, `max_lam = 1`, 4 CPF points,
  3 iterations, 0 events
- paper-control capability stop run: `success = 1`,
  `max_lam = 1.01312656412`, 173 CPF points, 172 iterations,
  one `VSC_CAPABILITY` event
- HVDC derating stress run: `success = 1`, `max_lam = 0.5`,
  24 CPF points, 23 iterations, one `HVDC_DERATING_SKIPPED` event

The comparison checked success flags, `cpf.max_lam`, CPF point counts,
iterations, event names/order/full payload structs, final AC/DC/VSC matrices,
and touched CPF report fields.

### Phase 6: Isolate Incremental Policy State

Status: done on 2026-06-19.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`
- `lib/vsc_mtdc_cpf_policy_state.m`

Extraction target:

- policy metadata collection, done in Phase 6
- policy state initialization, done in Phase 6
- current-MPC construction, done in Phase 6
- load, generator, and HVDC incremental application helpers, done in Phase 6
- selector and weight validation helpers, done in Phase 6
- dispatch report helpers, participant-row queries, and vector-limit helpers,
  done in Phase 6

Keep local:

- solver loop decisions that mutate `cpf_policy_state`
- refresh timing for `cpf_policy_state.anchor_mpc` and `anchor_lam`
- relief/freeze interactions and active-set rollback

Behavior protected:

- load-only lambda scaling when CPF policies are active
- frozen generator and HVDC participant rows
- VSC slack-Q relief
- capability margin policy
- unchanged outputs for cases without CPF policies

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
t_cpf(1)
```

For performance-sensitive cases, run the profile-off/profile-on smoke and
Beerten comparison.

Rollback risk:

- high

Implementation result:

- Added `lib/vsc_mtdc_cpf_policy_state.m`.
- Routed policy-state initialization, policy metadata selection, generator and
  HVDC policy resolution, derating policy resolution, VSC slack-Q relief
  policy resolution, VSC capability margin policy resolution, current-MPC
  construction, load/gen/HVDC incremental application, selector/weight
  validation, vector limits, participant-row queries, dispatch report helpers,
  and lambda-definition lookup through the new helper.
- Preserved local ownership of the mutable `cpf_policy_state` variable,
  `refresh_incremental_policy_anchor`, relief/freeze decisions, trial
  rollback, and active-set loop control.
- Preserved the pre-existing `mpopt.vsc_mtdc.dispatch_policy` report behavior:
  when no `cpf_policies` are active, policy-state initialization does not
  overwrite the explicit dispatch report created before validation.
- Local function count changed from 188 to 163.

Validation result:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
checkcode('lib/vsc_mtdc_cpf_policy_state.m')
t_vsc_mtdc(1)
t_cpf(1)
```

```powershell
git diff --check
```

Analyzer output was clean. `t_vsc_mtdc(1)` passed. `t_cpf(1)` passed with the
existing 97 skipped tests. `git diff --check` reported no whitespace errors,
only existing Windows line-ending warnings for dirty files.

Baseline-vs-after comparison matched exactly for:

- small default wrapper CPF: `success = 1`, `max_lam = 1`, 4 CPF points,
  3 iterations, 0 events
- paper-control stop and freeze runs: `success = 1`,
  `max_lam = 1.01312656412`, 173 CPF points, 172 iterations,
  one `VSC_CAPABILITY` event
- generator freeze run: `success = 1`, `max_lam = 0.728417667541`,
  161 CPF points, 160 iterations, one `GEN_CAPABILITY_FREEZE` event
- HVDC derating stress run: `success = 1`, `max_lam = 0.5`,
  24 CPF points, 23 iterations, one `HVDC_DERATING_SKIPPED` event

The comparison checked success flags, `cpf.max_lam`, CPF point counts,
iterations, event names/order/full payload structs, final AC/DC/VSC matrices,
and touched CPF report fields.

### Phase 7: FULL Trace Helper, Superseded By CPF-CX-005

Status: superseded on 2026-06-19.

Files likely touched:

- `lib/runcpf_vsc_mtdc.m`

Original extraction target:

- collect initial FULL trace flags into one state struct, done in Phase 7
- pure voltage-parameterization candidate selection, done in Phase 7
- centralize mode transition decisions:
  - arc to voltage
  - voltage to lambda
  - lambda back to voltage
  - target-lambda closure
  - stall-triggered nose handling

Keep local:

- corrector calls
- accepted-point mutation
- event append calls until event builders are already stable
- FULL mode transition decisions and retry counters after initialization

Superseding CPF-CX-005 behavior:

- `NOSE`
- `TARGET_LAM`
- no VSC-specific FULL transition events
- no custom parameterization mode or voltage-bus trace columns

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
t_cpf(1)
```

Also run the paper-control FULL trace smoke and compare key CPF trace fields.

Rollback risk:

- high

Implementation result:

- CPF-CX-005 removed the helper and the custom VSC FULL state machine instead
  of continuing to decompose it.
- `cpf.stop_at = 'NOSE'` keeps localized `NOSE` behavior.
- `cpf.stop_at = 'FULL'` keeps regular CPF arc-length tracing and uses
  `TARGET_LAM` only when the trace reaches lambda zero.

Validation result:

The original Phase 7 validation applied to the now-removed helper and custom
FULL state machine. Current validation belongs to CPF-CX-005 and should confirm
that the custom transition events/fields stay absent while regular `NOSE` and
`FULL` semantics remain intact.

### Phase 8: Introduce A Shared Active-Set Stage Runner

Status: done on 2026-06-19.

Files likely touched:

- primarily `lib/runcpf_vsc_mtdc.m`

Extraction target:

- factor repeated save/restore/rebuild/re-correct/event/tangent-invalidating
  patterns one stage at a time, partially done in Phase 8 through shared local
  snapshot/restore helpers
- start with the smallest stage after prior helper extractions, done in Phase 8

Prerequisites:

- event helpers extracted
- policy state contract clearer
- stage reports have stable explicit fields

Behavior protected:

- retry and step-halving behavior
- freeze/stop semantics
- fixed-lambda re-correction
- context rebuilds
- tangent invalidation
- `last` / `last_lam` trace continuity

Expected validation:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
t_cpf(1)
t_mpxt_psse(1)
t_psse(1)
```

```powershell
git diff --check
```

For broader structural work, also run the Beerten profile-on comparison and
verify event order and trace fields.

Rollback risk:

- highest

Implementation result:

- Added local `active_set_stage_snapshot` and
  `restore_active_set_stage_snapshot` helpers in `runcpf_vsc_mtdc.m`.
- Routed repeated snapshot/rollback bundles for PSS/E, VSC capability,
  generator capability, and HVDC derating active-set stages through the shared
  local helpers.
- Kept solve/re-correct calls, retry/step-halving decisions, event append
  timing, tangent invalidation, and freeze/stop semantics in the original
  stage blocks.
- Local function count changed from 162 to 164 because the shared runner
  boundary is intentionally local at this checkpoint.

Validation result:

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
t_cpf(1)
t_mpxt_psse(1)
t_psse(1)
mpopt = mpoption('out.all', 0, 'verbose', 0);
mpopt.vsc_mtdc.profile = 1;
results = run_case5_vsc_mtdc_beerten_paper_controls_cap_pv_curve(800);
```

```powershell
git diff --check
```

Analyzer output was clean. `t_vsc_mtdc(1)`, `t_mpxt_psse(1)`, and `t_psse(1)`
passed. `t_cpf(1)` passed with the existing 97 skipped tests. The
profile-enabled Beerten 800 wrapper completed with `success = 1`,
`max_lam = 4.20240054736`, 322 CPF points, 321 iterations, and 60 events.
`git diff --check` reported no whitespace errors, only existing Windows
line-ending warnings for dirty files.

Baseline-vs-after comparison matched exactly for:

- small default wrapper CPF
- paper-control stop and freeze runs
- generator freeze run
- HVDC derating stress run
- paper-control FULL trace run
- Beerten NOSE trace run

The comparison checked success flags, `cpf.max_lam`, CPF point counts,
iterations, event names/order/full payload structs, final AC/DC/VSC matrices,
touched CPF report fields, and FULL trace fields.

### Phase 9: Align Documentation

Files likely touched:

- `docs/other/VSC-MTDC-CPF-Complexity-Audit-Tracker.md`
- `docs/other/VSC-MTDC-Architecture-Decision.md`
- this document

Target:

- update `CPF-CX-002` status after actual implementation slices land
- align the architecture decision with the final boundaries, not desired future
  boundaries

Behavior protected:

- none; documentation only

Expected validation:

```powershell
git diff --check
```

Rollback risk:

- low

Status: Done on 2026-06-19.

Completed work:

- marked `CPF-CX-002` complete in the tracker, with the remaining solver-local
  seams explicitly left to their narrower follow-up issues
- marked `CPF-CX-010` complete after aligning the architecture decision with
  the implemented helper boundaries
- recorded the final Phase 8 metrics and this Phase 9 documentation checkpoint

Validation:

```powershell
git diff --check
```

Result:

- passed with no whitespace errors; Git still reported the existing LF-to-CRLF
  working-tree warnings for dirty files

## Final CPF-CX-002 Status

CPF-CX-002 is complete as a behavior-preserving decomposition checkpoint. The
solver remains a lower-level VSC-MTDC CPF entry point, but the largest safe pure
helper seams have been separated: generic event-list utilities, shared PSS/E
active-set/report helpers, VSC capability event helpers, generator capability
metadata/default helpers, generator capability event helpers, HVDC derating
report/event helpers, incremental policy-state helpers, and the local
active-set stage snapshot/restore bundle. CPF-CX-003 then added the local
active-set stage runner for the accepted-point stage plumbing. The intermediate
FULL trace helper was removed by CPF-CX-005.

The intentionally remaining local responsibilities are the continuation loop,
fixed-lambda solve/re-correct timing, mutable policy state ownership, active-set
policy-specific freeze/stop/recovery decisions, actual tangent rebuilds after
active-set invalidation, context rebuilds, event append timing, regular `FULL`
target-lambda closure, profiling wrappers, and internal dispatch. Those are
covered by narrower tracker items rather than by CPF-CX-002.

## Recommended First Implementation Slice

Phase 1 is complete: the generic event-list utilities have been extracted.

Why this was the right first slice:

- it is behavior-preserving and small
- it removes local functions without touching solver math
- it does not mutate `mpcb`, `mpct`, `cpf_policy_state`, or context caches
- it protects all event payloads by keeping event builders in place
- it creates a low-risk pattern for future helper files

The completed first slice did not include:

- VSC capability event builders
- generator capability event builders
- HVDC derating helpers
- regular CPF `FULL` target-lambda behavior
- active-set stage runner (now completed by CPF-CX-003)
- profiling service changes
- policy state extraction

## Next Recommended Implementation Slice

CPF-CX-002 is complete for this decomposition checkpoint. Future work should
start from the narrower open tracker items instead of reopening the umbrella
decomposition issue.

Recommended next-step prompt:

```text
Begin the next selected CPF complexity issue in:
C:\Users\santi\Documents\UNIVERSIDAD\PROYECTO FINAL DE CARRERA - MATPOWER\matpower

Scope:
- Preserve behavior exactly.
- Do not touch unrelated dirty files.
- Start with read-only inspection of the specific tracker issue and affected
  helper boundary.
- Propose the smallest helper boundary before editing.
- Keep solver math, event order/payloads, CPF traces, max_lam, and final
  matrices unchanged unless the tracker issue explicitly calls for a behavior
  change.
- Prefer a narrower issue such as profiling hardening, explicit policy
  semantics, deeper FULL trace state-machine work, event builder centralization,
  or internal dispatch cleanup.

Validation:
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
git diff --check

Report:
- exact files touched
- before/after local function count for runcpf_vsc_mtdc.m
- baseline-vs-after comparison of success flags, max_lam, point counts,
  iterations, event order/payloads, touched report fields, and final matrices
  for affected runs
```

## Validation Ladder

Run this after every narrow implementation slice unless it is documentation
only.

```matlab
matpower_project_startup
checkcode('lib/runcpf_vsc_mtdc.m')
t_vsc_mtdc(1)
```

```powershell
git diff --check
```

For broader structural work, also run:

```matlab
matpower_project_startup
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

- No broad rewrite of `runcpf_vsc_mtdc.m`.
- No mathematical VSC-MTDC formulation changes.
- No change to project entry points.
- No OPF capability-constraint work.
- No line-ending or style-only churn.
- No movement of active-set loops before their helper/report seams are stable.
- No documentation claim that boundaries are complete before implementation
  has actually created them.
