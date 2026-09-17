from pathlib import Path
import hashlib,json
p=Path(__file__).resolve().parent; root=p.parent.parent
hashes=json.loads((root/'outputs/cpf_solution_experiments_20260917/production_hashes_before.json').read_text())
changed=[name for name,h in hashes.items() if hashlib.sha256((root/name).read_bytes()).hexdigest()!=h]
(p/'integrity.json').write_text(json.dumps({'files_checked':len(hashes),'changed':changed},indent=2))
rows=json.loads((p/'comparison.json').read_text())
table='\n'.join(f"| {r['variant']} | {r['step']} | {r['lambda']:.12f} | {r['termination']['cause']} | {len(r['history'])} |" for r in rows)
report=r'''# Why the voltage rises, and how to catch a skipped turn

Study: Beerten constant-P/Q, non-slack dispatch, ULTC and switched shunt, G2 active capability 150 MW. Diagnostic date: 2026-09-17. All new code and outputs are isolated in this directory.

## Finding

**The upward segment in the coupled-current trace comes from reversing continuation direction after G2 reaches its reactive limit.** Newton convergence and small balance residuals do not establish that the intended direction along the solution branch was preserved.

The event is a **local loading maximum caused by a control-limit transition**. The one-sided loading tangents change sign without either fixed-mode Jacobian becoming singular at that point. This differs from a smooth saddle-node nose, where the tangent loading component approaches zero continuously. These static calculations do not certify a dynamical bifurcation or dynamic stability.

![Trace and rollback diagnosis](nose_skip_diagnosis.png)

Markers are saved accepted states from the original coupled-current run (initial step 0.1). The star is an independently solved event; it was not an accepted point in that original trace. Arrows illustrate local tangents, not additional solved trajectories. The horizontal axis is bus 5 demand relative to the localized event; P5 = 60 + 240 lambda MW.

## Same physical state, two equation sets

I solved the incoming PV equations together with G2's exact Q-limit event. Results from initial continuation steps 0.1 and 0.05 agree to approximately 4e-13 in lambda:

| Quantity | Localized event |
|---|---:|
| Loading parameter | 1.245668943510 |
| Bus 5 demand | 358.960546442 MW |
| Bus 5 voltage | 0.680547007711 p.u. |
| G2 terminal / bus 6 voltage | 1.000000000000 p.u. |
| G2 reactive output | 112.500000000 MVAr |
| Maximum PV/PQ equation residual, step-0.1 seed | 2.51e-12 |
| Maximum PV/PQ equation residual, step-0.05 seed | 1.45e-12 |

The event solve uses the full coupled-current network and converter equations. At the event, I replaced G2's voltage constraint with its reactive-power constraint at the **same physical state**, then computed both nullspace tangents. No finite Q or lambda jump was introduced.

For equations F(x,lambda)=0 and continuation coordinate s:

$$J\,t_x+F_\lambda t_\lambda=0,\qquad t_x=\frac{dx}{ds},\quad t_\lambda=\frac{d\lambda}{ds}.$$

The outgoing tangent is oriented to agree with the incoming tangent after mapping common variables by identity. A newly freed voltage variable is added with zero incoming component. This local comparison uses the solver's state coordinates; a general implementation should define explicit variable scaling.

| Direction at the same event | d(lambda)/ds | d(V5)/ds |
|---|---:|---:|
| Incoming PV branch | +0.165736 | -0.345454 |
| Outgoing PQ branch, direction preserved | -0.021789 | -0.365364 |
| Outgoing PQ branch, forced positive lambda | +0.021789 | +0.365364 |

The mapped tangent dot product is +0.948702 for the direction-preserving choice. The incoming and outgoing fixed-mode Jacobians both have smallest singular values approximately 0.0038 in their implemented coordinates; they are nonsingular here. Singular-value magnitudes depend on scaling and are not stability margins.

**Physical interpretation:** G2 can no longer supply additional reactive power while holding its voltage. The forward equilibrium path locally turns toward lower loading and lower V5. Forcing loading to increase selects the opposite direction on the Q-limited branch, and V5 consequently rises.

The original coupled-current run eventually reports a smooth nose at lambda = 1.245901716890, V5 = 0.688338037 p.u. That is a different point, reached after the direction reversal. Its bus 5 demand exceeds the first limit-induced maximum by only about 0.055866 MW. The small loading difference masks a visible voltage difference. It should not be used as the first forward-path loading maximum for a NOSE-only study.

## Verified code cause

The production tangent-reset block seeds only the loading component with positive `direction` after an active-set change: [runcpf_vsc_mtdc.m](../../matpower/lib/runcpf_vsc_mtdc.m#L827), specifically line 830. The isolated A implementation retains this behavior.

The next event test at [line 837](../../matpower/lib/runcpf_vsc_mtdc.m#L837) requires `~active_set_changed`. Thus a turn occurring during a control transition is excluded. The smooth-nose predicate at [line 3677](../../matpower/lib/runcpf_vsc_mtdc.m#L3677) checks the loading tangent changing from positive to nonpositive or nearly zero.

These are two distinct defects: forced orientation can hide a turn, and the active-set exclusion can skip a turn even when orientation is preserved.

## Isolated rollback experiment

The new guard checks control-changing trials for either a loading-tangent sign reversal or a negative mapped tangent dot product. It checkpoints and restores network contexts, case data, transfer policy, discrete controls, event records and diagnostic/cache state before retrying at half the step. Snapshot restoration is asserted. It does not label a guard stop as successful NOSE detection.

| Variant | Initial step | Last accepted lambda | Termination | Guard alarms |
|---|---:|---:|---|---:|
TABLE

All eight accepted traces pass the existing 17 independent physical checks. No MATLAB numerical warnings were returned. Baseline outcomes are unchanged: the half-step baseline still stops at a generator-capability problem and does not reach its requested NOSE endpoint. Its legacy success flag is true under its configured-stop policy; that is not endpoint success.

The six modified-variant runs detect suspicious control-transition trials. Coupled-current detects reversed orientation; augmented/combined detect a change to negative loading tangent. In coupled and combined, the remaining incoming trial intervals are about 3.24e-5 in lambda: the original minimum continuation step (1e-4) prevents reaching the 1e-5 event tolerance by halving alone.

**Prototype limitation:** these intervals are diagnostic trial bounds, not universally certified event brackets. In augmented-only runs, reactive-limit projection can modify the settled state during refinement; some accepted states are already PQ and subsequent alarms involve further control updates. A small lambda interval alone does not prove the first G2 limit was located. All six guard stops therefore have `success=false`, `nose_detected=false`, and `requested_endpoint_reached=false`. The exact event solve above independently resolves the coupled-current case only; it is not a finished generic event locator.

## Recommended complete NOSE policy

1. **Preserve direction across control changes.** Transport the tangent by physical variable identity, use consistent scaling, and orient the new nullspace tangent to agree with the transported incoming direction. Do not reset to positive lambda. An abrupt rotation should trigger refinement and diagnosis, rather than automatically prove a bifurcation.
2. **Evaluate events before accepting a trial.** Monitor both the smooth-fold function t_lambda and every active control margin, for example Qmax(Pg)-Qg and Imax-|Ic|. Keep the pre-control corrected state: post-limit clipping can erase the sign change that establishes a bracket.
3. **Rollback all trial changes.** Restore controls, device modes, cases, tangents, policies, caches and event records. Retry with a shorter pseudo-arclength step. Retain diagnostic evidence of rejected trials without treating them as accepted operating points.
4. **Locate the actual event.** Use a bracketed event search on the incoming branch, or solve the network equations augmented with the event equation. For this case:

$$F_{\mathrm{PV}}(x,\lambda)=0,\qquad Q_{g2}(x)-112.5\ \mathrm{MVAr}=0.$$

   The diagnostic implements this augmented solve with analytic network and Q derivatives. In a general capability curve, include the dependence of Qmax on Pg. An event-localization tolerance and iteration budget should be separate from the ordinary continuation minimum step. If the event cannot be localized, return an unresolved-event termination rather than success.
5. **Classify the localized maximum.** Evaluate both one-sided tangents at the event. A smooth fold has t_lambda=0 within one equation set. A control-limit turn has t_lambda before >0 and correctly oriented t_lambda after <0. Record distinct `SMOOTH_NOSE` and `LIMIT_INDUCED_TURN` event kinds. For an option meaning “stop at the first maximum loading along this operating path”, either kind should satisfy the endpoint. A physical limit-induced turn cannot be removed by reducing the step.
6. **Keep FULL tracing available.** Record the maximum and continue with the oriented tangent when FULL is requested. For discrete taps/shunts, check admissible pre/post-control states and event ordering; do not interpret every switched jump as a smooth fold. Near simultaneous events, localize the earliest admissible event and reassess the remaining margins.

MATPOWER's documented event framework already uses event-function sign changes, bracketing and refinement, with callbacks for limit changes: [official Event Detection and Location documentation](https://matpower.app/manual/matpower/EventDetectionandLocation.html). The proposed extension applies that principle to this custom solver's control-changing steps and distinguishes smooth and limit-induced maxima.

No finite endpoint-only sign test guarantees detection of two folds inside one large step. Additional safeguards should subdivide steps when tangent rotation, predictor-corrector discrepancy, control-margin proximity or nonlinear corrections grow unexpectedly. Voltage rise alone is not a valid nose detector: controls can legitimately increase voltage.

## Reproduction and scope

- [run_guard.m](run_guard.m): all four variants at both step sizes using MATLAB MCP; historical solver options preserved apart from explicit NOSE mode and isolated guard.
- [build_guard.py](build_guard.py), `ng0` through `ng3` solver copies and `.diff` files: bounded experimental changes.
- [localize_g2_transition.m](localize_g2_transition.m): independent same-state PV/PQ event solve and tangents.
- [localized_event_100.json](localized_event_100.json), [localized_event_050.json](localized_event_050.json): numerical evidence; MAT files retain full contexts and states.
- [comparison.json](comparison.json): termination flags and every guard trial; individual audit JSONs and trace CSVs preserve independent checks.
- [plot_diagnosis.m](plot_diagnosis.m), [vector figure](nose_skip_diagnosis.pdf): reproducible scientific plot. PNG was visually inspected for labels and layout.
- [integrity.json](integrity.json): production/study hashes compared with the pre-experiment manifest. Historical outputs were read, not overwritten.

This is a validated diagnosis and an isolated rollback prototype, not a production implementation of the complete policy above.
'''
(p/'REPORT.md').write_text(report.replace('TABLE',table),encoding='utf-8')
print(json.dumps({'files_checked':len(hashes),'changed':changed,'report':str(p/'REPORT.md')}))
