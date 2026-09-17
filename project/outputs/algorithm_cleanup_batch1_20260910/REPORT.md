# Algorithm cleanup batch 1 — VSC investigation, 2026-09-10

The four known VSC failures reproduce on the unchanged scientific implementation.
They expose control-state handoff and result-export defects; they cannot be
dismissed as optional exact PSS/E matching. Some exact expected values were also
produced by an incomplete auxiliary model and should not become physical targets.
No production solver, control policy, rating, limit, tolerance or original test
assertion was changed. ULTC/shunt refactoring, TRANSPA and hydro-corridor work remain
deferred.

The new [acceptance contract](../../docs/CONTROL_ACCEPTANCE.md) separates physical
requirements, RAW/interface correctness, declared policy and historical numerical
expectations. [The focused test runner](../../tests/t_control_acceptance_batch1.m)
is a separate physical gate, not a replacement for `t_vsc_mtdc` or `t_mpxt_psse`.

## Reproduction and physical meaning

The full unmodified `t_vsc_mtdc(0)` first returned **326/330 passed, four failed,
no skipped checks**, in 396.77 seconds through MATLAB R2025b MCP. The failed
assertion identities and values are independently reproduced in the small
fixtures and saved under `evidence.legacy` in the acceptance MAT/JSON files.
The second full run, captured in `vsc_reproduced.log/.mat`, again ran all 330
checks with **326 passed, four failed, zero skipped**, in **289.42 seconds**.
Its failures are exactly 110, 111, 283 and 284; it emitted no warning lines.

| Original check | Measured result | Original expectation | Interpretation |
|---|---|---|---|
| 110 | PF `psse_controls.changed = 0`, `success = 1` | Changed flag true | Controller is not handed the solved shunt state. This is not merely a choice of event label. |
| 111 | PF top-level and extended AC `BS5 = 0`, but `BINIT = 9`; solved `Vm5 = 0.990329389197` | `BS5 = 9` | Metadata/electrical-state disagreement and unresolved deadband. Requiring exactly 9 is not independently justified. |
| 283 | CPF bus 2 remains PV (`2`), but GENQ report says limited at QMAX | PQ (`1`) | Expansion erased the auxiliary PQ state. Independently, the original complete model does not require this upper limit to bind. |
| 284 | CPF `QG2 = -33.8559377465` MVAr, report says upper limit active | `QG2 = QMAX2 = -20` MVAr | Original range `[-100,-20]` is respected, but the returned electrical state contradicts the binding-limit report. Do not describe this value as an original-Q-range violation. |

GENQ final matrix limits remain `[-100,-20]`, not a fixed interval `[-20,-20]`.
This distinction matters: the physical failure is an inconsistent control mode
and report, not a claim that every feasible PV solution must be clamped at -20.

The existing CPF shunt comparison succeeds with `BS5 = BINIT = 6` and
`Vm5 = 0.995198526875` at approximately lambda 0.2 on the 2% load-growth target.
The specified deadband is `[0.995,1.005]` pu with `1e-5` pu control tolerance.

## Confirmed causes and isolated evidence

### 1. Topology expansion discards solved controls

`mp.psse_branch_expand` restores `[BUS_TYPE PD QD GS BS]` from
`state.original_bus` for every expanded bus. In the auxiliary AC route the tiny
converter transformer branches are collapsed, making this restoration active.
The metadata retains the solved control state while the returned bus array is
reset. The following values come from the same auxiliary solve, before and after
expansion, not from separate operating assumptions:

| Fixture | Before expansion | Returned after expansion |
|---|---|---|
| Switched shunt | Bus 5 `BS = 9` | Bus 5 `BS = 0`; `BINIT = 9` remains |
| GENQ | Bus 2 PQ (`1`), `QG = -20` | Bus 2 PV (`2`), `QG = -20`; limited report remains |

The instrumented CPF copy records an auxiliary result with PV bus 2 and QG=-20
already at `apply_psse_active_set_update`. The CPF base/target and rebuilt context
retain that PV bus. At lambda 0 it recomputes QG=-34.0683841294, and at the final
point QG=-33.8559377465. Thus the bus-mode loss occurs before CPF's rebuild; this
is not evidence that its context cache ignored a requested PQ bus.

