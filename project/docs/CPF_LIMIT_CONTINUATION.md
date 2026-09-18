# Coupled current limits and continuation through control transitions

The standard **unified VSC-MTDC CPF** now combines converter current-limit equations, augmented capability-transition correction, transported tangents and loading-turn detection. Sequential PF/CPF and AC-only CPF are not migrated to this formulation. No equipment ratings, case parameters or historical outputs are changed.

## Converter current constraint

Coupled-current activation is optional in unified CPF. Its default is enabled,
preserving the integrated algorithm's behavior. Set it with either syntax:

```matlab
options = mpoption(options, 'vsc_mtdc.coupled_current_limits', 0); % off
options.vsc_mtdc.coupled_current_limits = 1;                      % on (default)
```

With the toggle off, capability enforcement uses the existing projected-Q
treatment, including its configured saturation margin. Augmented correction,
tangent transport and nose detection stay enabled. The resolved setting is
reported in `results.cpf.coupled_current_limits`. This switch controls CPF
activation, not the lower-level PF interpretation of a saved active constraint.
An off-setting CPF rejects an input with a positive `vsc_current_limit` entry;
compare formulations from the original unsaturated case rather than silently
discarding its saved active-set state. Missing or empty options use the default.

When the existing capability policy chooses **preserve active power** and identifies converter current as the binding constraint without changing active power, the released AC-Q equation becomes

\[
f_I=\frac{I_c^2}{I_{\max}^2}-1=0,\qquad
I_c=\frac{\sqrt{P_c^2+Q_c^2}}{S_{\rm base}|U_c|}.
\]

Here Pc and Qc are internal converter powers in MW/MVAr; Uc is the internal converter voltage in p.u. The transformer, filter and reactor remain in the network equations. PAC_SET/QAC_SET remain PCC orders. The released Q order remains stored for provenance but is no longer an enforced Q equation while the current constraint is active. DC-voltage control and the AC/DC bridge balance remain enforced.

The Newton Jacobian includes the analytic derivative of this current equation with respect to all relevant network states. It is used consistently by the corrector and tangent calculation. Other capability policies (including radial projection and internal-voltage saturation) retain their existing projection behavior. A second binding ceiling on an already current-limited converter is not silently ignored: the active-set settlement rejects it under the existing failure/recovery policy. This is not an implementation of simultaneous independent current and internal-voltage equalities.

`mpc.vsc_current_limit` is solver active-set state: one finite, nonnegative number per converter, in system-base current p.u.; zero means inactive. An active entry requires an online converter in Q/PQ mode. `savecase` preserves it. Sequential PF rejects active entries rather than silently restoring the stored Q order. Since 2026-09-18, unified CPF can restore the original voltage control under the acceptance rule below.

## Return to voltage control — corrected 2026-09-18

`vsc_mtdc.current_limit_release=1` enables **local, continuous release**, not a search for any feasible voltage-controlled equilibrium. `vsc_current_restore_mode` records the original V/PV mode on current-limit activation, is validated, and survives save/load. Old saved current-limited cases without this provenance remain constrained; no original mode is guessed.

A release is considered only when the current-limited branch itself reaches the voltage target:

\[
I_c=I_{\max},\qquad V_{\rm PCC}=V_{\rm set}.
\]

The voltage-error event is bracketed between consecutive points on the same active set and located with pseudo-arclength correction. The old and new modes must share the localized equilibrium: a zero-length augmented correction must change the scaled physical state by at most `max(1e-7,10*PF_tolerance)`. The voltage contact tolerance is `max(1e-9,PF_tolerance)` p.u. Configured physical controls must be settled at the contact, without a simultaneous finite change to their settings, and enabled generator/converter capability checks must pass.

The outgoing tangent is oriented by its dot product with the transported incoming tangent. **Its lambda component is never forced to have a chosen sign.** Two small forward corrections (arclength 1e-4 and 5e-5) must stay near their predictors and enter the feasible current interior. These probes do not advance the accepted trace. A clearly outward direction keeps the current constraint. Failed, ambiguous or nonlocal transitions are rolled back and retried with a smaller step; exhausted refinement returns `current_release_unresolved`, `success=0`, and `requested_endpoint_reached=false`, preserving the last accepted point.

Multiple converter contacts are examined in arclength order. The first admissible local release is accepted at its contact, rather than at the original overshooting candidate. Ordinary loading-turn checks remain enabled across this transition. A release event cannot itself falsely complete a pending FULL lambda-zero step.

`VSC_CURRENT_RELEASE` now has `kind='localized_branch_intersection'` and records the contact error, scaled state gap/tolerance, current ratio at contact, both forward-probe ratios, tangent orientation and lambda components. A finite voltage jump to a distant feasible equilibrium is rejected. The earlier `fixed_lambda_control_transition` behavior was an incorrect branch-tracing policy and is superseded.

