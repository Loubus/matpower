# Control acceptance contract — algorithm cleanup batches 1–3

The later [unified saturation contract](CONTROL_SATURATION_CONTRACT.md)
declares the batch-5 follow-up policy: physical tap/shunt saturation may be
accepted with unmet regulation while the controller remains eligible. The
historical requirements and observations below retain their original scope.

Scope: small AC/DC control regressions before any ULTC or shunt policy refactor.
TRANSPA, reduction, hydro corridors, new benchmark adaptations and published
Beerten reference alignment remain separate work. This contract does not certify
the existing algorithms or turn numerical convergence into operational feasibility.

## Separate requirements from historical expectations

| Class | Required evidence | Existing examples and treatment |
|---|---|---|
| Electrical and physical correctness | Solved network balance, converter balance and losses; original capability limits; consistent discrete states and binding modes | Retain even when the function/test name contains `psse`. `t_vsc_mtdc` balance/Jacobian tests and `t_mpxt_psse` direction, status, bounds, fixed-shunt separation and bus mapping are not optional compatibility tests. |
| Adapter/interface correctness | Correct RAW units, signs, identities, terminal mapping, status, field synchronization and option precedence | Preserve `t_psse`, mapping/round-trip checks and original external bus-number tests. PSS/E-specific input semantics can be necessary without requiring the same final operating point. |
| Declared control policy | Device order, simultaneous-limit priority, one versus multiple steps, sharing and cycling behavior | Must be explicit, deterministic and tested. Existing behavior is evidence, not automatically the thesis policy. Changing it requires a documented replacement and revalidation, not deleting assertions. |
| Exact compatibility / historical snapshots | Particular PSS/E final taps, block combinations, Q allocations, counts, event order and rounded numerical tables | Keep original assertions runnable in the historical suite. Do not use exact equality to reject a different feasible state under a deliberately changed policy. Do not reclassify violated physical equations or stale reports as compatibility differences. |

`t_mpxt_psse` remains intact. In particular, its GENQ RAW fixture comparisons
(`psse_check_genq_case`) mix physical bounds/mapping with reference numerical
values. Its MODSW tests mix legal states and voltage regulation with exact step
counts (for example six adjustments), literal group allocation `[25;25]`, and
best-visited-state cycling policy. Transformer direction, finite grid and TAB/CW
unit conversion remain physical/adapter requirements even where labels say
“matches PSS/E direction.” TWODC table comparisons are historical references;
power balance, enabled/blocked states and physical unit conversions still matter.
The existing freeze and numerical-lockout tests establish implementation behavior,
not acceptance of those recoveries in the main scientific scenario.

## Physical gates

| Component | Acceptance requirement before changing its decisions |
|---|---|
| Electrical solve | Report success and configured residual tolerance separately. Recompute AC nodal balance on the extended station network, and check DC/converter balance. A failed solve cannot be accepted through metadata alone. |
| ULTC | Honor device status, regulated-bus identity, physical lockout, direction, deadband, tap grid and finite bounds. Re-solve the actual electrical model after a move. Distinguish saturation from control cycling and numerical rejection. Do not call a numerical failure a physical lockout. |
| Switched shunt | Use `BS = fixed_BS + sum(active switched B)` and electrical injection `Q = BS * Vm^2` in MVAr on the MATPOWER bus convention. Preserve fixed contributions; use legal block combinations for discrete mode and the declared interval for continuous mode. Regulate from solved local/remote voltages. No candidate may be accepted solely from an AC projection that omits active AC/DC equations or required limits. |
| Generator/VSC capability | Check original ratings with explicit physical tolerances, not the solver's temporary fixed-Q matrix limits alone. A binding limit must change the applicable equations and agree with metadata. Permit release only under a declared feasible rule; do not require a limit to bind just because a test expected it. Ratings, current limits and converter voltage bounds cannot increase silently. |
| PF/CPF coordination | At the same loading and fixed control state, PF and CPF must agree. After a control change, rebuild and correct at fixed loading, and rebuild the continuation direction as required. Every accepted trace point must use the accepted active set. |
| Termination | Preserve last feasible point and diagnostic cause. Separate requested endpoint, physical bound, nose, cycling and numerical failure. A physical bound can remain feasible with a saturated controller; it is not automatically a nose. Freeze/recovery policies are separately named sensitivity scenarios. |

## Executable focused gate

Run from the project root after following `.codex/MATLAB_MCP.md`:

```matlab
iniciar_proyecto;
addpath(fullfile(pwd, 'tests'));
t_control_acceptance_batch1(0, fullfile(pwd, 'outputs', 'my_fresh_acceptance_run'));
```

The output directory must not already exist. The runner saves `acceptance.mat`
(inputs, options and full results) and `acceptance.json` before MP-Test finishes.
Failing requirements remain failed; none are expected-failure skips. Unexpected
solver exceptions abort and must be reported as execution failures.

The fixtures reproduce the two local `t_vsc_mtdc` configurations without changing
ratings, deadbands or original assertions. The isolated four historical checks
are observations under `evidence.legacy`; the physical checks are a separate
MP-Test gate. The full `t_vsc_mtdc(0)` remains required. Batch 2 corrects five obsolete
auxiliary-model expectations using physical evidence. The original assertions
remain runnable with `t_vsc_mtdc(0, true)` and retain their original tolerances;
this historical replay is separate from acceptance of the repaired model.