The numeric Q after rebuild also reflects a changed voltage constraint:
`apply_psse_active_set_update` copies the auxiliary VM as a starting value, and
`build_unified_model` stores `fixed_vm = ac.bus(:,VM)` for fixed-voltage buses.
The falsely restored PV bus consequently holds Vm2=0.998636016202 even though
the generator VG schedule remains 1.0. The focused gate separately requires a
bus returned as PV to satisfy its voltage schedule. This starting-value versus
setpoint distinction must be preserved when repairing the handoff.

`mp.psse_swdev_expand` contains the same reset pattern, but this investigation
has not executed a SWDEV failure case. Treat that as a review lead, not a verified
additional failure. A repair must map device contributions back to original buses
without duplicating aggregate loads/shunts across collapsed groups. Copying every
aggregate column to every original bus would be incorrect.

### 2. The extended AC result drops a converter proxy generator

`build_ac_results` in `runpf_vsc_mtdc_unified` appends the voltage-controlling
converter's proxy generator after internal indexing, then calls `int2ext` with
the old generator mapping. In the Beerten fixture `r.ac.order.int.gen` has three
rows but `r.ac.gen` has only two. The missing row is the converter at internal
station bus 9 (external numbering here is also 9).

The Newton AC/DC solution itself reports a residual of about `3.71e-11` pu for
the shunt PF, but recomputing balance from the exported AC arrays gives
`0.220712400453` pu concentrated at bus 9. Restoring only that missing proxy row
from the saved internal result, with its bus identifier mapped correctly,
reduces the residual to `5.19065e-11` pu. No network parameters or ratings change.
The proxy is an algebraic representation of the solved converter injection;
its large numerical bounds do not constitute physical converter ratings.

This incomplete export is fed to `control_case_from_unified_result`, so the
auxiliary controller studies a different injection pattern. Diagnostic projection
comparisons with only the missing row restored give:

| Auxiliary decision | Existing projection | Restored-proxy diagnostic |
|---|---|---|
| Shunt BINIT | 9 | 6 |
| GENQ upper-limit flag | True | False |
| GENQ QG2 (MVAr) | -20 | Approximately -30.3048 |

The exact “9” and “PQ at -20” expectations therefore are not validated PSS/E truth.
They reflect historical auxiliary behavior. Preserve the original assertions
until a deliberate correction separates bug snapshots from scientifically valid
requirements; do not simply replace them with current failing outputs.

The restored-proxy auxiliary calculation still uses the existing AC projection
and collapse approximation. It is diagnostic evidence, not a replacement for
decisions checked against the actual monolithic AC/DC model.

### 3. PF's direct controller receives input voltages

`unified_build_results` starts from `results = mpc` and writes solved AC arrays
under `.ac`. Within PF settlement, `unified_pf_psse_control_update` passes `r.bus`
to `psse_unified_control_update`. For this fixture the former contains Vm5=1,
while `r.ac.bus` contains Vm5=0.990329389197. The unchanged decision function,
given those two arrays, returns respectively no change/BS=0 and one capacitor
step/BS=1. CPF stamps solved original-bus arrays before its direct controller,
explaining its different route and successful six-step shunt result.

Correcting only expansion would still leave this stale-voltage path and the
incomplete auxiliary model. Correcting only metadata would leave an unregulated
electrical state. These are bounded data-flow repairs to establish before changing
ULTC or shunt decision policy.

## Physical acceptance gate

The initial 40-check physical gate returned **33 passed, seven failed**. It found:

- Three exported-AC balance failures (PF shunt, CPF shunt, CPF GENQ), with
  residuals `0.220712400453`, `0.216444659515`, `0.227975847591` pu respectively.
- PF shunt BS/BINIT synchronization and reachable-deadband failures.
- GENQ binding-report and bus-mode consistency failures.

All three configured monolithic residual checks passed at tolerance `1e-8` pu;
DC nodal and converter power balances also passed. This separates solved-equation
convergence from export/control correctness. Original Q bounds, legal shunt grid,
direction, fixed-part preservation, remote regulation, disabled status and both
saturation boundaries passed. Four fixed-state matched-loading PF/CPF comparisons
had maximum voltage differences below `1.76e-12` pu. These passes do not waive the
red physical gate.

