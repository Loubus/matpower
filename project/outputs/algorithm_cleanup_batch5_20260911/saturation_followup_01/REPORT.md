# Batch 5 follow-up: accept physical saturation and retain full-model control reports

The user-authorized saturation policy is implemented for unified PF/CPF.
The original Beerten bus-5 loading scenario passes the former lambda-0.4107
blockage and reaches its unchanged requested lambda 0.8 within the original
target tolerance. Physical saturation leaves the controller eligible to move
away from its limit if its existing voltage rule later requests it.

This is a declared control-policy change plus a separate PF acceptance bug
repair. It is not a rating increase, tolerance relaxation, freeze, new dispatch
policy, or evidence that lambda 0.8 is a voltage-stability margin.

## Changes and scope

- `vsc_mtdc.psse_control_limit='saturate'` is the new default. A fresh full-model
  pass must request no change, and every remaining regulation violation must
  be an outward physical-bound request. Any pending legal move still requires
  a full electrical correction. Cycling, unresolved requests, unsupported
  modes and failed electrical solves receive no saturation exemption.
- `mp.psse_unified_control_acceptance` shares that settlement classification
  between unified PF and CPF without modifying controller state or eligibility.
  Existing tap/shunt decision helpers, ranges, control tolerances, equations,
  Newton corrections, tangent construction and capability handoffs are retained.
- The PF bug is repaired independently: an unchanged auxiliary AC active set
  cannot overwrite the supported voltage-controller reports with an auxiliary
  voltage. Final classification uses the actual full-model voltage. Auxiliary
  recovery proposals remain available and require full-model correction.
  PF also uses CPF's existing PQBRAK activation boundary: inactive metadata
  alone cannot force an unnecessary auxiliary solve. Active equivalent-load
  processing retains its existing path.
- PF separates electrical `converged` from `overall_success` and reports its
  control acceptance. CPF retains the last accepted point and emits informational
  `PSSE_CONTROL_SATURATED` samples rather than freeze/failure events. Unresolved
  control transitions under `saturate` return failure even for NOSE/FULL requests.
- Explicit `stop` and `freeze` remain available. Saved options with `stop` are
  not silently migrated. The historical full-VSC and earlier Beerten gates now
  select their intended `stop` mode explicitly; their assertions are retained.

See `docs/CONTROL_SATURATION_CONTRACT.md` for field semantics and the exact scope.
The AC-only controller loops and general recovery framework are not rewritten.

## Demonstrated numerical outcome

The new main run uses the immutable batch-4 base/target and options with exactly
one declared scenario change: `psse_control_limit` becomes `saturate`.
The original load-growth definition, lambda-0.8 request, original ratings,
controller bands and solver/control tolerances remain unchanged.

| Quantity | Result |
|---|---:|
| Accepted endpoint lambda | 0.799998623161974 |
| Requested lambda | 0.8 |
| Overall success / requested endpoint reached | 1 / 1 |
| Termination cause | requested_lambda |
| Bus-5 voltage | 0.872288364217 pu |
| Shunt BINIT | 15 MVAr |
| Transformer tap | 1.01111111111111 |
| Electrical mismatch | 2.54157e-12 pu |
| Nose detected / independently validated stability margin | false / false |

At the exact former rejected loading, automatic PF from the original initial
state returns success=1, V5=0.949985565573 pu and reports
`saturated`, `regulation_satisfied=false`. Its electrical mismatch is
6.90509e-09 pu. Under explicit `stop`, the same full-model electrical
point now correctly has overall failure and a control-bound report; the old
auxiliary `inside_band` claim is gone. These flags describe different policy
outcomes on the same electrically solved state.

The focused gate independently solves every accepted CPF state and materializes
the actual stored CPF state for AC/DC/converter/loss balances at 1e-8 pu. It
checks automatic PF from original controls at the former event, 0.45 and 0.8,
CPF steps 0.1/0.05/0.025, original grids and ratings, both physical bounds and
reverse eligibility for both device types, retained explicit locks, and rejection
of cycling, unresolved requests, unsupported modes and electrical failure.
Fixed-state and prescribed-voltage decision probes are separate diagnostics.
An additional negative fixture narrows only its copied shunt regulation band
to [0.95, 0.95001] pu to force alternating discrete requests. It verifies actual
CPF cycle termination and failure flags; it is not the main Beerten case and
does not change the original input file or any solver/control tolerance.
A separate copied transformer fixture requests an unreachable [1.30, 1.31] pu
regulation band to exercise saturated-tap acceptance through complete PF and
CPF solves. Its tap grid and ratings remain original; it is a policy regression,
not a proposed study voltage objective or a modification of the main case.

The saved fixture originally has optional capability enforcement and CPF P/Q,
voltage and flow limit enforcement off. These settings were preserved, not
disabled by this change. The post-solve endpoint capability audit is retained
verbatim in `summary.json` and the focused MAT evidence; it reports
0 violations. This run therefore
does not validate all operational-limit enforcement regimes.

## Verification

Latest selected runs: **2207 passed, 0 failed,
97 skipped, 0 suite exceptions**.

