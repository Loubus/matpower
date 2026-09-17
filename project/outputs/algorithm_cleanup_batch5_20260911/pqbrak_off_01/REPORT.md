# PQBRAK disabled: full Beerten NOSE run

Date: 2026-09-11. User-authorized modeling follow-up to algorithm cleanup batch 5.

## Outcome

The final run (`nose_03/nose.mat`) reaches a detected mathematical nose:
lambda **1.305375520422**, bus-5 voltage
**0.594706044 pu**, scheduled demand **373.290125 MW /
62.215021 MVAr**. Overall success is true; termination is `nose_event`;
the requested NOSE endpoint is reached. Electrical convergence, returned
tables, the internal state vector, and last accepted lambda refer to the same
localized point. The electrical residual is 1.21e-12
against the unchanged 1e-8 tolerance. There are 35 accepted points including
the base point. The default-step tangent lambda component is
-4.07e-08.

The shunt is at 15 MVAr, the tap is 0.988888888889, and a fresh full-voltage
control decision at the localized nose requests no change and accepts physical
saturation. There is no controller freeze/lockout. The main run ends at the
nose, not at the old PQBRAK-related control-cycle endpoint.

This is **not a validated equipment-compliant stability margin**.
`stability_margin_validated` remains false. The unchanged optional capability
enforcement is off in the saved scenario, and the endpoint audit reports
2 violations (details in `final_summary.json`).
These are generator 2's overexcited capability boundary and converter 2's
current boundary. No limit was disabled or rating increased in this follow-up.
The result describes the selected equations and control settings; it does not
establish the instability point of a fully constrained physical installation.

## Modeling change and preservation

Added `exp.psse_pqbrak`, default 0, with version-27 option migration. Old saved
options without the field also mean off. Common PSS/E preparation passes this
option into PQBRAK preparation; disabled cached native-load scaling is removed
by external bus ID, with equivalent demand preserved. Native PF/CPF callbacks
see disabled metadata. The coordinated active-set path uses threshold zero
when disabled rather than falling back to 0.7. Solver policy reports disabled
PQBRAK while preserving RAW/default threshold evidence. Explicit option 1 is
available for historical experiments; `t_mpxt_psse` explicitly selects it.
The scaling formula and PSS/E CLI behavior were not changed.

The main run starts from the immutable batch-4 `b4f`, `b4t`, and `b4o` fixture.
Declared scenario changes are PQBRAK off, the previously authorized `saturate`
policy, and stop target `NOSE`. Step .1, min/max step, adaptive-step setting,
iteration bounds, max lambda 5, tolerances, ratings and limit-enforcement
settings are retained. No input case or historical evidence was overwritten.
This does not diagnose or repair the old PQBRAK-on control-settlement issue;
it removes that model from the current scenario as requested.

## Additional bounded bug repair found by verification

The first run (`nose_01`) localized lambda and `cpf.x`, but retained bus,
generator/converter and voltage tables from the pre-localization trial point.
That produced a false final V5 of 0.587418838 pu and inconsistent load reporting.
Half/quarter steps agreed on nose lambda but exposed different stale voltages.

The repair consumes the localized electrical evaluation and residual, rebuilds
the result and original-bus trace tables, and refreshes directly supported
settled control reports at the localized voltage. If direct report refresh
cannot establish acceptance, retained control reports are explicitly scoped
to their pre-localization evaluation lambda. It does not alter the continuation
equations, nose locator, Newton tolerances, or recovery policies. Final runs
are `nose_03` and `verification_03`; earlier runs are retained.

## Verification

| CPF step | Nose lambda | V5 (pu) | Residual |
|---|---:|---:|---:|
| 0.1 | 1.305375520422 | 0.594706044 | 1.21e-12 |
| 0.05 | 1.305375521381 | 0.594706081 | 2.85e-09 |
| 0.025 | 1.305375520383 | 0.594703379 | 2.41e-12 |

The 124 new checks cover option defaults/migration, explicit opt-in, cache
restoration and idempotence, bus reordering, policy reporting, native low-voltage
PF versus ordinary PF, all three full automatic NOSE traces, every default-run
point's full AC/DC/converter equations and constant demand schedule, voltage
table reconstruction, final state/termination consistency, and a fresh
localized-nose control decision. Diagnostic state materialization is kept
separate from the main automatic-control solves.

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| t_beerten_termination_batch5 | 77 | 0 | 0 |
| t_control_acceptance_batch1 | 43 | 0 | 0 |
| t_control_handoff_batch2 | 53 | 0 | 0 |
| t_control_saturation_batch5 | 105 | 0 | 0 |
| t_cpf | 333 | 0 | 97 |
| t_mpxt_psse | 508 | 0 | 0 |
| t_swshunt_acceptance_batch4 | 67 | 0 | 0 |
| t_swshunt_beerten_batch4 | 281 | 0 | 0 |
| t_ultc_acceptance_batch3 | 52 | 0 | 0 |
| t_ultc_beerten_batch3 | 358 | 0 | 0 |
| t_vsc_mtdc | 330 | 0 | 0 |
| t_pqbrak_off_batch5 | 124 | 0 | 0 |
| t_mpoption | 171 | 0 | 0 |

Totals: **2502 passed, 0 failed,
97 skipped**, 0 suite exceptions.
The 97 standard CPF skips are existing feature-dependent skips.
See `verification_summary.json` for exact counts and execution times.

Initial verification is retained: `verification_01` had 4 failures (the actual
nose-table defect plus an unsuitable low-voltage PF fixture whose generator
dispatch had not been scaled with its small demand); `verification_02`
had 36 failures from new diagnostic checks reading unstamped input tables and
an incorrectly reconstructed tap-control cache. Those test diagnostics were
corrected to use mapped full-model AC output and the actual returned control
state. No solver tolerance or production control policy was relaxed. The
final 124 checks pass. MATLAB work ran through MCP; no CLI fallback was used.
The first options-suite run had one stale version expectation (26); it was
updated to the new schema version 27 and rerun. Static analysis found only
three pre-existing STRCMP/UPPER style suggestions in mpoption, and no issues
in the other six checked implementation/test files.
No numerical warnings were found in the final prior-suite logs.

## Artifacts and readiness

- `nose_03/`: final unchanged-step run, inputs, complete result, log and summary.
- `verification_03/`: full step-sensitivity results and focused regression.
- `prior_suites_01/`, `options_suite_02/`: final prior and options regression results.
- `beerten_pv.png`: final constant-load PV trace.
- `before/`, `pqbrak_off.patch`, `source_manifest.json`, `patch_validation.json`:
  isolated patch against the pre-turn working files, with scratch application
  and content matching checks. Prior scientific modifications are retained.
- `code_analysis.json`: MATLAB static analysis of affected implementation/test files.

The model now produces a reproducible Beerten mathematical nose with PQBRAK
off. Published Beerten alignment and IEEE benchmark validation remain separate
work: the selected loading direction, generator/converter constraint treatment,
and reference model must be matched before interpreting this as a published
physical margin. No benchmark conversion, TRANSPA, hydro-corridor, continuous
shunt consolidation, or general recovery rewrite was undertaken.
