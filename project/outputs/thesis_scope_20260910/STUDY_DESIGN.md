# Proposed thesis scope: TRANSPA hydro corridor, 500 kV AC versus VSC-HVDC

Prepared 2026-09-10 from the user's research objective, current project code, dated verification reports, and primary benchmark sources. This is a design proposal, not an implemented or numerically validated change. Existing solver code and historical outputs were not modified.

## Research objective and comparison

Compare power flow and steady-state voltage-stability/loadability of two transmission alternatives connecting a new hydroelectric plant through a long TRANSPA corridor: a 500 kV AC line and a VSC-HVDC link. Quantify the role of transformer voltage regulation, switched shunts, and generator/converter capability limits. TRANSPA is the application; Beerten and selected published systems provide validation. Exact PSS/E agreement is not an academic requirement.

The primary result is a defensible comparison, without assuming in advance that VSC is superior. Report transferred and delivered MW, losses, critical voltages, reactive reserves, limiting equipment, and control states. CPF evaluates equilibria along a defined stress path; it does not establish transient stability, converter-control stability, or the timing of long-term voltage collapse.

Build two explicit corridor alternatives. The existing Beerten `vsc_hvdc.enabled=false` option removes the DC equipment; it does not construct an equivalent 500 kV AC corridor. Therefore that toggle alone cannot implement the thesis comparison.

Use the same hydro plant, terminal locations, background network, demand, and dispatch assumptions. Compare at common hydro injections and record net receiving-end delivery, including unequal losses. Define comparable transfer requirements and disclose equipment ratings; equal cost is not assumed. The AC alternative needs credible resistance, reactance, charging and compensation. Include documented shunt reactors or other compensation appropriate to that design rather than handicapping AC by omission. VSC reactive support must respect converter ratings and voltage-dependent capability. Initial voltage-control targets should be documented consistently, not adjusted separately merely to improve one alternative.

## Keep / simplify / defer

| Component | Keep | Proposed simplification or boundary | Acceptance evidence |
|---|---|---|---|
| AC/DC electrical model | Network equations, losses, converter transformer/reactor/filter representation, valid references for each AC island | Keep the currently supported equations initially; no solver rewrite as part of cleanup | Residuals, independent PF comparison, consistent signs/bases, derivative checks where equations change |
| ULTC | Status, local/remote regulated bus, deadband, correct direction, finite tap grid and bounds, existing physical lockouts | One decision implementation for AC and AC/DC; deterministic documented ordering; remove exact PSS/E final-state matching from thesis acceptance | Small tests of direction, grid, bounds, regulation, multiple interacting devices |
| Switched shunt | Susceptance rather than fixed-Q injection, fixed-shunt separation, actual block states, status, regulated bus, discrete/continuous distinction | One decision implementation; simplify conflicting group policies to a declared policy; evaluate candidate moves with the actual electrical study model | Legal states, Q/voltage consistency, saturation and cycling tests |
| Generator/converter limits | Q capability and applicable P/current/voltage bounds; explicit control-mode transition at a binding limit | One documented priority when simultaneous P and voltage targets become infeasible; no implicit increase of ratings to continue | Capability residuals before/after transition, feasible base point, limit-event tests |
| PF/CPF coordination | Electrical re-solve after control changes, fixed-loading correction, continuation-direction rebuild as needed | Share family order and device decisions; retain solver-specific CPF mechanics | PF and CPF agree at matched loading/control states within declared tolerances |
| Failure handling | Last accepted feasible point, diagnostic trace, honest outcome | Bounded retries without changing model assumptions; unresolved cycling/nonconvergence terminates with that classification. Freeze/lockout recovery becomes a separately named sensitivity scenario | No accepted point hides a failed solve; terminal reason agrees with success/status |
| RAW/PSS/E interface | Import conversion, identifiers, three-winding/unit mapping, reference fixtures | Preserve as an adapter and validation route; postpone additional compatibility modes | Current supported import/physical mapping regressions remain meaningful |
| Experimental breadth | Existing evidence and a transmission benchmark suite: IEEE 30, New England 39, IEEE 57, Nordic, CIGRE B4 (DCS1 first) | Defer new LCC/FACTS modes, DC/DC support, meshed-grid policies, EMT and optimization/economic claims; use one shared benchmark workflow | No new solver feature without a direct thesis scenario |