The old `current_release_margin` option remains readable for compatibility but is **ignored** by this local method. At the intersection the current is at its limit; requiring 0.1% headroom at that very point would prevent a continuous switch. Inward feasibility is tested by the forward probes instead. `results.cpf.current_release_policy` identifies `localized_branch_intersection`; the legacy option is explicitly reported as `current_release_margin_legacy_ignored`.

Incremental policy interpolation carries current constraints and mode provenance, allows returning to the original AC mode, and prevents old predictor contexts from inheriting later constraints. Release does not restart a previously saturated active-power dispatch schedule. Physical current-limit enforcement and generator capability curves are unchanged.

## Solved generator capability contact (2026-09-18)

Generator localization uses signed physical headrooms (P minimum, P maximum, upper Q and lower Q) from the unchanged generic curve, instead of zero-inside projection distance. For a crossed boundary it brackets between the previous accepted lambda and the corrected candidate, solves the incoming equation set at trial lambdas, and locates zero headroom to 1e-8 MW/MVAr. The earliest solved contact along the step is selected. The new active set is corrected at that same lambda and the contact appears in the accepted trace. P-only contact retains PV control; Q contact releases voltage control.

`GEN_CAPABILITY` preserves the overshooting candidate separately from the solved contact. Its `solved_boundary` event has signed `margin_previous`, `margin_candidate` and `margin_event`; the older `margin_final` remains projection distance. Base-point or discrete active-set updates without a bracket are explicitly `active_set_update_not_localized` with `lambda_event=NaN`. A failed bracket solve/localization requests the existing retry handling and is not reported as a solved contact. Event bracketing is local; it is not a guarantee of global event ordering through arbitrary discrete jumps.

This change does not implement Q-first increasing-P boundary following. That separate policy still needs its own equation/derivative treatment. The studied G2 reaches Pmax first; its P remains clamped and its Q can regulate voltage until the Q boundary.

## Augmented transition correction and tangent orientation

For projected capability transitions without a solved generator contact, ordinary NOSE/FULL continuation corrects the new equation set on a transverse plane through the incoming corrected candidate:

\[
F_{\rm new}(x,\lambda)=0,\qquad
\widehat t^T\big([x;\lambda]-[x_*;\lambda_*]\big)=0.
\]

Lambda is free in this correction. Base-point settlement and explicitly requested numerical-lambda endpoints retain fixed-lambda correction. Existing discrete tap/shunt correction remains in place; its outgoing tangent now preserves the incoming orientation too.

Tangents are mapped by identities of AC-angle, AC-voltage, converter-power and DC-voltage variables. Newly introduced coordinates have zero incoming component. The new tangent is oriented to agree with the mapped vector; a mode change does not force positive d(lambda)/ds. Normalization uses the existing solver coordinates (angles in radians, magnitudes in p.u., converter-power coordinates in MW). A different coordinate-scaling convention is not introduced here.

## NOSE means the first local loading maximum on the traced operating path

Two event kinds can satisfy `cpf.stop_at='NOSE'`:

- `NOSE`, with `kind='SMOOTH_NOSE'`: a smooth loading-tangent zero on an unchanged equation set.
- `LIMIT_INDUCED_TURN`: a localized control transition with positive incoming and negative outgoing loading tangents, oriented consistently.

FULL records the event and continues. Termination reports separate `smooth_nose_detected`, `limit_induced_turn_detected`, aggregate `nose_detected`, and `requested_endpoint_reached` fields. A FULL run that records a nose but stops later at a capability limit does not claim FULL completion. Neither event certifies dynamic stability.

Before accepting a control-changing trial, the solver checks loading-tangent reversal and mapped tangent orientation. A reversed orientation is also suspicious without a control change. It restores the pre-trial cases, contexts, policy state, control-freeze state, event records, caches and diagnostics, then halves the arclength step. Rejected trials are retained only in `cpf.turn_detection.history`.

For a continuous control-limit turn, localization requires all of:

1. A control-changing trial with positive incoming and negative outgoing loading tangents and a positive orientation dot product.
2. Arclength step no larger than `max(1e-10,min(1e-7,cpf.nose_tol/100))`.
3. Both incoming-candidate and outgoing-state intervals, measured in the solver coordinates, no larger than `cpf.nose_tol`.
4. A converged corrected network state and settled enabled controls.

The ordinary `cpf.step_min` does not prevent these event-refinement steps. The event search allows at most 60 rejected refinements and does not halve below 1e-12. If local refinement stalls, the checkpoint recovery described below runs before declaring failure. If recovery is unavailable or exhausted, an unresolved turn returns failure and retains the last accepted point. A discrete jump that does not shrink with refinement is therefore not mislabeled as a localized continuous turn. After either a smooth nose or a localized control turn, FULL restores the pre-refinement step size, subject to any replay cap.

