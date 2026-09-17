# Algorithm cleanup batch 3 — shared ULTC tap decisions

**Complete: 2,873 checks passed, zero failed, and 97 existing core-CPF checks
were skipped in the selected final runs.** This batch extracts
the adjacent-tap decision shared by AC and unified AC/DC controls, after isolated
lock-handoff and CPF numerical-completion repairs. Solver-specific electrical re-solving, CPF
correction, cycling and rollback remain in their existing layers.

## Scope and preservation

The production changes are confined to `psse_xfmr_control.m`,
`psse_unified_control_update.m` and the new `psse_xfmr_tap_decision.m` in
`matpower/lib/+mp/`, plus the residual norm in `matpower/lib/runcpf_vsc_mtdc.m`.
No electrical equations, limits, ratings, configured tolerances,
benchmark inputs or recovery settings changed. CPF now additionally checks
complex nodal mismatch before accepting convergence. Switched-shunt consolidation,
broader recovery-policy changes, benchmark conversion, TRANSPA and the hydro
corridor remain deferred.

`before/`, `status_before.txt` and `preexisting.patch` preserve the starting
working-tree context. The repository is nested in `matpower/`; the workspace
root is not itself a Git repository. `batch3.patch` isolates this batch relative
to those saved working files, rather than relative to Git HEAD. The separate
`lockout_repair.patch` isolates the lock-handoff repair;
`cpf_balance_repair.patch` isolates the CPF convergence repair.

`batch2_preservation.json` verifies the batch 2 source hashes before the additional
CPF repair. The final preservation audit records the intentional CPF file change
and retains the other source hashes, excluding the two documentation files
intentionally extended here. All batch 2 export, expansion,
solved-voltage, active-set and load-cache repair code remains untouched. Original
regression tests and historical evidence were not edited. `structural_preservation.json`
also verifies that the switched-shunt implementation and shared reporting suffix
are unchanged, and that the two adapters differ from the accepted pre-extraction
versions only by replacing their local tap selectors with the shared call.

## Shared behavior and removed duplication

The [decision contract](../../docs/ULTC_DECISION_CONTRACT.md) was written before
extraction. Both paths previously implemented their own adjacent-grid search:
read regulated voltage, order the voltage band, apply the existing tolerance,
multiply the voltage request by the adapter's terminal direction, and choose
the next paired tap/WINDV value. Both used one voltage sample for all devices;
neither sequentially re-solved between transformers in that pass.

Those two local selector implementations are removed. One pure helper now
performs the operation for both callers. It takes an explicit eligibility mask,
retains untouched rows, honors both finite bounds, and does not create locks or
accept electrical candidates. The shared state constructor and updater continue
to own RAW conversion, bus/branch identities, CW/TAB, initial normalization,
branch TAP, WINDV and impedance synchronization.

The adapters retain their own reporting and state-machine behavior. In
particular:

- AC keeps persistent iteration/cycle history, the best visited state, and its
  existing probe toward the base tap. Unified direct control reconstructs state
  per pass; its outer solver retains settlement/cycle handling.
- AC classifies the solved pre-move tap. Unified marks candidate saturation using
  the pre-move voltage, before its solver re-solves. These reports are not treated
  as interchangeable evidence of a corrected electrical solution.
- AC preserves `controllable` for locked rows and reports locked voltage
  violations separately. Unified suppresses those rows before classification.
  AC consumes transformer/study flags; the extra unified solver lock mask remains
  specific to that path.
- MXTPSS handling, numerical replay, correction, release/freeze options and
  rollback remain with their existing callers. The extraction does not select a
  common scientific recovery policy where the paths differ.

## Prerequisite defect and incremental evidence

The new pre-extraction ULTC gate initially passed 48 of 50 checks. Its two failures
showed that unified control erased locks already loaded from transformer
metadata: a study-locked device and a numerically rejected device both moved.
`apply_control_lockout` reset `locked_out` before considering the unified mask.

The repair is confined to the transformer adapter: retain the inherited flags,
union them with the explicit unified mask, and suppress locked rows before
classification/selection. Study labels and rejected-rebuild diagnostics remain
distinct. This preserves an existing declared lock; it adds no implicit lock,
freeze or release rule and does not alter switched-shunt handling.

| Stage | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Unchanged batch 1 physical gate | 43 | 0 | 0 |
| Unchanged batch 2 handoff gate | 53 | 0 | 0 |
| New ULTC gate before repair | 48 | 2 | 0 |
| First repair rerun, cached MATLAB function | 48 | 2 | 0 |
| Repair after explicit function reload | 50 | 0 | 0 |
| Full controls before extraction | 508 | 0 | 0 |
| ULTC gate immediately after extraction | 50 | 0 | 0 |