The physical tests currently cover the two VSC failure fixtures, three electrical
solutions, legal/synchronized shunt states, reachable deadband, original generator
bounds, binding Q/mode consistency, PV voltage schedules, control-state preservation through auxiliary
topology expansion, fixed shunts at B = 0, 6, 9, 10, matched-loading PF/CPF, and
isolated shunt direction/deadband/fixed-part preservation, remote regulation,
disabled status and saturation at both bounds. Fixed-state
runs explicitly disable automatic shunt movement as a diagnostic scenario; this
does not disable capability enforcement to obtain acceptance of the main runs.
These fixtures do not exercise the full generator capability curve or converter
current/voltage saturation feature: their original options are preserved.

Tolerances are declared rather than derived from observed discrepancies:

- Solver residual: each result's configured `convergence.tol`; record actual value.
- Additional AC and converter power balances: `1e-8` pu on `baseMVA`.
- Shunt state/synchronization: `1e-8` MVAr at 1 pu voltage.
- Voltage deadband: fixture `[0.995, 1.005]` pu plus its `1e-5` pu control tolerance.
- Matched fixed-state PF/CPF voltages: `1e-6` pu.
- Generator Q feasibility and binding-mode consistency: fixture `VCTOLQ = 0.01` MVAr.

These are local gate tolerances, not proposed independent-reference accuracy
claims. The independent benchmark comparison thresholds in `STUDY_DESIGN.md`
serve a different purpose. Converter station proxy generators do not establish
unlimited physical capability.

## Refactor entry conditions

First resolve the focused red physical gates and reconcile any obsolete exact
expectations with retained evidence. Then choose one device policy. Before its
implementation change, add missing tests for remote regulation, nonconsecutive
bus numbering, disabled status, saturation at both bounds, mixed block signs,
continuous mode, interacting devices, cycling/nonconvergence, and physical versus
numerical lockout; reuse existing fixtures where they already establish those
requirements. For ULTC also test both terminal conventions, CW/TAB mapping and
multiple-device ordering. For CPF add accepted-point capability/event tests and
step/correction sensitivity on a validated benchmark.

A passing small suite alone does not authorize deleting the broader physical,
adapter, derivative or limit regressions. Do not consolidate `psse_xfmr_control`
and `psse_unified_control_update`, replace shunt candidate screening, or revise
freeze policies until their relevant gates and declared policy are ready.

## Batch 2 handoff gate and remaining boundary

`t_control_handoff_batch2(0, fresh_output_directory)` adds 53 physical and
serialization checks. The combined small gates contain 96 checks. The additional
gate establishes:

- Every voltage-controlling converter proxy survives external/internal export,
  with original offline/reordered generator identities and P/Q cost layouts.
  Its algebraic bounds do not replace physical converter capability limits.
- THRSHZ and SWDEV expansion preserve solved PQ/PV/REF modes and voltages,
  allocate explicit switched-shunt deltas to original device buses, and preserve
  aggregate PD/QD/GS/BS exactly once. Unattributed equivalent-demand changes are
  retained once at the representative; no unique internal flow on a collapsed
  ideal connector is claimed.
- Solved voltage measurements reach the direct PF controller; generator VG
  remains a regulation constraint independent of bus VM initialization.
- The unchanged light-load GENQ fixture is physically interior. A 25% load
  increase crosses its unchanged QMAX=-20 MVAr; both PF and CPF enforce the
  bound. Every accepted CPF point, an independent endpoint PF, a half-step
  CPF and a repeated auxiliary solve are checked.

The handoff refreshes stale PQBRAK caches only when scale is exactly unity and
there are no active equivalent-load changes. Non-unit PQBRAK and FACTS/TWODC
equivalents are deliberately retained. The new crossing does not certify
low-voltage nominal/effective-load transfer or a mixed FACTS/TWODC/VSC model.
Those require separate physical fixtures before extending this behavior.

Batch 2 fixes data transfer, not controller selection, priority, release,
lockout or freeze policy. A green gate removes the reproduced handoff blockers;
ULTC consolidation still requires the device-specific coverage and declared
policy listed above. TRANSPA and hydro-corridor work remain deferred.

## Batch 3 bounded ULTC extraction

The [ULTC decision contract](ULTC_DECISION_CONTRACT.md) declares the shared
single-pass tap operation and records differences that remain in AC and unified
solver layers. `t_ultc_acceptance_batch3` establishes terminal/CW/TAB, eligibility,
mapping, bounds, interaction, cycle and lockout coverage before extraction.
Its failing lock-handoff cases require an isolated adapter repair; they are not
waived as policy differences. `t_ultc_beerten_batch3` adds short controls-active
continuations, a post-base tap event, accepted-point electrical/interface checks,
matched-state PF comparisons and half-step endpoint verification. Both preceding
physical gates and full electrical/interface/control suites remain required.
See the [batch 3 report](../outputs/algorithm_cleanup_batch3_20260910/REPORT.md)
for actual gate results and remaining limits of the evidence.

Switched-shunt selection, broader recovery policy, new benchmark conversion,
TRANSPA and the hydro corridor remain outside this extraction. Passing ULTC
coverage does not establish missing switched-shunt physical regimes or resolve
the caller-specific cycle/report/lock policies listed in the shared contract.
