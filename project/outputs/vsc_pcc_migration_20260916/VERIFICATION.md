# Verification record — 2026-09-16

- MATLAB MCP used throughout; initialized with `iniciar_proyecto`.
- Dedicated station/PCC regression: **141/141 passed**, final source after cleanup.
- Broader regression rerun: **326 passed, 4 skipped, 0 failed**. The four FULL
  continuation checks (256–259) passed in `legacy_suite_current.txt`; their solver
  equations and fixture were unchanged. `prepare_repeat.py` creates the task-local
  repeat harness that explicitly skips those previously checked items. The
  production `t_vsc_mtdc` still runs all 330 checks by default.
- Six checked production files have **zero MATLAB Code Analyzer findings**.
  The new test has one nonfunctional “extra comma is unnecessary” style finding.
- Base five-bus unified PF: success=true, 3 iterations, maximum mismatch
  **2.9705e-12 pu**. Sequential base PF also succeeds with default settings.
- Filtered high-impedance sequential stress case: default 20 iterations fail to
  converge; the documented 100-iteration test budget succeeds in 66 iterations.
  Tolerances and production defaults are unchanged. This limitation is retained.
- Full-station maps were checked against independent explicit branch terminal
  flows, including resistance, filter G/B, branch pi charging and phase shift.
- Current/voltage boundaries, zero/tiny impedances, empty regions, analytic
  Jacobians, PQ/Q/PV/V, droop and CPF PCC schedules are covered by the new tests.
- Mathematical nose regression was refreshed only after two step sizes agreed
  to **2.84e-11** in lambda and both reported actual nose detection. An initial
  smaller-step probe exhausted its 120-step budget; success=true meant configured
  stop, **not** nose detection. Doubling that probe's step budget allowed it to
  reach the requested event; no tolerance was relaxed. This is an unconstrained
  mathematical benchmark, not a hardware operating margin.
- The changed PSS/E control-limit snapshot was checked by independent PF solves
  at lambda minus/plus 1e-4: the lower one succeeds and the upper one fails.
- Offline HTML: 16 SVG-rendered equations, valid image, zero missing local links,
  zero browser errors, no desktop/mobile page overflow. Plot, table, cover and
  display equations visually inspected; screenshots are in `verification/`.

## Failed attempts retained and resolved

`legacy_suite_after_ports.txt` records that the old 250-MVA C2 test no longer
reaches the corrected current boundary. The revised test-only 200-MVA C2 rating
exercises the intended V-to-Q transition and reaches its endpoint. An intermediate
80-MVA test was too restrictive and did not reach that endpoint; its failure is
retained in `legacy_suite_current.txt`.

The old generator freeze fixture used 90 MVA. Under PCC Q control its base
reactive output is −32.6646 MVAr, outside the underexcitation boundary
(approximately −30.3077 MVAr at 40 MW). It therefore fails at the base instead
of exercising later freeze. A replay using the backed-up pre-migration solver
confirmed that the old fixture had worked with the old port definition. The
updated **test-only** 100-MVA rating makes the base feasible and still triggers
the later freeze event. See `legacy_freeze_comparison.json`.

The last two failed assertions were numerical snapshots for the old model:
the blocked control location and unconstrained mathematical nose. Their new
values were independently checked before updating the tests. See
`legacy_suite_before_snapshot_update.txt` and `changed_benchmarks.json`.

Early task-local export/probe scripts encountered syntax/structure-initialization
errors and were corrected; these were not numerical solver failures. A MATLAB
diary attempt returned an empty file, so subsequent logs were captured explicitly
with `evalc`. No unavailable-tool or numerical failure was hidden by CLI fallback.

## Reproduction

From an initialized project MATLAB MCP session:

```matlab
addpath(fullfile(pwd,'tests'));
t_vsc_pcc_station(tempname);       % fresh output directory
t_vsc_mtdc(0);                    % all 330 tests, including expensive FULL run
```

`change_manifest.json` and `changes.diff` record the changed files and preserved
case executable content. Backups of pre-edit files are under `before/`.
Historical outputs were not converted to the new PCC semantics.
