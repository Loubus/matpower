# Experiment B: retain continuation during capability settlement

This isolated solver experiment changes no case parameter and no production file. It uses the saved 150 MW generator constant-P/Q, non-slack-dispatch Beerten case with ULTC and switched shunt. The full CPF is requested at the original 0.1 step and at 0.05, with the original iteration budget and all other options unchanged.

## Algorithm changed

The original converter and generator active-set stages obtain an electrical CPF point, select new fixed control orders, then solve a power flow at fixed loading. The experimental stages instead solve the same new electrical equations with loading free, plus an incoming-tangent hyperplane through the pre-switch corrected candidate:

\[
F_{a^+}(x,\lambda)=0,\qquad
 t_-^T\bigl([x;\lambda]-[x_{\mathrm{candidate}};\lambda_{\mathrm{candidate}}]\bigr)=0.
\]

The normal CPF predictor/corrector has already selected the candidate's continuation location. This correction preserves a transverse coordinate at that candidate; it does not impose an arbitrary lower loading to obtain convergence. The actual change in loading is recorded for every correction, including rejected attempts.

The incoming tangent is calculated from the pre-switch equations, oriented using the secant from the last accepted solution. The tangent is mapped by state identity (AC voltage angle, variable AC voltage magnitude, converter active power, DC voltage). When a PV bus becomes PQ, its newly freed voltage coordinate has zero incoming derivative. The outgoing tangent uses that same transverse direction, with consistent orientation; this avoids automatically forcing a positive loading component after a descending-branch limit change.

All electrical evaluations use the existing lambda-dependent case and dispatch functions. The corrected loading is propagated through VSC and generator settlement, controller handoffs, main-loop acceptance, and result construction. The existing fixed-Q converter projection, including its 0.1% inward Q adjustment, remains unchanged. There is no coupled current-limit equation in this experiment.

## Unchanged controls and numerical settings

- Station model, loss model, PCC setpoint definitions, and capability ratings.
- Generator capability, dispatch rules, converter priority, and DC-voltage control.
- Converter Q projection and reserve/margin convention.
- Discrete ULTC and switched-shunt settlement at the currently selected loading.
- Newton tolerances, iteration limits, adaptive CPF settings, and requested FULL endpoint.
- Base-case and explicitly requested fixed-loading PF behavior.

The baseline generator's fallback to a second fixed-loading re-solve is disabled during continuation because it would undo the purpose of this experiment. Its baseline approximate event-location calculation remains available as metadata.

## Deliberate prototype limitations

This is a bounded test of augmented capability correction and tangent transport, not a complete event-localized constrained CPF implementation. The converter event is still detected at a corrected candidate, and the baseline generator margin interpolation is retained. We do not claim that every earliest event has been solved exactly. Discrete-only tangent reset and fixed-loading discrete settlement remain baseline behavior. Those differences matter when comparing close control transitions.

A changed active set may describe a discontinuously shifted fixed-Q branch. A transverse correction identifies a nearby point on it; it does not prove that a physical continuous trajectory connects the two operating states. Every before/after loading change must therefore remain visible in the journal. Passing Newton's residual test alone is insufficient: current/voltage inequalities, generator capability, control deadbands/saturation policy, AC/DC balances, and lambda-dependent loads/dispatch must also be checked.

FULL means tracing the descending branch back to the declared loading target. Passing a maximum-loading sample or reaching an iteration budget is not FULL completion. The baseline formal nose flag remains unchanged; observed tangent sign changes are reported separately.

## Reproducibility

`build_copy.py` creates uniquely named `b17_cpf.m` and `b17_psse.m` from the present production source. `implementation.diff` records all solver changes and `source_sha256.json` records the source fingerprint. `b17_run(0.1)` and `b17_run(0.05)` load the saved original case/options and write separate MAT files and logs, without overwriting earlier experimental files.

`b17_journal.m` records every augmented correction with stage, candidate index, loading before/after, incoming loading tangent, state dimensions, hyperplane residual, electrical residual, iteration count, success, and state correction norm. A candidate index can repeat during retries; journal entries are attempts, not accepted trace points.

