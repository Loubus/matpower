# Algorithm cleanup batch 2 — result export and control handoff

**Complete.** Both focused gates pass (43/43 and 53/53), the full VSC suite
passes 330/330, and the relevant electrical, RAW/interface, derivative and
capability regressions pass. In the selected final runs, **2,463 checks passed,
zero failed, and 97 existing core-CPF checks were skipped**. The repairs remove
the reproduced handoff blockers; ULTC policy consolidation remains deferred.

## Scope and preserved work

The repairs concern serialization of solved results and transfer of accepted
control state. No control selection, priority, deadband, limit-release, lockout,
freeze, rating or tolerance policy was changed. ULTC/shunt consolidation,
TRANSPA and hydro-corridor work remain deferred.

MATLAB R2025b ran through the initialized MATLAB MCP session, following
`.codex/MATLAB_MCP.md`. No CLI fallback, path reset or solver-option workaround
was used. Python work used the project `.venv`. All new verification evidence
is in this directory; each numerical rerun used a fresh subdirectory.

The workspace already contained extensive scientific changes. `preexisting.patch`
and `status_before.txt` preserve the initial nested MATPOWER Git state. `before/`
and `before_hashes.json` preserve pre-edit files; `batch2.patch` isolates this
batch from those prior changes. `source_manifest.json` records before/after
hashes. The original batch 1 gate, `t_mpxt_psse`, `t_psse`, study design, input
cases and historical output directories were not edited.

## Implemented repairs

1. **Converter export.** `runpf_vsc_mtdc_unified/build_ac_results` retains the
   converter proxy injections and maps their internal generator buses to external
   identifiers. Original generator rows, including offline rows, pass through
   `int2ext` with the original row count. Proxies are then appended and the
   generator maps are extended. P-only and P/Q cost layouts receive zero-cost
   proxy rows; generator labels retain their original identities. This also
   resolves the cost-indexing exception found by the new edge-case test. Proxy
   bounds retain their pre-existing algebraic values; they are not converter
   capability ratings.
2. **Topology expansion.** THRSHZ and SWDEV collapse retain the original switched
   shunt metadata. The shared `mp.psse_expand_bus_controls` reconstructs solved
   states: device-specific switched-B changes go to the original physical bus,
   fixed contributions remain, and any unattributed aggregate PD/QD/GS/BS delta
   goes once to the representative. It preserves solved PQ/PV/REF modes at the
   original generator locations, accounts for offline/limited/remote generators,
   and retains the representative's solved voltage for every group member.
   The helper also supports the existing bus-only expansion fixture.
3. **Voltage handoff.** Both normal and cycle-check PF direct-controller calls
   use `r.ac.bus`, the solved voltages. Unified PV/REF equations take the online
   generator's `VG`; `bus.VM` remains an initialization. PQ voltages remain
   unknowns. No regulation setpoint is inferred from an auxiliary warm start.
4. **Binding-Q handoff discovered by the stronger test.** PF/CPF active-set
   comparison and copying include QG when it is an online PQ generator's fixed
   input. Active-set signatures include that input, but not a free PV generator's
   changing solved Q. Recreating GENQ state retains a previously accepted limited
   flag when the generator is active, nonswing and at an original bound. The
   existing controller still owns any subsequent release decision.
5. **Stale auxiliary load cache.** When the exported projection has exactly unit
   PQBRAK scale and no active equivalent-load changes, its cached nominal demands
   are rebuilt from the current projection. This prevents a later CPF auxiliary
   solve from replaying the base-case loads. Non-unit PQBRAK and active
   FACTS/TWODC equivalents are retained; this is a cache repair, not a change to
   their characteristics.

## Incremental evidence

| Stage | Batch 1 physical gate |
|---|---:|
| Unchanged starting implementation (`baseline/`) | 33/43 |
| Proxy export (`stage1_export/`) | 40/43 |
| Topology expansion (`stage2_expansion/`) | 43/43 |
| Solved voltage and VG handoff (`stage3_voltages/`) | 43/43 |
| Final implementation (`physical_gate_final/`) | 43/43 |

The stronger crossing uses the same GENQ fixture and original range
`[-100,-20]` MVAr, with a 25% load-growth target. Before the additional handoff
repair, CPF reported success with PV bus 2 and QG approximately -16.3631 MVAr,
above its original upper bound. Its auxiliary solve had silently reset demand
to the base point and therefore reported a feasible, free generator. A separate
PF could enforce -20 while the top-level limit report incorrectly said free.
`genq_crossing_probe.mat` preserves the failing investigation; the repaired
crossing is saved in `genq_crossing_repaired.mat` and the final handoff evidence.