The first repair rerun used MATLAB's cached function. An explicit
`clear mp.psse_unified_control_update; rehash` loaded the edited file; the saved
rerun passed. No MCP connection failure, MATLAB restart, CLI fallback, path reset
or numerical-setting workaround was involved. Both failed runs are preserved.
The final ULTC gate additionally asserts study-versus-numerical provenance.

The acceptance gate reuses the existing two-bus fixture and preserved
three-winding CW/TAB RAW fixtures. It exercises both entry points for signed
terminal conventions, remote control, nonconsecutive identifiers and reordered
measurements, CW=2 kV/TAB conversion, three-winding mapping, seven disabled
conditions, deadband edges, both bounds, explicit locks, simultaneous interacting
transformers, row permutation, an actual AC cycle and direct-pass reversal.
Independent AC re-solves check physical direction and nodal balance. A declared
reverse-action negative own-terminal CONT is checked as an interface convention,
without claiming it raises voltage on the radial fixture.

Existing full tests retain initial off-grid snapping, missing winding-bus
fallback, max-iteration failure, CPF cycle resets, split numerical replay and
explicit selective-freeze sensitivity scenarios. Saturation itself creates no
lock in the shared decision. The pathological `1e6` tap used by the existing
replay pattern is an injected rejected candidate, not an accepted legal state or
a benchmark operating point.

### Additional physical gate: CPF stopping norm

The first Beerten gate passed 333/337. Reverting only the tap adapters to their
pre-extraction versions reproduced exactly the same four failures. Three checks
identified actual accepted CPF states whose complex AC mismatch exceeded 1e-8
pu even though every scalar equation passed. The load-side endpoint had complex
residual 1.08563439498e-8 versus reported scalar residual 9.4406e-9; its half-step
endpoint had complex residual 1.13087967263e-8.

The fourth check used an approximate reconstruction of station angles from
recorded magnitudes/injections. Materializing the actual stored CPF state showed
9.99526182819e-9, within the gate, versus reconstructed 1.00814868003e-8.
`norm_investigation/point5.mat` preserves that distinction. The test now uses
stored CPF state vectors and also checks their identity against the exported
bus/converter trace. The assertion and its 1e-8 tolerance did not change.

With that measurement correction, the pre-repair solver passed 355/358 checks
(`beerten_exact_before/`): the three actual balance failures remained. The
isolated solver repair adds the complex nodal mismatch magnitude to the existing
maximum over scalar equations, including CPF parameterization. Both fixed-lambda
correction and continuation correction use that norm; line-search merit uses it
consistently. It preserves all equations and the configured tolerance and can
require an additional Newton iteration. It does not change recovery or freeze
policy, or silently tighten an option in the test.

This repair covers monolithic CPF and its fixed-lambda correction solves.
Standalone PF retains its existing stopping criterion; its results are
independently checked against the complex-balance acceptance threshold here.

With both adapters still in pre-extraction form, the repaired Beerten gate passed
358/358 (`beerten_preextraction_green/`) and the strengthened ULTC gate passed
52/52. Only then was the tap extraction restored and both gates rerun, again
passing 358/358 and 52/52. The full VSC suite and both preceding physical gates
were rerun because the CPF completion check changed. No assertion was weakened,
no tolerance relaxed, and no rating, limit or implicit lock was changed to pass.

## Short Beerten verification

The existing project variant `case5_vsc_mtdc_beerten_ultc_swshunt` retains its
original ULTC/shunt bands, grid, generator bounds, converter loss parameters and
ratings. Two short continuations use the unified solver:

- Uniform load target at twice base demand, stopping at lambda 0.6.
- Bus-7 load target at five times its base demand, stopping at lambda 0.8.
  This exercises a tap move after the initial point, with fixed-lambda
  electrical correction, rather than testing only initial normalization.

`t_ultc_beerten_batch3` checks requested endpoint, actual residual against the
configured tolerance, full AC station-network balance, DC nodal balance,
converter balance and its unchanged loss equation. Every primary accepted point
is checked for affine loading, legal taps and original generator Q bounds, and
compared to an independent full-equation PF at matched loading and discrete
states. That fixed-state diagnostic calls `runpf_vsc_mtdc`; the main CPF and
separate automatic endpoint PF keep controls active through `runcpf_psse` and
`runpf_psse`. Both scenarios are repeated with half the CPF step.