| Suite | Passed | Failed | Skipped | Seconds |
|---|---:|---:|---:|---:|
| t_beerten_termination_batch5 | 77 | 0 | 0 | 10.35 |
| t_control_acceptance_batch1 | 43 | 0 | 0 | 2.12 |
| t_control_handoff_batch2 | 53 | 0 | 0 | 6.37 |
| t_control_saturation_batch5 | 105 | 0 | 0 | 15.62 |
| t_cpf | 333 | 0 | 97 | 12.25 |
| t_mpxt_psse | 508 | 0 | 0 | 91.65 |
| t_swshunt_acceptance_batch4 | 67 | 0 | 0 | 2.37 |
| t_swshunt_beerten_batch4 | 281 | 0 | 0 | 2.08 |
| t_ultc_acceptance_batch3 | 52 | 0 | 0 | 2.15 |
| t_ultc_beerten_batch3 | 358 | 0 | 0 | 2.47 |
| t_vsc_mtdc | 330 | 0 | 0 | 853.84 |

The standard CPF skips retain their prior MP-Core/user-callback scope. Each
suite's complete log, MP-Test counts and exception field are preserved. The
first run exposed historical default-policy assertions and two new tests
that incorrectly demanded 1e-8 loading accuracy despite the saved 1e-5 target
tolerance. The historical scenarios now explicitly select `stop`, and the new
checks use the original configured target tolerance. No solver tolerance changed.
The first-run failures remain in `verification_01`; fresh corrected runs are in
`verification_02`, with final focused, termination and physical/handoff reruns
in `verification_03`. Counts above select the latest run, without double counting.

All numerical execution used MATLAB MCP after project initialization, with
no path reset, CLI fallback or integration error. The long exploratory nose
probe occupied the session before queued verification. An accidental exploratory
MATLAB command typo (`b5s nose=0`) produced an undefined-name error and performed
no solve. A read-only Python import attempt found no SciPy in the project venv;
the retained standard-library MAT-v5 reader inspected options only. Numerical
solves continued through MATLAB MCP. The artifact builder's first read failed
under Windows' default text encoding; explicit UTF-8 fixed that file-processing
error. `code_analysis.json` records zero Code Analyzer findings in the two
edited solvers, new acceptance helper and new focused test. Selected final
suite logs contain no MATLAB warning lines.

## Preservation and readiness

`before/`, `preexisting.patch`, the baseline hashes, `preservation.json`,
`source_manifest.json` and `structural_preservation.json` preserve the working
baseline and verify the bounded changes. `saturation.patch` is isolated against
the entry working files, not Git HEAD; `patch_validation.json` verifies its
application to a fresh scratch baseline. All original batch-4 and batch-5
evidence, including the original REPORT.md, remains unchanged.
The hash check covers 1,101 baseline files, with only nine declared existing
files changed and no unexpected changes. All 15 checked equation/correction,
tangent, state-transfer and capability function bodies are identical.
`option_diff.json` verifies the single declared main-scenario option change.

This resolves the demonstrated saturation blockage and PF report inconsistency.
It does not certify the published Beerten model, a physical limiting point,
or IEEE benchmark alignment. Full intended capability-switching scenarios,
independent reference comparison and limiting-point validation remain separate.
Continuous-shunt consolidation, broader recovery rewrites, benchmark conversion,
TRANSPA and the hydro corridor remain deferred.

## Separate longer exploratory search

`nose_probe.mat` retains the initial saturation-policy NOSE search. It was
started before the final reporting/auxiliary-acceptance edits and is not a
final-code benchmark. It continued to approximately lambda 1.93385 before
reporting a control cycle, with no detected nose. Its legacy success flag is
preserved as historical exploratory evidence; it must not be read as successful
nose completion or a validated stability margin. `cycle_summary.json` records
the decision states, residuals, absolute candidate loading and a separately
bounded diagnostic restart using the final code.

The restart shifts the loading origin to the exported accepted state and keeps
the original demand-growth direction. Its three-step budget is explicitly a
diagnostic bound, not a shortened target for the main lambda-0.8 acceptance run.
It does not replace a complete final-code NOSE trace or validate the absolute
limiting-point location. General control-cycle recovery remains deferred.
The restart failed its base solve and therefore did not reproduce the later
cycle. It is retained as an unsuccessful diagnostic, not evidence of collapse.
The late exploratory decision records show bus active-set changes with a fixed
tap and V5 near 0.6785 pu; the cause of this different low-voltage regime needs
separate diagnosis. Physical tap/shunt cycling is not established by that
classification. The focused synthetic cycle test, rather than this failed
restart, verifies final-code unsuccessful NOSE-request reporting.
`later_auxiliary_details.json` shows active PQBRAK processing (threshold 0.7,
non-unit scale) and successive proposed PD/QD updates at this later event;
BINIT remains 15. This is a different auxiliary equivalent-load regime from
the repaired lambda-0.4107 control-band event. Its convergence/cycle-detection
behavior is not resolved or validated by this bounded saturation repair.

Restart outcome: `base_failure`, success=False, requested endpoint reached=False, nose detected=False.
