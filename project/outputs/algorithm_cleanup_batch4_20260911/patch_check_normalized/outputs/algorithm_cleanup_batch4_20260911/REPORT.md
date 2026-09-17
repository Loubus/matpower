# Algorithm cleanup batch 4 â€” switched-shunt acceptance and bounded consolidation

**Complete: 1,282 checks passed, zero failed, zero skipped and no exceptions.**
The new switched-shunt gate passes **67/67**, and the short shunt-only and
combined ULTC/shunt Beerten gate passes **281/281**, before and after extraction.
This batch repairs an explicit unified shunt-lock eligibility defect and shares
only group voltage requests and adjacent discrete BINIT selection. Final counts
and warning-line checks are recorded in `verification_summary.json`.

## Baseline and scope

Batch 3 and its September 11 revalidation are the starting baseline. Every
entry in the revalidation source manifest matched on arrival
(`batch3_baseline_verified.json`). Batch 3 was not reimplemented or rerun.
The focused batch 1/2 gates and existing controls/VSC suites are used as
regression protection for this change, not as a repetition of the batch 3 audit.

Production changes are confined to two existing adapters and two new helpers:

- `matpower/lib/+mp/psse_swshunt_control.m`
- `matpower/lib/+mp/psse_unified_control_update.m`
- `matpower/lib/+mp/psse_swshunt_group_action.m`
- `matpower/lib/+mp/psse_swshunt_discrete_next.m`

The [shared contract](../../docs/SWSHUNT_DECISION_CONTRACT.md) was written before
extraction. Existing scientific repairs, electrical equations, solver options,
ratings, generator/converter limits, shunt/tap grids and historical evidence
remain preserved. No broader recovery change, benchmark conversion, TRANSPA or
hydro-corridor work is included. No new lock or freeze rule was introduced.

The workspace root has no Git repository; MATPOWER is nested in `matpower/`.
`status_before.txt`, `preexisting.patch` and `before/` preserve entry context.
`batch4.patch` is relative to those working files, not Git HEAD. The README's
original prefix was recovered after its append and verified against its entry
SHA-256 before patch capture. Historical batch 3 files remain byte-identical.

## AC versus unified decisions

Both adapters already used one voltage sample for all devices, normalized
voltage bands, literal RMPCT weighted positive/negative errors, an upward tie
rule, and one adjacent susceptance state for discrete shunts. These operations
are now shared. Eligibility is explicit: a locked row cannot vote or move.
Only voters on the winning side move. Fixed bus BS, RAW BINIT and physical
bounds remain owned by the unchanged state constructor/updater.

The following differences remain intentional and unmerged:

| Behavior | AC | Unified AC/DC |
|---|---|---|
| Continuous move | Group dV/dB history, with quarter-span fallback | Quarter-span move on each direct pass |
| Electrical screening | Existing auxiliary plain AC PF probe | Outer monolithic electrical correction |
| Cycle handling | Persistent history and best visited BINIT | Outer solver; direct pass can reverse |
| Diagnostics | Solved pre-move voltage plus cycle history | Pre-move voltage and provisional post-move saturation |
| Explicit unified lock mask | Not an AC shunt API | Suppresses current eligibility |

Continuous steps retain their original literal RMPCT scaling and clamps. The
AC probe retains its existing Q-limit setting and voltage sanity range; it is
screening, not proof of final acceptance with all controls. Numerical rollback,
release/freeze policy, iteration limits and solved-state reporting remain in
their current callers. A physical shunt bound is distinct from numerical
rejection. Group report metadata still describes the constructed group, not
the subset eligible in the current direct pass.

## Isolated defect and incremental evidence

`psse_swshunt_states` constructed groups before the unified lock mask was
applied. The mask set `state.controllable` false, but the local selector still
iterated the stale membership. Thus an explicitly locked device could vote
and move, and could prevent an eligible opposing peer from acting.

The initial valid acceptance run passed 64/67. It failed the all-locked group,
the locked upward voter versus eligible downward peer, and explicit-release
sequence. The repair filters current eligibility before voting, not merely
before writing BINIT. All 67 then passed with local selectors still present.
`lock_eligibility_repair.patch` isolates this repair. `preextraction/` preserves
the repaired adapters. Only after both gates were green was the common operation
extracted (`bounded_consolidation.patch`). No failing check was skipped.