Scope reduction must not silently disable devices already needed by TRANSPA. A fixed tap or fixed shunt state is a scenario assumption; a numerical inability to adjust a device is not a physical lockout.

## Proposed operating assumptions, pending corridor data

**Primary stress: hydro export.** Increase the new plant's active injection and reduce specified receiving-system generators using fixed participation factors and P bounds. Reserve a documented balancing mechanism for the incremental losses. This is a transfer/redispatch continuation, not uniform load growth. Check that the present CPF target construction supports this direction before using it. Stop or switch dispatch according to a declared rule when a participant reaches a bound; do not silently shift the transfer to an unlimited slack.

**Secondary stress: receiving-area demand.** Fix a stated hydro output, increase selected receiving-area loads at an initially fixed power factor, and dispatch a specified set of generators to meet the added demand and losses. Consider constant-PQ versus a justified voltage-dependent load model as a later sensitivity. Avoid claiming load-restoration effects from a model that does not represent them.

**VSC controls.** For an initially assumed two-terminal link, propose one DC-voltage-controlling terminal and one scheduled-power terminal, with AC voltage regulation where appropriate and feasible. A Q-setpoint variant can isolate the benefit of voltage regulation. Preserve current/capability limits; specify the priority between active transfer and reactive support at saturation. Whether the hydro end is a separate AC island changes the required voltage/angle reference and must be resolved before selecting the final modes. No grid-forming/dynamic claim follows from a steady-state voltage constraint.

ULTC and shunts are modeled as settled quasi-static controls: no physical time delay is implied by their numerical ordering. At a physical tap/shunt bound, continue with that bound if the electrical model remains feasible. At a generator/converter bound, continue only under the declared feasible control transition. Distinguish an operational transfer limit, a localized CPF nose, control nonsettlement, and numerical failure. Reaching a bound does not by itself prove voltage collapse.

## Small experiment matrix

First validate the electrical base point of each alternative. Then use the primary hydro-export path for the eight paired cases below; generator and converter capability limits stay enabled in every main case.

| Control profile | 500 kV AC corridor | VSC-HVDC corridor |
|---|---|---|
| Base tap/shunt states held fixed | A0 | D0 |
| ULTC active, shunts fixed | A1 | D1 |
| ULTC fixed, shunts active | A2 | D2 |
| Both active | A3 | D3 |

The existing regulator/generator voltage controls remain specified in each profile. For frozen devices, use each alternative's documented feasible base states. Add a VSC Q-setpoint versus voltage-control sensitivity to D3 after the main cases work; do not expand the full factorial prematurely. Repeat the main paired comparison under receiving-area demand stress only after dispatch assumptions are fixed. A small selected contingency study can follow if it materially changes the corridor comparison; an N-1 claim requires its own contingency coverage.

Save full accepted states, normalized balance residuals, loading/transfer definition, control actions, binding limits, outcome reason and source versions. Compare voltage curves at common physical MW, not raw lambda values whose definitions might differ. Report numerical PF convergence and operational feasibility separately. Never label the last point of a failed trace as a validated stability margin.

## Validation sequence and change boundaries