To check CPF AC balance directly, the gate materializes the actual stored
continuation state, including station angles, at its accepted load and discrete
state. It checks that this reproduces the exported bus/converter trace, then
independently recomputes full-network nodal balance. It does not borrow the
independent PF's solved voltages.
Balances use the existing 1e-8 pu gate; matched-state complex voltage and
converter-power agreement use 1e-6 pu, discrete states use 1e-10, demand uses
1e-8 MW/MVAr and generator Q uses the existing 0.01 MVAr tolerance.

These are short project-variant checks, not validation against the published
Beerten benchmark. The earlier probe directories retain the load-growth
investigation; the final test evidence is authoritative.

## Verification results

Selected runs are listed in `verification_summary.json`; every run has its own
counts and full log. No selected run has an exception or MATLAB warning line.

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| ULTC acceptance (`ultc_verified`) | 52 | 0 | 0 |
| Short Beerten PF/CPF (`beerten_verified`) | 358 | 0 | 0 |
| Batch 1 physical gate (`gate1_verified`) | 43 | 0 | 0 |
| Batch 2 handoff gate (`gate2_verified`) | 53 | 0 | 0 |
| Full VSC/electrical/capability (`full_vsc_norm_final`) | 330 | 0 | 0 |
| Full controls (`full_controls`) | 508 | 0 | 0 |
| RAW/interface (`full_interface`) | 296 | 0 | 0 |
| AC PF (`full_pf_ac`) | 726 | 0 | 0 |
| DC PF (`full_pf_dc`) | 14 | 0 | 0 |
| Core CPF (`full_cpf`) | 333 | 0 | 97 |
| Jacobian (`full_jacobian`) | 64 | 0 | 0 |
| Hessian (`full_hessian`) | 96 | 0 | 0 |

The 97 skips are unchanged: 88 user-callback checks and nine legacy angle-wrap
failure checks inapplicable to MP-Core. No new gate uses expected-failure skips.
The full VSC rerun after the CPF repair took 402.32 seconds. The unaffected AC,
RAW/interface and core suites were not needlessly repeated after the isolated
monolithic CPF change.

A final review replaced `max` of two norms with the norm of their concatenated
vectors. These are identical for finite inputs; concatenation also preserves
the original NaN propagation instead of allowing MATLAB's `max` to omit NaN.
Beerten and both focused gates were rerun after this expression refinement.
`finite_norm_equivalence.json` verifies identical accepted state vectors,
loading, bus and converter traces on both Beerten cases.

MATLAB Code Analyzer reports zero findings in all four changed production files
and both new tests (`code_analysis_verified.json`). A nested test-helper variable
was renamed to eliminate its loop-variable scope warning, then the ULTC gate
was rerun. `numerical_summary.json` also records exact pre/post-extraction
equality for all saved terminal and lock decision states.

| Final physical result | Maximum observed mismatch |
|---|---:|
| AC balances of CPF endpoints, automatic/fixed PFs and half-step endpoints | 9.76590e-9 pu |
| AC balance across all 21 primary accepted CPF states | 9.99527e-9 pu |
| Converter power balance across 48 evaluations | 8.23672e-10 pu |
| DC nodal balance across 48 evaluations | 9.29923e-13 pu |

All are below the unchanged 1e-8 pu gate. Both converter loss equations and
original generator Q bounds pass. The uniform case has nine accepted points;
the load-side case has twelve. Initial tap normalization gives
1.011111111111111. The load-side event at lambda approximately 0.76914586 moves
to 0.988888888888889, with a fixed-lambda re-correction and no freeze/lock event.
Automatic endpoint PF voltage errors are 2.75e-10 and 1.15e-12 pu; half-step
endpoint differences are 2.75e-10 and 3.85e-11 pu. `beerten_balance_summary.json`
and `numerical_summary.json` contain the measured values and event messages.

`source_manifest.json` records the final before/after hashes. The isolated patch
was applied to a fresh scratch mirror of the saved inputs and compared to all
final files, with line endings normalized (`patch_application_verified.json`).

## Unresolved policy differences and switched-shunt readiness

The shared adjacent-tap operation has a declared boundary. It does not resolve
AC versus unified cycle recovery, provisional versus solved report timing,
locked-voltage accounting, initial-normalization handling or numerical/physical
limit recovery. Those differences remain explicit in the contract and runnable
tests; no policy was silently promoted from one solver to the other.