| Stage | Passed | Failed | Exception |
|---|---:|---:|---|
| First new harness attempt (`acceptance_before`) | 0 | 0 | Nested helper overwrote loop BINIT variable |
| Corrected harness, original adapters (`acceptance_before_02`) | 64 | 3 | None |
| Eligibility repair (`acceptance_repaired`) | 67 | 0 | None |
| Strengthened admittance check, pre-extraction (`acceptance_preextraction`) | 67 | 0 | None |
| Initial Beerten gate (`beerten_preextraction`) | 279 | 2 | None |
| Corrected endpoint criterion (`beerten_preextraction_02`) | 281 | 0 | None |
| Final shunt acceptance (`acceptance_final`) | 67 | 0 | None |
| Final Beerten (`beerten_final`) | 281 | 0 | None |

The Beerten failures were in a copied test criterion, not electrical balance:
the new test initially required endpoint error below 1e-6, whereas the unchanged
configured `cpf.target_lam_tol` is 1e-5. Actual endpoint error was about 5.03e-6.
The new gate now checks the configured target tolerance. It preserves 1e-8 pu
electrical checks, 1e-6 pu voltage/power comparison, 1e-10 discrete-state checks,
1e-8 demand checks and 0.01 MVAr generator-Q allowance. No existing test or
configured tolerance was changed. All failed runs are retained separately.

## Physical acceptance coverage

`tests/t_swshunt_acceptance_batch4.m` adds mixed inductive/capacitive steps
through zero and both bounds; independent AC re-solves for voltage direction;
an admittance-difference check of BINIT times local voltage squared; fixed-BS
preservation; disabled modes/status/ADJM; tolerance edges and reversed/NaN
bands; nonconsecutive bus IDs and reordered unified measurements; remote
regulation and missing-remote fallback; conflicting weighted groups, exact
ties, device permutation and simultaneous same-bus accumulation.

It also covers explicit locks and caller-requested release, continuous first
steps and AC history-dependent divergence, continuous bounds and a solved
continuous case, an actual AC cycle and direct-pass reversal. An intentionally
pathological 1e6 MVAr discrete block shows the existing AC probe rejecting a
candidate while the direct unified selector returns it provisionally. That
injected diagnostic is not an accepted operating state or a benchmark input.
The full controls suite retains broader mode/interface and cycle regressions.

## Short Beerten verification and retained failure

Both cases start from `case5_vsc_mtdc_beerten_ultc_swshunt`, retaining its shunt
grid 0/5/10/15 MVAr and band 0.95â€“1.03 pu. The shunt-only study fixture removes
ULTC control metadata and keeps the transformer ratios fixed. The combined
fixture retains the original ULTC metadata, limits and initial off-grid tap.
The source case is unchanged. Both grow bus-5 demand toward five times base
and stop at lambda 0.4 with CPF step 0.1, then repeat with step 0.05.

Both have seven primary accepted states. A post-base control event near lambda
0.39462 changes shunt BINIT from 0 to 15 MVAr after fixed-lambda correction.
The combined case also normalizes the tap to 1.011111111111111 at the initial
point. These cases exercise shunt events with ULTC enabled; they do not claim
a new post-base tap event, which is already established by batch 3.

Every primary point is compared with an independent full-equation fixed-state
PF at matched demand, tap and BS. Actual stored CPF state vectors materialize
the complete station network, and their bus/converter traces must agree with
exports before independent AC nodal balance is checked. DC nodal balance,
converter power balance and unchanged loss equations are checked separately.
The gate checks affine loading, original generator Q bounds, legal shunt/tap
states and BINIT/BS synchronization. Automatic endpoint PF and half-step CPF
must independently succeed and agree at matched operating conditions.

| Measured balance | Maximum |
|---|---:|
| AC, 20 endpoint/automatic/fixed/half-step evaluations | 7.92824299245e-9 pu |
| Actual CPF AC, all 14 primary accepted states | 7.90178545564e-9 pu |
| DC nodal, 34 evaluations | 1.27986510279e-12 pu |
| Converter power, 34 evaluations | 7.13970593758e-11 pu |