The repaired PF and CPF both enforce -20 MVAr, return PQ mode and report the
binding upper limit. All 12 accepted CPF points satisfy the original Q interval
and their active voltage/fixed-Q equation. A half-step CPF, a separate endpoint
PF and a repeated auxiliary solve agree within the declared physical tolerances.

## Justified historical expectation changes

The first full VSC run after the repairs, before expectation changes, completed
all 330 assertions: **325 passed, five failed, none skipped**. Its log is
`full_vsc_before_expectation_changes/run.log`. Failures were exactly 111, 112,
283, 284 and 285. The extra two compared with batch 1 were formerly passing
metadata expectations that encoded the defective auxiliary solution.

| Checks | Historical expectation | Repaired requirement and independent justification |
|---|---|---|
| 110 | PF reports a shunt change | Now passes unchanged: solved low voltage reaches the controller and an actual move is reported. |
| 111, 112 | BS = BINIT = 9 | Enumerate every unchanged legal B in `0:10` using full AC/DC PF equations. B=5 gives Vm5=0.994478602118, below the 0.995 deadband edge and its 1e-5 tolerance; B=6 gives 0.995312351572, inside the band. Six is the first reachable legal state from zero. Default assertions compute that state from the grid and retain their original 1e-10 state tolerance. |
| 283 | Bus 2 must be PQ | The unchanged light-load fixture is physically interior after restoring the converter injection. Its PV solution holds the original VG=1 and respects the original Q interval. Default check retains exact bus-type precision and requires PV. |
| 284 | QG must equal QMAX=-20 | QG is approximately -30.0801273962 MVAr. The new assertion recomputes its reactive nodal equation from the complete exported AC model at the original 1e-10 MVAr assertion tolerance. The focused gate independently compares a full-model PF at the same CPF loading and verifies original bounds. No observed Q number becomes a new target. |
| 285 | Upper-limit report must be active | Require a free report consistent with original bounds and VG. The new 25% load-growth fixture separately proves that a real upper-limit crossing changes the equation and reports the limit. |

The original assertions remain in `t_vsc_mtdc` and are runnable with
`t_vsc_mtdc(0, true)`. The default `t_vsc_mtdc(0)` uses the repaired-model
requirements. Historical MAT/JSON results and logs remain unchanged. This is
not a claim of new exact PSS/E compatibility: physical equations, input semantics
and declared controller behavior remain separate acceptance categories in
`docs/CONTROL_ACCEPTANCE.md`.

## Verification

Final selected runs, summarized in [verification_summary.json](verification_summary.json):

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Focused batch 1 physical gate | 43 | 0 | 0 |
| New batch 2 handoff gate | 53 | 0 | 0 |
| Full VSC/electrical/capability (`t_vsc_mtdc`) | 330 | 0 | 0 |
| Full PSS/E controls (`t_mpxt_psse`) | 508 | 0 | 0 |
| RAW/interface (`t_psse`) | 296 | 0 | 0 |
| AC PF (`t_pf_ac`) | 726 | 0 | 0 |
| DC PF (`t_pf_dc`) | 14 | 0 | 0 |
| Core CPF (`t_cpf`) | 333 | 0 | 97 |
| Jacobian (`t_jacobian`) | 64 | 0 | 0 |
| Hessian (`t_hessian`) | 96 | 0 | 0 |

The final full VSC run took 373.60 seconds and emitted no warning lines.
No warning lines or exceptions occurred in any selected final suite. Logs and
counts are stored in the corresponding `full_*` directories,
`physical_gate_final/`, and `handoff_verified/`; the latter is the final focused
rerun with forced generator reordering. Complete focused numerical results are
in each gate's `evidence/` MAT/JSON files.

MATLAB Code Analyzer reports zero findings in all nine changed production files
and the new handoff test. The full VSC test retains its same 12 pre-existing
findings, with no new messages. `code_analysis.json` records the before/after
comparison. A scalar-comparison performance hint was fixed equivalently, then
the 53-check handoff gate was rerun; no policy or numerical behavior changed.
A separate saved structural probe, `nonunit_cache_guard.mat`, verifies that
non-unit PQBRAK metadata is retained, without claiming a low-voltage solve.