1. **Document current reference behavior.** Preserve the September audit and local scientific changes. The audit records four VSC test disagreements and TRANSPA failure at a generator-capability rebuild. Historical passing reports do not supersede those findings.
2. **Beerten first.** Reproduce the original published PF configuration separately from project-added ULTC/shunt/capability variants. The official MatACDC examples and the local 2010-paper case are not automatically parameter-identical. Align losses, station impedances, controls and sign conventions before comparing numbers.
3. **Several transmission benchmarks.** The user requests Nordic and IEEE systems beyond the 39-bus network, plus an additional CIGRE case. Use IEEE 30, New England 39, IEEE 57, Nordic and CIGRE B4 as the main suite, with IEEE 14 available for small checks. On the AC networks, begin with the original baselines and build explicit paired AC/VSC corridor alternatives. For the already hybrid CIGRE B4 benchmark, verify the available transcription against the reference data and start with the DCS1 two-terminal subsystem for VSC link validation. Other published VSC variants remain optional references. Use one scenario schema and runner across systems; implement sequentially without reducing the agreed suite to one case.
4. **Control-focused validation.** Use small fixtures for isolated rules, then run applicable common control profiles across the main suite. Nordic is originally AC; a VSC addition is a documented new adaptation. Dynamic LTC/OEL data informs the mapping but does not turn CPF into time-domain simulation. Fixed transformer ratios and shunt susceptances in IEEE cases are not complete automatic-controller definitions; record added deadbands, steps, limits and capability assumptions explicitly. CIGRE B4 is included for link power balance, losses, voltage regulation and capability validation; any added controls or AC replacement scenario are declared adaptations. Its inclusion does not require implementing the full meshed grid or DC/DC converters. Audit exact source variants, bases and existing modifications before adapting any case.
5. **Implement and validate bounded simplifications before application work.** Agree the control/failure specification, then share decisions and remove unnecessary policies incrementally. Recheck essential small fixtures and representative traces across the benchmark families. Retain electrical/control correctness checks currently named PSS/E tests; move exact-emulation studies into a separate historical/optional suite after resolving fixture dependencies. Changes in behavior under the new declared policy are assessed scientifically; exact historical event order is not automatically a requirement.
6. **Full-network/TRANSPA application last.** Preserve the original PSS/E RAW throughout. Once the algorithms are validated, assess whether to reuse, revise or rebuild the historical reduction. Compare any reduced equivalent against the full network at the base and several stressed operating points with matched controls and dispatch. Check boundary voltages, P/Q exchanges and the response to regulation. A base-point fit alone is insufficient evidence for the corridor margin comparison. Only then construct and study the proposed hydro AC/VSC corridor alternatives. The old reduction files remain together as deferred historical material rather than driving the first cleanup batch.

Initial numerical acceptance: use the configured electrical residual tolerance (record its value and units), require a feasible initial operating point, and verify physical limits with separate explicit tolerances. For independent PF references, propose 1e-4 pu maximum voltage error and 1e-3 pu base-power-normalized P/Q discrepancy as initial investigation thresholds when the models and source precision permit; these are proposed thresholds, not measured results. Rounded paper tables need precision-aware comparisons. For CPF, halve the nominal/maximum step and tighten correction settings in a targeted sensitivity; a provisional goal is under 1% change in the limiting physical transfer for the same event/branch. Discrete events and changes of limiting mechanism must be explained even if the scalar difference is small.

## Immediate code review locations

- `matpower/lib/+mp/psse_xfmr_control.m` and `psse_unified_control_update.m`: duplicate tap decisions.
- `matpower/lib/+mp/psse_swshunt_control.m`: candidate screening currently uses plain PF with extensions and generator Q-limit enforcement disabled.
- `matpower/lib/+mp/task_pf_psse.m` and `task_cpf_psse.m`: mirrored control-family ordering and dispatch.
- `matpower/lib/+mp/psse_xfmr_guard_candidate.m`: numerical rejection can lock out taps.
- `matpower/lib/runcpf_vsc_mtdc.m`: continuation, capabilities, freeze/recovery and experimental policies.
- `auditoria_psse_matpower/transpa_reduccion/cpf_psse_runner/`: transfer definition, dispatch, termination reporting and study outputs.

These are design targets, not established causes of every current failure. The first implementation should be selected only after verifying the current path used by the chosen benchmark.

## Inputs still needed

Hydro plant name/location, installed MW and generator-unit data; corridor sending/receiving buses and approximate length; existing AC connection at the hydro end; proposed AC circuits, conductor data and compensation; proposed VSC/DC voltage and power/current ratings. Unknown values can remain parameterized assumptions. No deadline or PSS/E-equivalence requirement was imposed by the user.

See [benchmark inventory](BENCHMARKS.md) and [download manifest](source_manifest.json). This proposal does not verify the separate historical statement about national HVDC deployment; it is not needed to define the comparison.