## Numerical results

Both complete requested CPF runs were executed through the parent-coordinated MATLAB MCP session. No MATLAB warnings were recorded.

| Quantity | Baseline step 0.1 | Experiment B step 0.1 | Baseline step 0.05 | Experiment B step 0.05 |
|---|---:|---:|---:|---:|
| Accepted points | 129 | 43 | 45 | 77 |
| Maximum sampled loading | 1.245160631 | 1.243784920 | 1.245254301 | 1.244125681 |
| Last accepted loading | 1.245061005 | 0.603064705 | 1.245254301 | 0.603048242 |
| Descending loading steps | 75 | 21 | 0 | 34 |
| Last accepted bus-5 voltage, p.u. | 0.673537108 | 0.235722175 | 0.680698335 | 0.235708593 |
| Terminal stage | VSC capability | VSC capability | Generator capability | VSC capability |
| Requested FULL endpoint reached | No | No | No | No |

B's solver success flag is 1 in both runs **only in the configured-stop-policy sense**. Its termination metadata explicitly reports that FULL was not completed. The last accepted loading values agree closely between steps; this is useful numerical consistency, not proof of an exact physical boundary.

### What improved

The augmented correction passes the difficult generator PV-to-PQ transition and continues well along the descending, very low-voltage branch. All accepted points pass the parent's independent electrical and declared-control-policy checks (17/17 after honoring tap saturation): AC/DC and bridge balances, full-station phasor/current reconstruction, loss equations, converter current/upper-voltage limits, fixed PCC orders, DC-voltage regulation, generator capability, tap/shunt ranges and allowed saturation, and lambda-dependent load consistency.

At the final point of the 0.1 run: G2 supplies 150 MW and 112.5 MVAr, VSC 2 supplies 115.923015 MVAr, the tap has reached 0.9, and the shunt is at B=15 MVAr-at-1-p.u. Its actual reactive supply is only 0.833474 MVAr because bus 5 is at 0.235722 p.u. Bus 7 is at 0.791081 p.u., outside its target band; this is an allowed saturated tap state under the declared policy, **not successful voltage regulation**. Electrical feasibility of these extremely low-voltage solutions is not evidence of dynamic stability or acceptable operating conditions.

### Why the smaller maximum is not a measured reduction in loadability

At step 0.1, the incoming PV candidate reaches lambda 1.251231555 before G2's Q-limit settlement. The augmented PV-to-PQ correction returns lambda 1.244072451; the following VSC correction returns 1.243784920. At step 0.05 the corresponding sequence is 1.250643897 -> 1.244482136 -> 1.244125681.

The approximate event treatment spans the transition region. It neither locates the first generator-limit crossing exactly nor samples the complete limited branch near its maximum. Therefore compare these as **maximum accepted samples**, not as exact noses or improved/worsened stability margins. This is a limitation of the bounded prototype, and a reason to implement proper event localization before drawing loadability conclusions.

The original `cpf.z(end,:)` convention also misses the incoming tangent across this event: the state dimension grows when the generator becomes PQ, and the trace pads older columns below their old lambda component with NaN. Recover the loading tangent as the last finite component of each column. `b17_derived_report.m` records that corrected extraction separately; the original summary's `turn_indices` field must not be used as evidence that no turn occurred. A tangent direction change across an active-set event is not by itself a localized smooth saddle-node.

### What fails next: converter 3, then converter 2

The logging-only replay identifies converter 3's current as the initiating limit. Its original PCC schedule is 35 MW and 5 MVAr at bus 5. With the filter-free station, converter current equals PCC series current, so keeping those orders requires

\[
|I_{c3}|=\frac{\sqrt{35^2+5^2}}{150V_5}\leq1,
\qquad
V_5\geq\frac{\sqrt{35^2+5^2}}{150}\approx0.23570226.
\]

The final accepted voltages lie just above this bound. However, the baseline policy permits radial P/Q derating; this bound is therefore a boundary of the original fixed orders, **not a proof that all allowed subsequent operation is impossible**.

