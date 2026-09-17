# Locating the projected-Q turn with coupling disabled

## Verified explanation

A nearby smooth nose exists. The original failed step-0.10 run reaches the converter-current boundary just before that smooth nose, then the projection's finite inward Q margin causes a discontinuous state adjustment. The current continuous-turn locator requires that adjustment to shrink with the predictor step; it cannot do so.

The final rejected trial has predictor step approximately 1.46e-12 and incoming state interval 5.83e-13, but the outgoing state interval remains 9.68e-4 in solver coordinates. The orientation remains positive and the loading tangent changes sign. Thus the obstacle is a finite projection jump, not insufficient predictor resolution or reversed tangent orientation.

## Independently solved points, initial step 0.10

All rows use the full network/station equations. The incoming branch retains the Q order immediately before projection. Its converter-current boundary was solved with an additional I2/Imax=1 equation. Its smooth fold was found by bracketed continuation and a loading-tangent zero.

| Point | Lambda | V5 p.u. | I2/Imax | Loading tangent |
|---|---:|---:|---:|---:|
| Incoming current boundary | 1.245549498746 | 0.678749959284 | 1.000000000000 | +0.0002278404 |
| Smooth fold with that Q held | 1.245549526703 | 0.678665532128 | 1.000037463598 | 1.53e-11 |
| Settled projected outgoing trial | 1.245401000339 | 0.678593756638 | 0.999178031356 | -0.0001092740 |

The smooth fold is only 2.80e-8 higher in lambda, but exceeds the current bound by 0.003746%. Its existence is not a reason to certify it as a constraint-feasible maximum. The current boundary precedes it on the forward branch.

Q2 changes from 144.098537387 to 143.954438835 MVAr, a 0.144098552 MVAr decrease. The relative change is 0.0010000001: the configured **0.1% inward projection margin**. The outgoing lambda decreases by 0.0001484984. Network residuals of all three independently evaluated points are below 3.4e-12.

## An immediate tested alternative: initial step 0.05

With coupling still disabled, the existing production algorithm, copied only to add checkpoint instrumentation, successfully locates a smooth NOSE:

- Returned lambda: **1.245485143871**.
- Returned V5: **0.678651851990 p.u.**
- `success=true`, `requested_endpoint_reached=true`, `smooth_nose_detected=true`.
- All **17 independent physical checks pass** on the accepted trace.

An independent refinement gives lambda=1.245485143870, V5=0.678651970792 and I2/Imax=0.999657117065. On this run's last fixed-Q branch, the current boundary lies **after** the smooth fold on the descending branch, so the fold is feasible and should be located first. The field named `incoming_boundary` in `diagnosis_050.json` refers to the incoming fixed-Q equation set; it is not the earliest event along that branch.

The event order differs because projected-Q values depend on the sequence of prior projection updates. Initial-step sensitivity is therefore part of this formulation's behavior. Finding a feasible smooth nose for step 0.05 does not establish step-independent convergence of the projected-control loading margin.

## Recommended detector changes

1. **Find the earliest event on the incoming branch before updating controls.** Compare a bracketed loading-tangent zero against bracketed generator/converter capability margins. If a feasible smooth fold comes first, return it as `SMOOTH_NOSE`. Applying the projection first can hide the fold.
2. **Handle finite control jumps explicitly.** Locate the triggering capability boundary, retain the pre-jump state, then apply the declared projection once and solve/check the outgoing branch. If the projected forward continuation turns toward lower loading, record a separate `PROJECTED_CONTROL_TURN` (proposed event name). A NOSE policy defined as the first local maximum along the declared operating path can stop at its incoming boundary. Report both pre/post lambda, Q, voltages, residuals and one-sided tangents. Do not call a finite jump a smooth saddle-node or infer dynamic stability from it.
3. **Use separate localization tests.** For a smooth fold, require converged network equations, a tangent-zero/bracket tolerance and constraint feasibility. For a finite jump, require an accurately located trigger and valid one-sided corrected states; do not require the prescribed finite jump itself to vanish. Keep rollback and explicit failure for unresolved event order or invalid states.

Increasing the retry budget cannot fix the step-0.10 state-gap plateau. Broadly relaxing the state tolerance would hide the distinction. Removing or shrinking the 0.1% inward Q margin could make the update more continuous, but changes the declared numerical projection policy and warrants a separate controlled comparison. Coupled current remains the optional, simultaneously enforced boundary formulation.

## Code and evidence

- `matpower/lib/runcpf_vsc_mtdc.m`: `turn_alarm` / `localized` around lines 883–895; `apply_vsc_capability_saturation_margin` around line 1787; smooth-nose test runs after control settlement.
- [diagnosis.json](diagnosis.json): independent current-boundary, fixed-Q fold and outgoing jump for step 0.10.
- [diagnosis_050.json](diagnosis_050.json): same diagnostic on the earlier rejected step-0.05 trial; the final step-0.05 run successfully reaches a smooth nose.
- [off_step_050_audit.json](off_step_050_audit.json): physical checks on the successful step-0.05 trace.
- [diagnose_projected_turn.m](diagnose_projected_turn.m): reproducible independent calculations. Its initial fixed fold bracket was insufficient for the step-0.05 branch; bounded bracket expansion was added, without changing network equations or solver policy.
- `pj_cpf.m` / `pj_psse.m`: isolated production copies with checkpoint capture only. Instrumented MAT files retain complete contexts and trial states.

This investigation changed no production code or case settings. The smaller step was an explicit sensitivity run saved separately. MATLAB MCP was initialized with `iniciar_proyecto` and used for all calculations. Historical outputs were preserved.
