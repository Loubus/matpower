# Experiment A — current-limit equality with unchanged transition continuation

## Main finding

Replacing VSC 2's clipped Q order with a simultaneous physical current equation removes the previous converter re-correction failure in the two attempted CPF runs. Both now reach the configured 200-step budget, with 201 accepted points, rather than the old VSC/generator re-correction stop. **Neither completes FULL.** A significant inherited branch-orientation issue and the prototype's missing limit-release logic prevent treating the entire trace as the original requested control policy.

| Result | Step 0.1 | Step 0.05 |
|---|---:|---:|
| Accepted points | 201 | 201 |
| Sampled maximum lambda | 1.245901555991825 | 1.245901455436215 |
| Index of sampled maximum | 38 | 57 |
| Last lambda | 1.212555974416838 | 1.220082858860957 |
| Decreasing-lambda steps | 163 | 144 |
| Raw stop cause | step_limit | step_limit |
| Raw success scope | configured_stop_policy | configured_stop_policy |
| FULL endpoint reached | false | false |
| Raw nose flag | false | false |
| Maximum current/rating | 1.000000000000244 | 1.000000000000253 |
| Maximum internal voltage | 1.076430129150965 | 1.071258230833700 |

The unchanged FULL-mode nose-recording limitation remains. These are sampled loading maxima, not localized physical limits. Near-identical sampled maxima do not by themselves establish control-policy correctness.

## Numerical equation checks

All 16 checks inherited from the prior study pass in each run: original AC balances, DC balances, bridge balances, station map consistency, loss formula, constant PCC P/Q for converters 1 and 3, DC voltage preservation, current/internal-voltage limits, ULTC/shunt bounds/grids and existing control acceptance. The two monotonic-control checks are descriptive checks from the old audit, not a general physical requirement for FULL.

An independent central-difference check of the new analytic current row at three step sizes gives relative infinity errors of approximately 7.1e-12, 7.34e-11 and 8.02e-10. See `jacobian_validation.json` for exact values and component derivatives. The converter current equation is propagated into both fixed-lambda PF and the ordinary CPF residual/Jacobian/tangent. VSC 2's DC voltage stays at 1 p.u.; its P remains a DC-balance outcome.

## Important new diagnosis: inherited tangent orientation

The production algorithm resets its tangent seed after an active-set change to a vector containing only a positive lambda component, using natural parameterization. Experiment A deliberately retains that procedure. In the 0.1 run G2 changes PV to PQ at accepted index 26, lambda 1.24573253556225, V5 0.681697890151632, Qg2 112.5 MVAr. Following the transition, V5 **increases**: it reaches 0.688542488025844 at the sampled maximum and 0.779199745228036 at the final point. This is not the simple high-voltage-to-low-voltage progression one might infer from the scalar lambda trace.

The 0.05 run changes G2 at index 46, lambda 1.24573783978136, V5 0.681802985152936, with the same qualitative reversal. The reset is at production `runcpf_vsc_mtdc.m:827`–832 and remains in `exa_cpf.m`. This motivates preserving the incoming direction through the equation change, as in Experiment B, rather than interpreting every positive-to-negative lambda pattern as the intended physical continuation.

## Missing release is materially relevant

The original VSC 2 voltage request is 1 p.u. The current-limited prototype intentionally has no recovery heuristic. In the 0.1 trace the PCC voltage first rises above that request at index 133 (lambda 1.23446345201069; PCC voltage 1.00003232768903). In the 0.05 trace this happens at index 153 (lambda 1.23441930910692; PCC voltage 1.00008151501978). Maintaining positive limiting reactive support beyond those crossings requires an explicit control-policy justification or a recovery test; passing equipment inequalities is insufficient.

Consequently the accepted electrical points after those indices must not be presented as validated continuation of the original voltage-control policy. No larger point-budget run was executed on this questionable held-mode path. `exa_run_extended.m` was prepared before this issue was identified but intentionally not used.

## What changed and what did not

See `design.md` and `experiment.diff` for equations and exact edits. The only new algorithmic model is physical current-row replacement for a pure current violation with active-power priority, including an explicit second-limit guard. The 0.1% Q clipping is removed for this branch because Q is solved on the exact current equality; ratings are unchanged. All case parameters, limits, control requests and base solver settings are the saved study's values. Fixed-lambda limit settlement remains unchanged in A; augmented transition continuation is only in the separately saved combined experiment.

The first run attempt hit an implementation error resolving an empty optional Smax override. It was corrected to use the capability wrapper's resolved `info.Smax` before either successful result was saved. This is documented in `execution_notes.md`; it was not a numerical or MCP failure. No numerical warnings were reported for the saved runs.

## Interpretation

The simultaneous equation is promising and numerically well supported for this case, but A alone exposes rather than solves continuation/control coordination problems. Its sampled maximum is approximately 0.000741 above the old 0.1 result (about 0.06%), far smaller than the improvement in numerical ability to trace past the previous failure. A combined A+B run is being evaluated separately to test whether preserving incoming continuation direction avoids the reversal while retaining the exact converter-current boundary. Neither result certifies dynamic stability or global maximum loading.