The 97 core CPF skips are the existing harness's 88 user-callback checks and
nine legacy angle-wrap failure checks not applicable to MP-Core. No skip was
added by this batch. Full VSC coverage includes converter/generator capability,
limit events, Jacobian/augmented-system finite differences, dispatch and existing
stop/freeze sensitivity scenarios. Those pre-existing explicit freeze scenarios
remain tests of declared behavior; no freeze was added to acceptance runs.

Final focused residuals independently recomputed from exported arrays:

| Result | AC mismatch (pu) |
|---|---:|
| Shunt PF | 1.13986e-9 |
| Shunt CPF | 3.06732e-10 |
| Original GENQ CPF | 1.23884e-9 |
| Reordered/offline export | 5.19065e-11 |
| VM initialization distinct from VG | 8.46431e-9 |
| Genuine crossing CPF / PF | 2.69790e-10 / 1.09941e-9 |
| Genuine crossing, half step | 2.48417e-10 |

All are below the unchanged 1e-8 pu physical gate. The three original fixture
solver mismatches are below 4.60e-12 against configured 1e-8. Converter and DC
balance checks also pass. Shunt PF/CPF return BS=BINIT=6 with Vm5 approximately
0.99531235/0.99519853. GENQ's free point holds VM=VG=1.

### Investigation of intermediate failures

- `handoff_first/` exposed generator cost indexing when an offline original row
  and proxy were present. `handoff_second/` exposed an incorrect assumption in
  the first repair that `order.int` stored a gencost field. Both MATLAB exceptions
  were recorded and fixed in serialization; they were not MCP connection errors.
- `handoff_third/`: two demand checks compared the returned CPF point to exactly
  lambda 1. Its actual endpoint was 0.999999969123392; the largest apparent demand
  error was 4.63e-7 MW, exactly the affine load increment at that lambda. The
  auxiliary demand matched the returned CPF demand exactly. The tests now use
  the reported lambda, retaining the 1e-8 demand tolerance.
- `handoff_fourth/`: the independent raw PF comparison read input `lp.gen` instead
  of solved `lp.ac.gen`. The raw unified PF API retains original top-level inputs;
  its solved AC arrays are under `.ac`. Correcting the accessor produced the
  final 53/53 result, without changing a solver or tolerance.
- The first full-run JSON's `executed` field is 329 because the initial capture
  helper subtracted one after `t_end` had already adjusted the counter. Its
  planned count, pass/fail sum and numbered log establish all 330 checks ran.
  The helper now derives executed count from passed+failed+skipped. Original
  captured evidence was retained rather than silently overwritten.

## Reproduce and review

After `iniciar_proyecto` through MCP, add `tests/` and this output directory to
the MATLAB path. Use the documented test commands in `tests/README.md`. To retain
full-suite counts, call, for example:

```matlab
run_batch2_suite('t_vsc_mtdc', fullfile(batch2_out, 'full_vsc_new_run'));
run_batch2_suite('t_control_handoff_batch2', ...
    fullfile(batch2_out, 'handoff_new_run'), ...
    fullfile(batch2_out, 'handoff_new_run', 'evidence'));
```

Here `batch2_out` is the absolute path of this output directory. Every destination
must be fresh. `batch2.patch` contains the isolated code/test/documentation edits;
`source_manifest.json` supplies source hashes. MP-Test failures and MATLAB
exceptions remain distinct in every captured count file.

## Remaining boundary and ULTC readiness

The reproduced export, solved-state and voltage-handoff blockers are repaired.
Passing these small cases does not certify a controller-policy consolidation.
Before ULTC consolidation, add/confirm its terminal-convention, CW/TAB,
nonconsecutive/remote bus, disabled/saturated, interacting-device ordering,
cycling and physical-versus-numerical-lockout acceptance cases, and declare the
policy that both execution paths must implement.

Remaining limitations are explicit:

- The new load-growth crossing stays above PQBRAK's low-voltage breakpoint.
  Non-unit nominal/effective-load handoff and mixed FACTS/TWODC/VSC projection
  require dedicated physical fixtures; the safe unit-scale cache repair does
  not claim to validate those regimes.
- Expansion preserves each collapsed group's aggregate physics. Unattributed
  equivalent-load changes are placed once at its representative; original
  ideal-connector internal flows and unique per-device allocations are not
  recoverable from a group total alone.
- Exact external PSS/E operating-point agreement, broader benchmark validation,
  and new release/priority/freeze policies were not evaluated or changed.

Use the two focused gates and full electrical/interface suites as the entry
baseline for a future bounded ULTC effort. Do not consolidate ULTC/shunt policy
in this batch. TRANSPA and hydro-corridor work remain deferred.
