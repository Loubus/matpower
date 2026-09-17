# AB2 results: the tap-related trace loops are removed

Transporting the accepted tangent across **all** active-set changes removes the repeating tap-related path reversals found in A+B. Both step sizes now follow a consistently falling-voltage descending branch, reaching lambda about 0.603 before the VSC capability stage stops. **Neither FULL endpoint is reached.** This is a substantial numerical progression past the old near-nose failure, not a certification that all capability transitions are solved generally.

| Quantity | Step 0.1 | Step 0.05 |
|---|---:|---:|
| Accepted points | 42 | 79 |
| Sampled maximum lambda | 1.243489357844008 | 1.243902455752465 |
| Maximum index | 22 | 43 |
| Last accepted lambda | 0.603079754115526 | 0.603058660511208 |
| Last V5 | 0.235715666672517 | 0.235707473014383 |
| Last VSC 2 PCC voltage | 0.783631435343900 | 0.783628655143753 |
| Last VSC 2 Q, MVAr | 116.002541204273 | 116.002128372777 |
| Last VSC 2 current/rating | 0.999999999999995 | 1.000000000000001 |
| Last VSC 3 current/rating | 0.999943125218628 | 0.999977885220159 |
| Maximum current/rating in trace | 1.000000000003792 | 1.000000000002326 |
| Maximum internal voltage in trace | 1.056382397163193 | 1.058067173482588 |
| Raw stop cause | vsc_capability_limit | vsc_capability_limit |
| FULL endpoint reached | false | false |
| MATLAB warning | empty | empty |

Both return success 1 with scope `configured_stop_policy`. The maximum lambda is still a sampled accepted value, and the augmented capability transition is not an exactly localized first limit event. The approximately 0.000413 difference between step-size maxima is evidence to retain that qualification.

## Tangent and control evidence

Each run has five accepted tap moves, all downward, reaching the declared minimum 0.9. The outgoing orientation logs show positive dot products with the transported incoming direction; the minimum values are 0.6079088104 and 0.6085456383. At the first descending tap change in the 0.1 run, incoming lambda tangent -0.06963884 remains negative at -0.16550400 after the move; at later tap moves it remains negative. Thus the algorithm no longer forces a positive lambda tangent at a tap-only transition.

The last V7 is about 0.79113 p.u. with the tap at its 0.9 lower bound, and the shunt is at its 15 MVAr nominal upper bound. The old audit's `ULTC_settled` condition only checks a voltage band and therefore fails. It must be evaluated under the study's explicit saturation-at-bound policy; this band-only failure alone does not invalidate the accepted controlled point. The old audit's remaining 15 checks pass, including current, voltage, PCC schedules, converter losses and all electrical balances. Parent independent audits supply the correct bound-aware control checks.

The maximum VSC 2 PCC voltage while its current limit is active is 0.9912026729 and 0.9919215960 respectively, below the original 1 p.u. voltage request. The earlier experiment's missing current-mode release is therefore **not triggered by a return above that request on these accepted AB2 trajectories**. No universal recovery correctness is claimed.

## What stops the run now

Only VSC 2 activates the new coupled-current equation. At the endpoint its current remains exactly at rating while its Q follows the falling PCC voltage. Converter 3 approaches its own current boundary on the very low-voltage branch; its final internal voltage is approximately 0.25241 p.u. and its current ratio is nearly one. Converter 1 remains well below rating (approximately 0.62).

The prototype only activates a pure-current equation under the existing active-power-preserving policy when the original P can be retained. Other converter saturation policies still use the existing setpoint projection, now followed by the B augmented corrector. Thus it is not a general simultaneous boundary formulation for every converter/control priority.

The final rejected sequence in the 0.1 run is recorded in `transitions`: a candidate at lambda 0.603018061451217 is re-corrected to 0.592215132429393, then another saturation correction reaches 0.450668990022050, and a subsequent attempt jumps to -1.001196731870854 and fails with residual 1.41421356e6. The corresponding final 0.05 sequence is 0.602996971954483→0.591841212965631→0.446827103527060→-1.017008877123546. The large residual is the existing invalid-voltage-state sentinel reached by Newton; the negative rejected lambda is **not accepted or plotted as part of the CPF trajectory**.

These are failed numerical attempts under remaining outer projection logic. They are not proof that lambda 0.603 is a physical end of the mathematical branch. The observed sequence also warrants preserving the incoming direction consistently through repeated projections inside the same transition, rather than recomputing it from large correction jumps.

## Bounded recommendation from the experiment

The coupled VSC current equation is supported by the actual full-CPF evidence, and direction transport must cover discrete controls as well as capability modes. The remaining work is policy-aware equation replacement for the next limiting converter, exact event localization, robust repeated-transition direction handling and recovery logic. The four experimental variants and failed attempts are all preserved; no production change is proposed as already validated.
