# CPF checkpoint replay after stalled turn refinement

Implemented and verified on 2026-09-17 through MATLAB MCP. The previously failing coupled-current-off NOSE run now finds a smooth nose after one rewind and step reduction. Coupled current remains an independent optional toggle, with its existing default enabled. No case parameters were changed.

## Recovery behavior

When the existing suspicious-turn refinement exhausts its local step-halving budget, unified CPF restores an earlier accepted checkpoint before a capability update and retraces with a smaller step cap. This lets the projected-Q algorithm approach the difficult region with a different, finer accepted history; shrinking only the final trial had left a finite projection jump.

The rewind restores network cases and contexts, policy and control state, caches, diagnostics, solution, tangent, accepted trace and events. It removes the discarded trace tail. Replay halves the saved step cap on each attempt, respects ordinary `cpf.step_min`, and caps subsequent adaptive growth. The default budget is three replays per run. Exhaustion still reports an unresolved turn, rather than declaring an unverified nose.

```matlab
options = mpoption(options, 'vsc_mtdc.nose_replay_max', 3); % default; 0 disables
options = mpoption(options, 'vsc_mtdc.coupled_current_limits', 0); % optional
```

The new metadata is `results.cpf.checkpoint_replay`. Local rejected trials retain their replay-attempt number in `results.cpf.turn_detection.history`.

## Studied case

Input: the saved Beerten constant-P/Q study with non-slack dispatch, ULTC, switched shunt, and generator 2's 150 MW capability, from `outputs/ultc_swshunt_g2_150mw_20260916/main_run.mat` (`g150_b`, `g150_t`, `g150_o`). Initial continuation step: 0.10.

| Coupled current | Requested stop | Replays | Final lambda | Final V5 (p.u.) | Outcome |
|---|---|---:|---:|---:|---|
| Off, replay disabled | NOSE | 0 | 1.245549498833 | 0.678749959057 | `turn_localization_failed`; no nose certified |
| Off | NOSE | 1 | 1.245535052415 | 0.678662481908 | Smooth nose; requested endpoint reached |
| On | NOSE | 0 | 1.245668942302 | 0.680546987456 | Limit-induced turn; requested endpoint reached |
| Off | FULL | 1 | 0.603060042973 | 0.235712428616 | Smooth nose recorded, then later converter-capability stop |
| On | FULL | 0 | 0.603073795247 | 0.235713351982 | Limit-induced turn recorded, then later converter-capability stop |

The off-case replay returns to lambda **1.204212007000**, trace index 20, discards 15 subsequent accepted points, and reduces the cap **0.10 → 0.05**. A retry budget of one gives exactly the same recovered NOSE trace as the default budget of three.

Both FULL runs have legacy `success=1` under their configured capability-stop policy, but `requested_endpoint_reached=false`. They continue beyond the first nose and stop at a later converter limit; they do not complete the FULL endpoint. The replay-disabled run has `success=0`. No MATLAB last-warning text was recorded for these six runs.

## Verification

- **35/35** checkpoint-replay regression checks passed: actual rewind, full-state restoration assertions, retained physical-trace prefix, aligned trace lengths, event indices, exact cap halving, retry bounds, invalid-option rejection, NOSE and FULL, and current coupling off/on.
- **17/17 independent physical checks per run**, for all six saved runs, passed. These recompute AC/DC and bridge balances, station phasors, losses, PCC schedules, converter limits, generator capability, load interpolation and discrete-control settlement. The replay-disabled failure's retained accepted trace also passes physical checks; this does not certify its endpoint.
- **330/330** existing `t_vsc_mtdc` regression checks passed.
- Coupled-current-enabled NOSE and FULL lambda, bus, generator, branch, converter, DC-bus and DC-branch traces are **exactly identical** to the preceding standard-integration runs.
- MATLAB Code Analyzer reported only growth, unused-function, scalar-condition and comma-style advisories; no parser errors. Full messages are saved.

The first development regression exposed that FULL retained the tiny event-refinement step after recovering a *smooth* nose. Step restoration now handles both smooth and limit-induced turns while respecting the replay cap. That earlier 34/35 result is preserved in `regression/`; the corrected 35/35 run is in `final/`.

## Scope and limits

This is recovery for exhausted suspicious-turn refinement in unified CPF. It does not change network equations, capability margins, ratings, control setpoints, or the existing smooth-nose acceptance criteria. Other corrector failures and a failed smooth-nose locator retain their existing handling.

The recovered nose belongs to the replayed projected-Q control history. It is not proof that the original unresolved jump was itself a continuous nose, or that projected-Q results are independent of step size. Starting the entire run at step 0.05 previously gave lambda 1.245485143871; retaining the earlier 0.10 history and replaying only the affected portion gives 1.245535052415. Exact discontinuous-event ordering remains a separate possible improvement.

## Code and evidence

- [Recovery and restoration](../../matpower/lib/runcpf_vsc_mtdc.m): option validation near line 156; checkpoint initialization 427; recovery 935; checkpoint capture 1032; FULL step restoration 1096; metadata 1139; helpers 1143; default 4633.
- [Option registry](../../matpower/lib/mpoption.m): help near line 198, default near line 1663.
- [New regression](../../tests/t_cpf_checkpoint_replay.m).
- [Algorithm documentation](../../docs/CPF_LIMIT_CONTINUATION.md).
- [Final regression evidence](final/replay_tests.json), [existing suite log](final/t_vsc_mtdc.log), [unchanged coupled traces](final/coupled_trace_comparison.json).
- [Recovered NOSE audit](final/off_nose_audit.json), [recovered FULL audit](final/off_full_audit.json). Each `final/*.mat` retains inputs, options, result, success flag, timing and warning fields; the corresponding CSV contains the accepted physical trace.
- `before/` preserves the prior source files. `changes.patch`, `after/` and `source_manifest.json` preserve the exact implementation changes and source hashes. Historical scientific outputs were retained.

To reproduce the feature test, initialize with `iniciar_proyecto`, add `tests` to the path, load the fixture above, then invoke `t_cpf_checkpoint_replay(g150_b,g150_t,g150_o,new_output_directory)`. Use a fresh directory; the test refuses to overwrite existing MAT runs.