The final **43-check gate returned 33 passed, 10 failed**, with no skips, in
2.874 seconds including its numerical fixtures. The three added failures are
`expansion.shunt_state`, `expansion.genq_mode`, and `genq.pv_voltage_schedule`.
See `acceptance_final.log`, `acceptance_final/acceptance.json`, and the full states
in `acceptance_final/acceptance.mat`. **The refactor gate is not satisfied.**
These are multiple checks of the identified defects, not ten independent
regressions introduced by this batch. `verification.json` summarizes the evidence.

MATLAB Code Analyzer reported zero issues for the acceptance runner, its fixture
and `investigate_boundaries.m`. `probe_vsc.m` has two unused-output warnings for
`prep` and `op`, retained intentionally in its full workspace save; see
`static_analysis.json`. No production-code static-cleanliness claim is made.

## Evidence, preservation and execution notes

- `matpower_before.patch` and `git_status_before.txt` capture the pre-existing
  scientific/dependency working-tree differences. The project root is not a Git
  repository; `matpower/` is the scientific repository.
- `source_hashes.json` identifies the initial solver and original regression files.
- `preservation.json` verifies those four hashes are unchanged and the full
  tracked working-tree patch is byte-identical before/after (SHA-256
  `7143752506eed68d69cdb371544216e5f2aebc762cf7fa7bf1a58f116e776322`).
  New files are tests, documentation and evidence; the README links them. Existing
  historical reports/results were not overwritten. The auxiliary trace copy is
  outside the scientific repository and normal startup paths.
- `probe.mat` holds exact fixtures/options, PF/CPF states, direct-voltage probes,
  and unconstrained-versus-explicitly-fixed-Q diagnostics. The free complete-model
  PF needs QG2=-30.2926790352 at Vm2=1; explicitly fixing Q=-20 is feasible at
  Vm2=1.00369755805. These are named diagnostics, not relaxed acceptance cases.
- `boundaries.log` and `boundaries.mat` contain same-solve before/after expansion
  states and the restored-proxy projection comparisons.
- `genq_trace.mat` and `runcpf_vsc_mtdc_batch1_trace.m` capture active-set transfer
  and result construction. `make_trace_copy.py` produces this diagnostic copy by
  renaming the original function and adding snapshots only; production code stays
  untouched.
- `acceptance_initial/` and `acceptance_initial.log` preserve the initial physical
  gate. No numerical/model warning was emitted by these focused runs. The tests
  retain any warnings emitted by future runs; none are disabled by the harness.
- MATLAB MCP worked throughout. The initial diary files were empty because MCP
  captured command output; the first attempted counter snapshot used the wrong
  MP-Test global (`t_`) and is empty. Those artifacts are retained but are not
  evidence of a pass. A second unchanged full run explicitly captures `evalc`
  output and the actual MP-Test globals in `vsc_reproduced.log/.mat`.
- An exploratory query incorrectly used literal column 12 as voltage magnitude
  (`VM` is column 8); its large residual was discarded. The persisted gate and
  boundary script use `idx_bus` and reproduce the bus-9 export imbalance stated
  above. A separate lookup of `aux.psse.pf` failed because the AC auxiliary does
  not expose that VSC-wrapper field; inspecting `psse.branch_collapsed` and the
  task source established the expansion path. Neither was a solver failure or
  a reason to change numerical settings.

Run `iniciar_proyecto` from the root, then follow `tests/README.md`. Use a fresh
output directory. To repeat the diagnostic scripts, copy them together into a
fresh direct child of `outputs/`; do not overwrite this evidence directory.

## Next bounded implementation

Repair converter result export, preserve control changes through topology
expansion, and supply solved voltages to the PF direct controller. Establish
corrected-model expectations with the existing small fixtures before changing
decision policies. Re-run the focused gate and the full original electrical,
adapter, derivative and capability regressions; retain and explicitly adjudicate
historical numerical expectations that no longer describe the corrected model.
Do not increase ratings, suppress physical limits, freeze controls implicitly or
relax assertions to obtain a green run. Beerten published-model alignment remains
open and the broader ULTC/shunt acceptance coverage in the contract is still
required before refactoring those policies.