The smooth locator also checks its residual/tangent or bracket convergence before reporting an event. FULL avoids immediately rediscovering the same near-zero tangent.

This is bracket refinement in continuation arclength, not a generic analytic solve of every possible control-limit equation. Endpoint sign checks cannot guarantee detection of multiple folds hidden inside a single step. The orientation check adds protection against branch reversal, but it is not a global branch-uniqueness test.

## Checkpoint replay after stalled turn refinement

Unified CPF automatically retries a stalled control-turn search from a saved accepted point before a capability update. This changes the approach to the difficult region, which can matter when the projected-Q policy makes a finite setpoint jump that persists even as the local trial step tends to zero. It applies with coupled current either enabled or disabled.

```matlab
options = mpoption(options, 'vsc_mtdc.nose_replay_max', 3); % default
options = mpoption(options, 'vsc_mtdc.nose_replay_max', 0); % disable replay
```

The nonnegative integer option bounds the total number of checkpoint replays in a run. The solver keeps a bounded cache of the base point and three recent pre-capability-update checkpoints. At the first suspicious turn it fixes the latest checkpoint as the replay anchor. Further local refinements do not replace that anchor with a nearly identical point at the stalled event.

After local refinement exhausts its budget, recovery restores the checkpoint's cases, network contexts, policy state, discrete controls, control-freeze flags, caches, diagnostics, solution, tangent, accepted trace and events. Accepted points after the checkpoint are removed. The new step cap is half the checkpoint's saved step, or half the previous replay cap for another attempt from that anchor. The solver does not launch a replay with a cap below ordinary `cpf.step_min`. Adaptive growth and other step proposals remain bounded by the replay cap for the rest of the run.

`results.cpf.checkpoint_replay` reports the attempt budget, attempt count, step cap and history. Each attempt records its failed lambda, checkpoint lambda/index, discarded-point count, old/new step caps and restoration verification. An infinite step cap means no replay occurred. Rejected local trials remain in `results.cpf.turn_detection.history`, tagged with `replay_attempt`; they are diagnostics, not accepted path points. Work-profile counters include discarded computation.

Recovery does not relax convergence, feasibility or event-localization criteria. It can recover a trace without certifying that every smaller initial step produces the same projected-Q history or nose. In particular, this is not an exact event-ordering solution for discontinuous capability projections. A failed smooth-nose locator and unrelated corrector failures retain their existing handling; this recovery specifically follows exhausted suspicious-turn refinement.

## Verified study and regressions

The 2026-09-17 baseline for the Beerten constant-P/Q non-slack dispatch study with ULTC, switched shunt and G2's 150 MW capability located the first turn at approximately lambda=1.245668943, V5=0.680547 p.u. This agrees with the separately solved G2 Q-limit event. Its latched-current FULL path stopped later near lambda=0.603 without completing the requested endpoint. These historical results remain unchanged.

The corrected 2026-09-18 verification is in `outputs/cpf_branch_preserving_release_20260918/`. G2's P contact remains at lambda=11/24 with P=150 MW; steps 0.1 and 0.05 preserve the first loading maximum near 1.245668944. The current-limited lower branch does not reach VSC2's voltage target, so no restoration occurs. With release enabled or disabled, FULL follows the same lower branch and stops at the existing converter-capability restriction near lambda=0.603, without claiming endpoint completion. The earlier `outputs/cpf_event_release_20260918/` remains historical evidence of the rejected finite-jump policy, not proof of complete branch tracing.

`tests/t_cpf_local_release.m` verifies continuous restoration at an initial contact and at a bracketed interior contact, and rejection of an outward direction. `tests/t_cpf_event_release.m` verifies exact generator contact, NOSE/FULL behavior at two step sizes, identical constrained traces with the local policy on/off, and physical balances, capabilities, load interpolation and control acceptance.

Verification artifacts, source snapshots, diffs and exact flags are saved in `outputs/cpf_standard_integration_20260917/`. `tests/t_cpf_coupled_controls.m` verifies current-row derivatives for three station configurations, metadata validation/round-trip, rollback, event localization and independent AC/DC/bridge/capability checks on saved verification runs. The existing PCC/station, directional-loss and VSC regression suites are also run.

Checkpoint-replay verification is saved separately in `outputs/cpf_checkpoint_replay_20260917/`. With coupled current disabled and initial step 0.1, the studied run previously stalled at lambda=1.245549498833. One replay from lambda=1.204212007000 with a 0.05 step cap locates a smooth nose at lambda=1.245535052415, V5=0.678662482 p.u. FULL records it and continues until a later converter-capability stop near lambda=0.603060043. Coupled-current-enabled NOSE/FULL accepted physical traces are identical to the preceding integration results and require no replay. The new `tests/t_cpf_checkpoint_replay.m` exercises replay, restoration, bounded options, disabled behavior and both endpoint modes using the saved study fixture.