The last rejected 0.1-step attempt shows the surviving outer-projection feedback:

| Outer correction input | Loading | Bus-5 voltage | C3 P / Q (MW / MVAr) | Current-capability margin C3 / C2 (MVA) |
|---|---:|---:|---:|---:|
| First violated candidate | 0.603006419 | 0.235699356 | 35.000000 / 5.000000 | -0.0004357 / initially inside |
| After first radial projection and augmented solve | 0.592959107 | 0.231831601 | 34.964569 / 4.994938 | -0.544808 / -0.104260 |
| After next C3 and C2 projection and augmented solve | 0.461259631 | 0.183401309 | 34.390811 / 4.912973 | -7.229769 / -1.977535 |
| Next Newton attempt | -0.917067347 | invalid trial | not accepted | residual 1.4142e6 |

Although P3 and Q3 are reduced, voltage drops more strongly and the actual current-limit violation becomes worse. VSC 2 then joins the violation. The last Newton trial leaves the physical model's valid domain and is rejected. Smaller predictor steps repeat the same type of cascade; the solver retains the last accepted point near lambda 0.603.

The tiny initial C3 violation triggers a radial correction that includes the existing 0.1% inward margin. Keeping this projection policy was intentional for isolation. The outcome shows that continuation alone can move the failure substantially farther along the branch while leaving the fundamental outer-projection inconsistency unresolved.

### Evidence and code locations

- Baseline converter fixed-loading correction: `matpower/lib/runcpf_vsc_mtdc.m:1332`; generator correction: `:1830`; baseline tangent reset: `:830`.
- Experimental converter correction: `b17_cpf.m:1347`; generator correction: `:1848`; VSC loading propagation through dispatcher: `:1091` and generator handoff `:1902`.
- Incoming tangent and state mapping: `b17_cpf.m:3594` and `:3608`; augmented transverse correction: `:3614`.
- Outgoing tangent transport/orientation: `b17_cpf.m:831`. Carried tangent is reset before every predictor trial at `:454`; a failed attempt's carried tangent cannot leak into the next retry.
- Production event-array padding: `matpower/lib/runcpf_vsc_mtdc.m:4465`; it explains the changing lambda-tangent row.
- `step_100.mat`, `step_050.mat`, their JSON summaries, and the parent independent audits `../B_100_audit.json` and `../B_050_audit.json` contain the primary run evidence.
- `diagnostic_step_100.mat` and its JSON contain the full projection reports. The diagnostic copy only adds logging. The parent verified exact equality of every accepted lambda, bus, converter, generator and branch array against the primary 0.1 run.

### Recommendation after the experiment

Keep augmented capability correction and tangent transport as promising components. Combine them with physical active-limit equations and exact event localization before considering a production change. Carrying the incoming tangent is essential; merely changing a local Newton solve while resetting the outgoing tangent to positive loading can reverse the intended traversal. Retain explicit handling of discrete equipment changes, state rollback, control recovery, and unsupported intersections. Neither numerical convergence nor the configured-stop success flag should be reported as completion of FULL or certification of a physical loadability boundary.

## Follow-up B2: tangent transport for every active-set stage

`all_controls/` contains a separately preserved follow-up variant. It initializes the incoming tangent carrier at each predictor trial, so a discrete-only tap/shunt change also preserves the intended direction. The original B only populated that carrier during capability corrections.

Both B2 runs reproduce B to numerical roundoff: step 0.1 ends at lambda 0.603064704847 with 43 points; step 0.05 ends at 0.603048242023 with 77 points. Both stop at VSC capability before completing FULL. For these B traces, descending tap changes already coincide with converter projections, so the original carrier was populated. The generalized transport matters when combined with the simultaneous current-boundary equations, where repeated Q projection no longer automatically supplies a carrier during each tap change.

See `all_controls/incremental.diff` and `all_controls/README.md` for the isolated change and numerical comparison. B and its diagnostic outputs are retained unchanged.
