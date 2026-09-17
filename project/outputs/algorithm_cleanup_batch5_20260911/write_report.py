from pathlib import Path
import json
out=Path(__file__).resolve().parent
v=json.loads((out/'verification_summary.json').read_text())
s=json.loads((out/'analysis_final_02/summary.json').read_text())
p=json.loads((out/'preservation.json').read_text())
rows='\n'.join(f"| {a['name']} | {a['passed']} | {a['failed']} | {a['skipped']} | {a['elapsed_seconds']:.2f} |" for a in v['suites'])
steps='\n'.join(f"| {a['step']} | {a['accepted']:.12f} | {a['rejected']:.12f} | {a['success']} |" for a in s['steps'])
text=f"""# Algorithm cleanup batch 5 — Beerten control-bound diagnosis and termination reporting

**Completed: diagnosed control-bound termination and repaired reporting.**
The unchanged lambda-0.8 automatic-control scenario returns success=0 at a
switched-shunt voltage-control bound. Its electrical candidate converges.
The former message incorrectly called this a failed control re-correction.
The repair names the actual cause, preserves the accepted point and rejected
candidate separately, and scopes every reported convergence/completion fact.

Final verification: **{v['passed']} checks passed, {v['failed']} failed,
{v['skipped']} skipped, {len(v['exceptions'])} suite exceptions**. Detailed results,
including any warning lines, are in `verification_summary.json` and each suite log.

## Reproduction and demonstrated cause

`reproduce_02/reproduction.mat` loads the four original variables from batch 4's
immutable `beerten_probe.mat` and calls `runcpf_psse(b4f,b4t,b4o)`. Every accepted
state vector exactly matches the historical failed probe. This confirms that
the event remains present after batch 4 and was not caused by the shared shunt
extraction. Options, base and target cases are saved with the reproduction.

`trace_01/trace.mat` uses an output-local diagnostic copy of the starting solver.
It records decisions before rollback, proposed base/target cases, full candidate
results, correction state vectors, contexts, residuals and Newton iteration
counts. Its accepted trace also matches the original exactly.

| Observation | Value |
|---|---:|
| Requested lambda | 0.8 |
| Last accepted lambda | {s['last_lambda']:.15f} |
| Rejected candidate lambda | {s['candidate_lambda']:.15f} |
| Last accepted bus-5 voltage | {s['last_vm5']:.12f} pu |
| Candidate bus-5 voltage | {s['candidate_vm5']:.12f} pu |
| Shunt voltage band | 0.95–1.03 pu |
| Unchanged VCTOLV | 0.00001 pu |
| Effective lower acceptance edge | 0.94999 pu |
| Shunt BINIT at both points | 15 MVAr |
| Last accepted electrical residual | {s['last_residual']:.6g} pu |
| Rejected candidate electrical residual | {s['candidate_residual']:.6g} pu |
| Final attempted CPF step | 0.0001953125 |

The shunt has only 0/5/10/15 MVAr legal states. At lambda 0.394617123742 it
moves 0 → 5 → 10 → 15 in three fixed-loading corrections. All converge in two
Newton iterations each, with residuals approximately 7.59e-9, 7.74e-9 and
7.90e-9 pu, below the unchanged 1e-8 tolerance. The initial off-grid ULTC ratio
1.0 is normalized to 1.011111111111111 and corrected successfully at lambda 0.
No later tap move occurs in this scenario.

At the terminal candidate, the direct report has one low-voltage shunt violation,
one blocked shunt, zero changed buses/generators/branches and no tap violation.
The ULTC regulates bus {s['tap_regulated_bus']} at {s['tap_regulated_vm']:.12f} pu,
inside its original band. No legal upward shunt move remains. The solver's
`~changed` / unsatisfied-controls branch returns control failure before any
new electrical correction. The existing stop policy does not apply selective
freeze. CPF rolls back and reduces the step until another halving would fall
below the unchanged 1e-4 minimum. There is no failed Newton re-correction at
this final event and no observed control cycle.

The active-set handoff retains the original bus modes, generator bounds/VG/status,
converter AC modes [3,2,3], DC modes [2,1,2], transformer ratio and BINIT/BS.
No generator/converter limiting event precedes this rejection. The candidate's
post-solve `check_capability_limits` audit reports zero violations using the
original generator data and converter station ratings. Converter internal
voltages are approximately 0.9787, 1.0115 and 0.9523 pu. The original options
have optional capability enforcement and CPF Q-limit enforcement set to zero;
these were **not changed**. Thus this event does not test active capability
saturation/release logic. Original generator Q bounds also pass explicitly.

## Independent electrical and step diagnostics

![Beerten control-band diagnostic](event_diagnostic.png)

`diagnostics_02/diagnosis.mat` independently solves the full AC/DC/VSC equations
at five matched loadings for all four legal shunt states, with the accepted
transformer ratio specified explicitly. These are fixed-control diagnostics,
separate from the automatic lambda-0.8 scenario. No ratings, electrical limits,
residual tolerances or target are changed to make that scenario pass.

All 20 fixed-state PF solves succeed, including at lambda 0.42 and 0.45.
At the rejected loading, bus-5 voltages for B=0/5/10/15 are approximately
0.935922099 / 0.940568934 / 0.945256586 / 0.949985565 pu. Even the largest legal
B is outside the required band. At lambda 0.45, B=15 still has a converged
solution at approximately 0.943363884 pu. The final regression independently
checks complex voltage agreement with each accepted CPF point and the rejected
candidate, and full AC station-network, DC, converter and loss equations.
Maximum fixed-state AC balance residual in that gate is
{s['max_fixed_ac_balance']:.6g} pu, below 1e-8.

| CPF starting step | Last accepted lambda | Rejected lambda | Overall success |
|---|---:|---:|---:|
{steps}

Every step sensitivity reports `control_bound` with a converged electrical
candidate on the same B=15 state. Independent fixed-state bisection brackets
the voltage-band edge at [{s['fixed_state_band_edge_bracket'][0]:.12f},
{s['fixed_state_band_edge_bracket'][1]:.12f}]. This is a diagnostic control-band
boundary, not an amended CPF target or a stability limit. The last accepted
lambda tangent is {s['last_lambda_tangent']:.6g}, still positive. The candidate
Jacobian reciprocal condition estimate is {s['candidate_jacobian_rcond']:.6g};
this scale-dependent number alone is not a stability certificate. The stronger
evidence against an electrical limiting point here is the independently solved
same-state full equations at and beyond the event.

**Classification:** exhausted discrete voltage regulation under the declared
stop policy, plus an implementation defect in reporting. No demonstrated
numerical difficulty, cycling, infeasible electrical transition or voltage
collapse occurs at this event. Exhausting this controller does not establish
global network infeasibility, optimality, or the maximum reachable loading
under another control/dispatch policy. Reaching lambda 0.8 was not assumed.

## Bounded repair and API meaning

Production changes are confined to `matpower/lib/runcpf_vsc_mtdc.m`:

- Preserve terminal PSS/E decision diagnostics and the rejected electrical
  candidate/state vector separately from the accepted trace. Distinguish
  control bound, unresolved control, update failure, cycling, iteration limit
  and actual electrical correction failure.
- Replace the generic PSS/E re-correction-failed message with the recorded
  cause and both candidate and accepted lambda values.
- Add `cpf.termination` with explicit cause, success scope, requested endpoint
  completion, accepted point index/lambda, NOSE-event detection and the scope
  of `max_lam`. No trace maximum is certified as a stability margin.
- Scope `convergence` to its electrical point and expose `overall_success`.
  The result constructor now derives electrical convergence from the finite
  residual and configured tolerance instead of unconditionally setting true. An unavailable electrical evaluation
  now returns the input and failed state vector with `ac=[]` and
  `evaluation_available=false`, rather than throwing during result construction.

For the main fixture, overall success remains false; the exported last accepted
point remains electrically converged; the separately stored rejected candidate
also remains electrically converged; requested endpoint and nose flags are false.
All original accepted lambda/state/bus/branch/gen/converter arrays are exactly
preserved. This is not a new acceptance or recovery policy.

The pre-existing API treats an orderly control-bound stop in NOSE/FULL mode
as success. That compatibility behavior remains explicit through
`success_scope='configured_stop_policy'`; `requested_endpoint_reached=false`
and `nose_detected=false` prevent it from being presented as the requested nose.
The new gate tests this distinction. Changing the success API or accepting
out-of-band saturated controls would be separate policy work. No implicit
freeze, lockout, limit relaxation or recovery-framework rewrite is introduced.
See `docs/CPF_TERMINATION_CONTRACT.md` for field semantics.

## Verification

`verification_01/` contains the complete matrix for the initial reporting
repair. After the empty-evaluation guard, `focused_final/` and the full VSC
suite in `verification_02/` were rerun. The table selects the latest run of
each suite, without counting reruns twice.

All numerical execution used MATLAB MCP after `iniciar_proyecto`, on R2025b.
No MCP connectivity failure, CLI fallback, path reset or solver-option workaround
was used for reproduction or acceptance. MP-Test assertion counts and exceptions were captured explicitly.

| Suite | Passed | Failed | Skipped | Seconds |
|---|---:|---:|---:|---:|
{rows}

The affected prior suites cover physical balance and handoff, ULTC decisions,
switched shunts, both earlier Beerten gates, full PSS/E controls, full VSC and
standard CPF. Standard CPF retains 88 user-callback skips and nine legacy
case14 angle-wraparound skips under MP-Core; no new gate is skipped. Original historical assertions and scientific source changes
remain present. The batch-5 gate additionally checks the specific rejected
event, independent fixed-state solves, step sensitivity and completion semantics.
`code_analysis.json` records MATLAB Code Analyzer results for edited/new MATLAB
production and test files: both have zero findings. Selected final suite logs
contain no MATLAB warning lines. Any exploratory command issues are described in
`execution_notes.json`; these are not disguised as numerical solver failures.

The first reproduction attempt used the lower-level entry point without wrapper
control activation and therefore succeeded in a different scenario; it remains
in `reproduce_01/` and is not used as reproduction evidence. The first diagnostic
log printed a row from the extended bus ordering instead of original bus ID 5;
its complete saved PF results remain valid, and the corrected rerun is isolated
in `diagnostics_02/`. Inspection-only undefined-field errors were corrected
without changing numerical options. An additional synthetic negative-path probe multiplied base demands by 1000
without changing ratings or solver options. Both the starting solver and the
initial reporting patch threw `Dot indexing is not supported for variables of
this type` while exporting an empty electrical evaluation.
`base_failure_probe/baseline_error.log` preserves the exact pre-existing stack.
The bounded constructor guard fixes this packaging failure; two regression
checks require false electrical/overall flags, a preserved failed iterate,
empty solved AC data and no accepted CPF point. This manufactured input is
not evidence about a Beerten physical limiting point. The full VSC suite was
rerun after the guard. The initial 75-check gate is retained in
`focused_01/`; `focused_final/` holds the final strengthened checks.

## Preservation and reproducibility

`before/`, `status_before.txt` and `preexisting.patch` preserve entry context.
The workspace root is not a Git repository; MATPOWER has its own nested repo.
`batch5.patch` is relative to the starting working files, not Git HEAD, and
contains only the solver reporting change, new focused test, termination
contract and tests README addition. `patch_application_final.json` verifies
that it applies to a fresh baseline copy and reproduces all intended files,
normalizing line endings only for scratch comparison.

`preservation.json` checks {p['baseline_files']} baseline files:
{p['unchanged']} are byte-identical; only the solver and tests README changed
among those existing files. Input cases, previous batch-4 evidence, existing
regressions and control decision implementations are preserved. `structural_preservation.json` additionally verifies unchanged equations,
Newton/CPF correction, tangent, state handoff and capability/control decision
helper bodies. New outputs
are under this batch's directory with fresh destinations for reruns.

To reproduce after MATLAB MCP initialization:

```matlab
iniciar_proyecto;
addpath(fullfile(pwd,'tests'));
b5 = fullfile(pwd,'outputs','algorithm_cleanup_batch5_20260911');
addpath(b5);
run_batch5_suite('t_beerten_termination_batch5',fullfile(b5,'fresh_gate'), ...
    fullfile(b5,'fresh_gate','evidence'));
```

The saved `trace_01` is the pre-repair instrumentation evidence. The final
production failure now contains the corresponding terminal candidate and
control decision without needing the diagnostic copy. Output-local diagnostic,
summary and artifact scripts are retained alongside complete MAT/JSON/log files.

## Remaining uncertainty and readiness

This batch resolves the reproduced event's classification and reporting. It
supports proceeding to a separately scoped published Beerten alignment study
and IEEE benchmark validation; it does **not** establish agreement with the
published network, station/loss conventions, control policies or reference
numerical results. Capability switching and limiting-point validation still
need their intended benchmark fixtures and independent reference evidence.
The control-bound location is scenario- and policy-dependent, and must not be
published as a nose or voltage-stability margin.

Broader recovery policy, continuous-shunt consolidation, benchmark conversion,
TRANSPA and the hydro corridor remain deferred. No proposed recovery-policy
change is part of this repair.
"""
(out/'REPORT.md').write_text(text,encoding='utf-8')
print('REPORT.md written')