All are below 1e-8 pu. These are project-variant checks, not certification
against the published Beerten benchmark or broader converter-limit coverage.

`beerten_probe.mat` retains the exploratory continuation to lambda 0.8. It
returns **success=0**, with last accepted lambda about 0.4106 and message
`VSC-MTDC monolithic PSS/E control re-correction did not converge at lambda
0.410705.` Its electrical convergence substructure still says converged; that
does not make the overall control continuation successful. The failure predates
extraction. This batch neither hides it nor changes recovery settings to pass.
The successful lambda-0.4 gate is explicitly a short acceptance case, not a
repair of that longer continuation. Broader control recovery remains deferred.

## Final verification and preservation

MATLAB R2025b was initialized using `iniciar_proyecto` through MATLAB MCP.
Edited functions were explicitly cleared and rehashed before reruns. There was
no MCP connectivity failure, CLI fallback, session restart or path reset.
Per-suite `counts.json` files and complete `run.log` files distinguish assertion
failures, exceptions and solver success flags.

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| New shunt acceptance | 67 | 0 | 0 |
| New short Beerten PF/CPF | 281 | 0 | 0 |
| Existing controls | 508 | 0 | 0 |
| Batch 1 physical | 43 | 0 | 0 |
| Batch 2 handoff | 53 | 0 | 0 |
| Full VSC | 330 | 0 | 0 |

The full VSC suite completed in 411.48 seconds. Selected final logs contain no
MATLAB warning lines. MATLAB Code Analyzer reports zero findings in all four
production files and both new tests. Two test-only formatting findings were
removed after the numerical run; no test expression or assertion changed.
`code_analysis_initial.json` preserves the initial findings.

`prepost_equivalence.json` verifies exact equality of accepted lambda/state
vectors, bus/branch/converter traces, events and half-step states for both
Beerten cases, plus all saved acceptance observations and lock/screening/
continuous decision evidence. `numerical_summary.json` records the measured
endpoints, event messages and the failed longer probe. Half-step endpoint
voltage differences are below 4.99e-8 pu; automatic endpoint PF differences
are below 8.17e-10 pu.

`preservation.json` checks 1,097 baseline files: 1,094 remain unchanged, with
only the two intended adapters and `tests/README.md` modified among existing
files. New helper/test/contract files are recorded in `source_manifest.json`.
`structural_preservation.json` separately verifies the unchanged ULTC prefix,
continuous calculations, candidate screening, shunt classification and unified
report/lock suffix. Original test files and all historical batch 3 evidence are
preserved; no old assertions were edited or removed.
`patch_application_verified.json` verifies that applying the isolated patch
to a fresh mirror of the saved starting files reproduces the final files,
normalizing line endings only.
The first scratch application failed on mixed LF/CRLF inputs. Its result is
retained in `patch_application_initial.json`; the successful check normalizes
both the patch and scratch inputs to LF, without changing the source files.

## Reproduce

Use MATLAB MCP, initialize from the project root, then run with fresh destinations:

```matlab
iniciar_proyecto;
addpath(fullfile(pwd,'tests'));
b4 = fullfile(pwd,'outputs','algorithm_cleanup_batch4_20260911');
addpath(b4);
run_batch4_suite('t_swshunt_acceptance_batch4',fullfile(b4,'acceptance_new'), ...
    fullfile(b4,'acceptance_new','evidence'));
run_batch4_suite('t_swshunt_beerten_batch4',fullfile(b4,'beerten_new'), ...
    fullfile(b4,'beerten_new','evidence'));
```

The runner captures MP-Test failures even when MATLAB returns normally. Original
MAT/JSON/log files are immutable evidence; choose new directories for reruns.
The output-local Python scripts use the project `.venv/Scripts/python.exe`.
`build_beerten_gate.py` and `consolidate.py` preserve initial development steps;
they are not rerun commands for the final source. Use the final tests above.

Remaining boundaries include continuous-policy equivalence, automatic release
and freeze/recovery policy, non-unit PQBRAK with mixed FACTS/TWODC/VSC equivalent
loads, benchmark conversion, TRANSPA and the hydro corridor. None is inferred
from the shared group/discrete contract or marked complete by this batch.
