# Combined A+B result: capability transition direction improves; tap transitions expose remaining reset

Both step-size runs attempted the original FULL task with the original 200-step budget. Neither completed it. Both returned `success=true` only under `configured_stop_policy`, cause `step_limit`, 201 accepted points. Equipment and electrical balance checks pass, but the continuation path repeatedly reverses after tap changes. Those loops prevent interpreting the final point or sampled maximum as a validated FULL trajectory or physical loadability limit.

| Quantity | Step 0.1 | Step 0.05 |
|---|---:|---:|
| Sampled maximum lambda | 1.245882710845659 | 1.245869716269402 |
| Index of sampled maximum | 197 | 46 |
| Last lambda | 1.222760029290885 | 1.245536417196048 |
| Decreasing-lambda steps | 90 | 79 |
| FULL endpoint reached | false | false |
| Old audit checks passed | 15/16 | 15/16 |

The lone failed old audit is `no_accepted_tap_reversal`; reversal alone is not inherently a physical error on a descending branch. Here the more substantive issue is systematic **numerical path-direction reversal after each tap-only active-set change**, described below. Parent independent audits cover full physical equations and lambda consistency.

## What the combined experiment successfully changes

VSC 2 follows its exact current boundary instead of repeatedly clipping Q. The converter and generator capability transitions use the B incoming-plane augmented corrector. The 0.1 generator Q transition changes state dimension 26→27, at candidate lambda 1.252025603604405, corrected lambda 1.243489357839621, residual 2.49e-12 and hyperplane residual -1.88e-16. The 0.05 counterpart changes 1.251326678546819→1.243902455755944, residual 2.72e-12.

Unlike isolated A, the combined trace initially **preserves falling bus-5 voltage through G2's PV→PQ transition**. In the 0.1 run, index 21 has V5=0.699242187248967 and index 22 has V5=0.663146836165660. Thus the current-limit metadata is present and the B tangent transport is actually being used. This is not a failed composition of the two equation changes.

## Remaining tap-only reset, with actual points

| Accepted index, step 0.1 | Lambda | V5 | Tap | Interpretation |
|---|---:|---:|---:|---|
| 21 | 1.23492725723412 | 0.699242187248967 | 0.9666666667 | Before G2 Q transition |
| 22 | 1.24348935783962 | 0.663146836165660 | 0.9666666667 | G2 Q-limited; incoming voltage direction preserved |
| 23 | 1.23165037097100 | 0.626427476638166 | 0.9444444444 | ULTC tap moves |
| 24 | 1.243516 (rounded) | 0.66298 (rounded) | 0.9444444444 | Voltage direction reverses immediately after tap change |
| 27 | 1.21859680170105 | 0.770836909261888 | 0.9444444444 | PCC voltage is now above original VSC voltage request |
| 28 | 1.19040645069814 | 0.804726362666943 | 0.9666666667 | ULTC reverses tap |
| 29 | 1.218598 (rounded) | 0.77075 (rounded) | 0.9666666667 | Voltage direction reverses again |

The pattern repeats approximately every 10 accepted points in the 0.1 run and 16 points in the 0.05 run. B transports the incoming direction for converter/generator limit transitions via `b17_carried`. A **tap-only** active-set transition does not populate that state, and the outgoing-tangent block still falls back to the inherited positive-lambda natural-parameterization seed. The next step retraces the local electrical branch in the opposite direction. This explains the repeating CPF trace; it is not evidence of a physical time-domain control oscillation.

The VSC current branch also still lacks release logic. Its original PCC voltage request is exceeded first at index 27 in the 0.1 run and index 50 in the 0.05 run. Beyond that point the held current mode requires a recovery test before it can be called the original voltage-control policy. This is independent of whether current and voltage rating inequalities pass.

## Bounded conclusion

The two proposals are complementary, but combining these bounded prototypes is insufficient for a valid complete CPF with discrete controls. Incoming-direction mapping must also cover the ULTC/shunt active-set stages, and original converter voltage-control recovery must be evaluated. Exact event localization is still needed: the augmented transition corrector solves on a plane through an overshot candidate, so its corrected lambda is not an exactly located first binding event. No larger step budget was used to prolong the repeating path. No production code or case parameter was changed.