Switched-shunt work can proceed as a separate acceptance-coverage review, using
the preserved batch 1/2 gates and the new ULTC gates as regression protection.
ULTC consolidation alone does not establish acceptance for mixed-sign shunt
blocks, continuous-mode screening, interacting shunt devices, release policy,
non-unit PQBRAK handoff or mixed FACTS/TWODC/VSC equivalent-load regimes. Those
remain prerequisites to any broader shunt/recovery consolidation. TRANSPA,
benchmark conversion and the hydro corridor remain deferred.

## Reproduce

Initialize with `iniciar_proyecto` from the root through MATLAB MCP, following
`.codex/MATLAB_MCP.md`. Add `tests/` and this evidence directory to the path.
For example:

```matlab
b3 = fullfile(pwd,'outputs','algorithm_cleanup_batch3_20260910');
addpath(fullfile(pwd,'tests')); addpath(b3);
run_batch3_suite('t_ultc_acceptance_batch3',fullfile(b3,'ultc_new'), ...
    fullfile(b3,'ultc_new','evidence'));
run_batch3_suite('t_ultc_beerten_batch3',fullfile(b3,'beerten_new'), ...
    fullfile(b3,'beerten_new','evidence'));
```

Every destination must be fresh. The runner records MP-Test passes, failures,
skips, exceptions, elapsed time and full logs separately. The test MAT files
retain options, inputs and complete results; JSON files list individual checks.
Use the project `.venv\Scripts\python.exe` with `capture_patch.py` to regenerate
the isolated patch and source manifest after deliberate edits.

## Current-workspace revalidation — 2026-09-11

The repeated implementation request found the complete batch 3 implementation,
contract, acceptance tests and incremental evidence already present. All twelve
entries in the original source manifest matched the files on disk at entry.
Review confirmed the extraction boundary and the two isolated prerequisite
repairs described above. No additional production or scientific test changes
were needed or made during this revalidation.

Fresh evidence is isolated in `revalidation_20260911_01/`. MATLAB R2025b was
initialized through MCP with `iniciar_proyecto`; the four production functions
were explicitly reloaded before testing. There was no CLI fallback, path reset,
rating change, tolerance change, limit disablement or additional lock/freeze.
The fresh ULTC, Beerten and preceding physical gates passed 52/52, 358/358,
43/43 and 53/53. The full-suite results are retained in the revalidation
directory's `verification_summary.json` and each suite's `counts.json` and log.

All twelve required suites completed: **2,873 passed, zero failed, 97 skipped,
and no exceptions or warning lines**. Every suite reproduced its recorded
pass/fail/skip counts. The skips remain the 88 user-callback checks and nine
MP-Core-inapplicable angle-wrap checks. The full VSC suite passed 330/330 in
422.45 seconds. Nested MATPOWER Git status was identical before and after
revalidation; no scientific source changes resulted from the runs.

Fresh Beerten maxima are 9.99526182819e-9 pu for AC balance across all 21 primary
accepted CPF states, 9.76589554672e-9 pu across the other 27 AC balance checks,
8.23671277850e-10 pu for converter balance and 9.29922805426e-13 pu for DC nodal
balance. All remain below the original 1e-8 pu gate. Legal taps, original Q
bounds, matched-state PF/CPF agreement, the post-base tap event and half-step
endpoint checks all passed.

The independent preservation audit confirms the recorded batch 2 source hashes,
with only the already documented CPF residual-norm change relative to batch 2.
It also verifies that both adapters differ from their accepted pre-extraction
forms only by replacing the tap selectors, and that the switched-shunt/reporting
suffix is unchanged. Applying the original `batch3.patch` to a fresh mirror of
the saved inputs reproduced every recorded final file, including the report
before this addendum, after normalizing line endings.

Original patches, manifests and numerical evidence remain untouched. The prior
report is preserved as `revalidation_20260911_01/REPORT_before.md`; the original
manifest still describes that original capture. New source hashes and an updated
isolated patch are captured inside the revalidation directory, relative to the
same saved pre-batch inputs. The addendum does not expand switched-shunt,
recovery-policy, benchmark, TRANSPA or hydro-corridor readiness claims.

The refreshed `revalidation_20260911_01/batch3.patch` includes the original
implementation/test/documentation changes, this report addendum and its audit
script. It was applied to another fresh scratch mirror and every resulting file
was compared with the current workspace, normalizing line endings only.
`final_patch_verified.json` and `source_manifest.json` record that check and the
current hashes. `report_update.patch` also isolates this addendum from the
preserved original report. The audit uses the project `.venv`; its `--finalize`
mode requires an unused final patch-verification directory.
