# Batch 6 — Beerten reference alignment and capability validation

Study: 2026-09-11; evidence packaging completed 2026-09-14. Final scientific traces: **`final_04/`**. Final independent
calculations: **`final_04/independent_final/`**. Earlier directories retain
investigations and failures; they are not alternate accepted results.

## Outcome and scope of the evidence

The archived author's **MatACDC 1.0 Stagg five-bus / three-terminal, single
DC-slack example** was reproduced using the unmodified author solver, its
manual's rounded tables, and a separate Python electrical implementation.
This is distinct from the 2010 paper's filter-free example and from the
project's seven-bus controlled extension. Exact full replication of the
2010 example remains unsupported by the collected numerical inputs.

The saved constant-PQ project direction was run with its supported converter
and non-slack generator capability options enabled. Genuine limiting-mode
transitions occur and continuation proceeds beyond both initial bindings.
The final default-step run stops at **lambda 1.138532043940** because a later
converter-capability electrical re-correction fails. It does not detect a
CPF nose. Independent augmented equations locate a nearby fold of the
implemented binding-circle model at **lambda 1.138532854472** under the final
fixed tap/shunt and generator-Q state. That is a mathematical diagnostic of
this model, not an equipment-compliant installation margin.

**No all-equipment-compliant margin is established.** The implementation
exempts the slack from generic capability enforcement. Applying the same
100 MVA fallback thermal curve to it makes the initial point infeasible;
the saved case supplies no separate nameplate capability metadata to resolve
that conflict. Later, even the slack's original explicit PMAX is exceeded.
No redispatch, rating increase, tolerance relaxation, freeze, backoff or
recovery was added to make these conflicts pass.

Two bounded implementation repairs were isolated and verified: public unified
PF tables now contain solved original equipment values, and capability changes
re-settle affected existing voltage controls before CPF acceptance. Historical
inputs and outputs remain unchanged, including the unconstrained nose at
lambda **1.305375520422**.

## 1. Published-reference alignment

### Sources actually used

1. J. Beerten, S. Cole and R. Belmans, *A Sequential AC/DC Power Flow Algorithm
   for Networks Containing Multi-terminal VSC HVDC Systems*, IEEE PES GM 2010,
   local PDF `Referencias/Jef Beerten - A Sequential ACDC Power Flow Algorithm for.pdf`.
   Equations (1)–(6), (9), Table I, Tables II–III and Figures 8–9 were inspected;
   the converter table was also visually checked. The article expressly puts
   controlled powers at the AC system bus. It gives no complete numeric table
   of its station impedances and DC branch resistances.
2. The collected [author's MatACDC distribution](https://www.esat.kuleuven.be/electa/teaching/matacdc),
   `cases/beerten/upstream/MatACDC1_0.zip`, extracted locally under `reference/`.
   Its original cases are `case5_stagg.m` and `case5_stagg_MTDCslack.m`.
   The DC case itself cites the 2011 PowerTech distributed-control paper; its
   numerical example is documented in section 6.1 of the
   [MatACDC 1.0 manual](https://www.esat.kuleuven.be/electa/teaching/matacdc/MatACDCManual),
   especially printed pages 31–32. This precise archived example, not every
   system called “Beerten,” is the reproducible full reference in this batch.
3. `cases/source_manifest.json` supplies the original download provenance.
   Batch-6 `source_manifest.json` adds hashes of inputs, author code, current
   changed files and comparison scripts. The extracted author bundle is local
   reference material; it is not part of `batch6.patch` or a redistributed
   dependency. Its original license restrictions remain applicable.

### Configuration comparison

| Item | Archived MatACDC 1.0 reference | 2010 paper / local project distinction |
|---|---|---|
| AC network | Stagg: 5 buses, 2 generators, 7 branches; 165 MW / 40 MVAr demand | Same five-bus core and per-unit branch R/X/B. Project fixture adds generator bus 6 and branch 2–6, and moves bus-4 load behind branch 4–7 to bus 7: 7 buses, 9 original branches. |
| AC base | 100 MVA, 345 kV | Local case uses 230 kV; added generator bus uses 13.8 kV. The paper is not a complete base/impedance input specification. |
| DC network | 3 buses linked as a triangle; AC PCCs 2, 3, 5; 100 MVA, 345 kV, `pol=2` | Local DC identifiers 2,3,5, base 300 kV. Its single-conductance representation has no explicit pole count. |
| DC resistance | 0.052, 0.052, 0.073 pu per pole | Independent mapping uses R/2 with unchanged 100 MVA base. Local values are 0.02633, 0.02337, 0.03601; they are not that exact mapping. Numeric 2010 R values cannot be established from the collected paper. |
| Station impedances | All stations: transformer 0.0015+j0.1121; filter B=0.0887; reactor 0.0001+j0.16428 pu | Paper neglects filters and lumps station impedance. Local filter=0; tiny transformer j0.0001 plus reactor R=[0.0009615,0,0.000785], X=[0.0399,0.0392,0.0399]. Their exact published provenance is unverified. |
| Active/reactive controls | PCC 2: −60 MW/−40 MVAr; PCC 5: +35 MW/+5 MVAr; PCC 3: Vdc=1 and Vac=1, P/Q solved | Same nominal modes in paper and local cases. Local `PAC_SET/QAC_SET` constrain internal converter powers, not the published PCC powers. PDC fields for fixed-PAC stations are not additional simultaneous setpoints. |
| Generator dispatch | G2=40 MW at bus 2; G1 balances. VG1=1.06, VG2=1.0 | Project moves G2 to bus 6, with P2 still 40 MW; no participation redispatch in the saved direction. |
| Loss model | A=1.103 MW; B=0.887 kV; C columns=2.885/4.371 ohm, current conversion uses 100/(sqrt(3)*345) kA | Local A=1.1033 MW; B=0.1999949 MW/pu-current; C=0.1466667,0.2222333,0.2222333 MW/pu-current². The local conversion/sign-dependent coefficient provenance is not established as an exact 2010 input. Python follows each configuration's supplied coefficients, without fitting. |
| Capability data | Converter Imax=1.2 pu and Uc range [0.9,1.1]; default author `LIMAC=0` | Project station ratings 150 MVA and fallback Uc,max=1.15 are additional assumptions. No project Uc,min field. Generator generic curves are project assumptions, not published capability curves. |
| Other controls | No automatic project ULTC/shunt | Project adds load-side ULTC (10 tap positions, [0.9,1.1]) and bus-5 shunt (0/5/10/15 MVAr at 1 pu). These are not validated by published PF agreement. |

The local file name/comment “Beerten” must not be used as evidence of exact
published input equivalence. With its existing internal P/Q definitions, the
local five-bus PF has PCC injections (MW/MVAr) approximately
(-60.051759,-42.153244), (20.771704,7.271287), (34.990039,4.492437).
They do not equal the paper's (-60,-40), (20.68,7.17), (35,5) PCC quantities.
Bus-5 voltage is 0.990329389, while the paper prints 0.991; this is beyond
half the final printed voltage digit. No parameters were tuned to hide it.

### Reproduction and reference precision

`run_author_reference.m` executes unmodified `runacdcpf` with the archived
default AC/DC tolerances and limits off. It supplies a modern MATPOWER option
structure for quiet AC output; there are no author-code compatibility patches.
Scoped path additions are removed afterward, including the conflicting
`idx_busdc` resolution. The author solver converges in three outer iterations.
All nine compared groups of manual AC bus/generator/branch, converter PCC/
internal-voltage, and DC voltage/power values agree within their printed
rounding intervals. The manual gives only rounded values, not 1e-8 accuracy.

The independent Python implementation constructs its own admittance matrices
from original branch and station data, uses rectangular voltage unknowns and
finite-difference SciPy root solves, and evaluates both station terminals.
It does not call MATPOWER, MATLAB, the project mismatch/Jacobian, or MatACDC.
For this archive configuration its maximum complex AC-voltage difference
from the author implementation is **1.05e-10 pu**, PCC power difference
**1.08e-7 MW/MVAr**, and DC-voltage difference **1.14e-14 pu**. Its own maximum
equation residual is **2.33e-11 pu**. MatACDC's reuse of MATPOWER for its AC
subproblem is explicitly distinguished from this independent calculation.

| Full archived reference quantity | Result |
|---|---:|
| PCC-3 P / Q | 20.7566019 MW / 7.1371612 MVAr |
| Bus-5 voltage / angle | 0.990759490 pu / −4.14941603 deg |
| Converter internal voltages (PCC 2,3,5) | 0.889865474 / 1.006975085 / 0.995480993 pu |
| DC voltages | 1.007910283 / 1 / 0.997784060 pu |
| DC injections, project sign convention | +58.6273601 / −21.9013162 / −36.1855615 MW |

The first archived converter is below its supplied Uc,min=0.9. This is consistent
with the author's default limit enforcement being off; successful reference PF
reproduction does not imply that even this archived example is equipment-feasible.

For the 2010 article, two narrower checks were actually executed: the AC-only
Stagg PF, and the AC network PF with the article's printed PCC injections
(including printed Ps3=20.68 MW) and voltage controls. The latter reconstructs
Q3=7.1658603 MVAr, consistent with 7.17, and all printed AC-voltage rounding
intervals. It is a consistency check using a published *output* as input,
not an independent full AC/DC replication. The AC-only bus-5 angle is
−5.764949462 deg against printed −5.77: absolute error 0.005050538 deg,
slightly above the strict half-digit gate 0.005. **That check remains failed.**
Input provenance/rounding is unresolved; neither branch values nor comparison
tolerances were altered. See [reference precision checks](final_04/independent_final/reference_precision_checks.json).

## 2. Capability-enforced project scenario

The named entry point is
`studies/beerten/beerten_constant_pq_capability_batch6.m`, returning the exact
saved batch-4 base and target plus declared options. `final_04/scenario.mat`
retains those inputs and original/current options. The capability runs are
named `beerten_constant_pq_supported_capabilities`; their traces deliberately
retain the implementation's slack exemption and disclose its consequences.

Physical loading is identical in all runs:

```
P5(lambda) = 60 + 240 lambda MW       Q5(lambda) = 10 + 40 lambda MVAr
Ptotal(lambda) = 165 + 240 lambda MW  Qtotal(lambda) = 40 + 40 lambda MVAr
Pgenerator2 = 40 MW; slack supplies remaining demand and all losses.
```

Other demands, converter transfer targets, ratings, station impedances,
capability metadata, iteration limits and tolerances are unchanged. In
particular, the old 373.290125 MW figure at the unconstrained nose denotes
**bus-5 demand**; total scheduled demand there is **478.290125 MW**.

### Enforcement option and representation audit

| Option / limit | Final setting and actual scope |
|---|---|
| `capability_enforce` | 0→1: converter geometric capability, using original station rating 150 MVA; does not enforce every station/network limit. |
| `capability_gen_enforce` | empty→1: generic non-slack generator curve, Sbase falls back to original MBASE=100 MVA, thermal type 2. No `gen_capability` or `vsc_capability` metadata exists in this saved fixture. |
| `capability_pf_enforce` / max-it overrides | Empty; PF converter enforcement inherits 1 and max-it 10. CPF converter max-it 10; generator override empty inherits 10. |
| PF generator generic capability | Not implemented by the PF converter loop; this option is implemented in CPF. Independent fixed-state PF uses the accepted generator Q state, not an imaginary PF generic-capability controller. |
| Slack generic curve | Explicitly exempt in enforcement and `check_gen_capability`; separately audited here against the original fallback data. Full slack enforcement / feasible redistribution unavailable. |
| Generator P/Q box | Original PMAX/PMIN and QMAX/QMIN audited at every point. `cpf.enforce_q_lims` requested 0→1, but no RAW GENQ metadata exists, so it does **not** establish box enforcement on this unified path. The non-slack generic curve is stricter than its boxes in this run. |
| `cpf.enforce_p_lims` | Original 0 retained; standard active-P limit event path unsupported by unified CPF. Slack PMAX=500 MW is eventually violated. |
| Converter current / active power | Implemented surrogate uses internal P/Q with PCC voltage: abs(P)≤150 and hypot(P,Q)≤150*Vpcc. Actual reactor current is separately calculated from full terminal voltages/powers and compared with the implied 1.5 pu current base. These are not the same constraint. |
| Converter internal voltage | Implemented circle uses abs(Ztransformer+Zreactor), Vpcc and Vmax=1.15. It is a geometric approximation; full-model actual Uinternal≤1.15 is separately audited. Minimum converter voltage, modulation limits and a full filter-aware manufacturer P/Q envelope are unavailable. |
| Converter station thermal limits | Original transformer/reactor RATE_A=150 MVA audited at both ends; not independently enforced as branch-flow constraints. |
| Network voltage / thermal limits | Original bus [0.9,1.1] and original branch RATE_A remain unchanged. `cpf.enforce_v_lims=0`, `enforce_flow_lims=0`: standard unified event support unavailable. Original branch overloads and voltages outside the generic bus range are reported, not waived as equipment feasibility. |
| DC branch constraints | Resistive power balance represented. This local DC branch format has no thermal ratings or Vdc upper/lower enforcement metadata. No limits invented. |
| PQBRAK / physical saturation | `exp.psse_pqbrak=0`; `psse_control_limit='saturate'`. Original effective transformer VCTOLV=0.005 pu and shunt tolerance 1e-5 pu are retained, with original bands [0.95,1.03]. |
| Capability stop / recovery | `capability_limit='stop'`, VSC/gen overrides empty. No freeze, transfer backoff, derating, controller lockout or implicit recovery introduced. |
| Release | Existing projection keeps converted modes; no automatic capability release-to-V/PV policy is added or certified. Physical tap/shunt saturation retains normal reversal eligibility. |

### Initial feasibility

The solved base needs G1=(133.592923 MW, 75.010034 MVAr) and
G2=(40 MW, −14.266728 MVAr). Original generator P/Q boxes, actual converter
current/maximum-voltage and station ratings pass at this base. The non-slack
generic curve and all implemented converter regions also pass.

If the same default thermal curve is required for **both** original generators,
its Pmax is 0.8×100=80 MW. G1 alone exceeds it by **53.592923 MW**; even the
two 80 MW curve maxima sum to 160 MW, below the 165 MW base demand before
losses. That fully enforced interpretation has no feasible base. MBASE is a
per-unit base, not independent proof of a manufacturer's nameplate capability;
the missing rating/curve data and slack exemption must be resolved explicitly
before a different physical study is defined. This batch did not substitute
the `[500,200]` metadata from another “explicit” Beerten variant.

Therefore the supported-enforcement trace below is an implementation study,
not a workaround that makes the fully constrained base feasible. Every audited
point fails the all-generator generic-curve feasibility requirement. At its
default-step endpoint G1 also exceeds the unambiguous original PMAX by
5.506338 MW; branches 1–2 and 2–5 overload their original 250 MVA RATE_A.

### Results and transitions

| Scenario / CPF step | Accepted points | Terminal lambda | V5 pu | Total demand MW | Termination |
|---|---:|---:|---:|---:|---|
| Unconstrained reference / 0.1 | 35 | 1.305375520422 | 0.594706044 | 478.290125 | detected mathematical nose |
| Supported capabilities / 0.1 | 26 | 1.138532043940 | 0.668476203 | 438.247691 | capability re-correction failure |
| Supported capabilities / 0.05 | 45 | 1.138531711818 | 0.667975435 | 438.247611 | capability re-correction failure |
| Supported capabilities / 0.025 | 83 | 1.138527434090 | 0.668665234 | 438.246584 | capability re-correction failure |

`results_table.csv` includes generator P/Q/reserves, V3/V5/V6/V7, converter
loading, taps and shunts. In the default constrained endpoint G2 is at
Q=75.2271164 MVAr with zero upper reserve, V6=0.948706095; converter 2 has
Qinternal=140.0926916 MVAr, V3=0.943419157 and actual current utilization
0.944811493. Its geometric margin is +0.000311921 MVA. The original current
surrogate is almost binding, while the exact reactor-current ratio is below
one; neither quantity is silently substituted for the other. The tap is
0.944444444444 and shunt B=15 MVAr at 1 pu. V7=0.952463169 satisfies its band;
the shunt is physically saturated with unmet regulation.

For step 0.1, G2 changes PV→PQ at the accepted sample lambda 1.079419752,
clamping Q at 75.227116419. Converter 2 changes AC V→Q at the accepted sample
lambda 1.104504838, retaining DC voltage control. The trace continues after
both. Independent fixed-previous-control PF bracketing finds the corresponding
zero-margin crossings near 1.067075667 and 1.085089570. The saved generator
`lambda_event≈1.0763` and converter `lambda_event≈1.08488` are heuristic event
estimates, **not exact crossing locations**. The original event-location
tolerances/algorithms were not changed. Accepted transition samples are step
dependent, and no claim of continuous enforcement between samples is made.

Independent fixed-state solves were performed immediately before, at and after
these bracketed crossings, and at **all 188 nonsingular accepted samples**
across the four traces. All those PF solves converge, with maximum complex
voltage difference below **1.19e-8 pu** and independent equation residual below
**4.34e-12 pu**. The unconstrained localized nose is checked by residual but
excluded from this ordinary fixed-loading PF comparison because of its singular
Jacobian. These PF comparisons validate equations for a given state; they do
not independently validate the automatic choice of that state.

Every one of the **189 accepted points** was audited against the full AC nodal,
DC and converter balances, original demand direction, equipment data and
applicable voltage/P/Q controls. All electrical residual gates are below
1e-8 pu (largest MATLAB complex nodal residual approximately 7.91e-9).
All **154** supported-capability samples satisfy the original non-slack curve,
converter surrogate, actual reactor current, actual maximum internal voltage
and station MVA checks. Every final effective tap/shunt decision is accepted,
uses a legal state, and has no lockout. Full-equipment acceptance remains false
for the disclosed slack conflict and later additional violations.

At matched physical loading lambda 1.138532044, an independent PF using the
unconstrained trace's preceding fixed control state gives V5=0.761506346 and
G2 Q=89.1014684 MVAr, versus 0.668476203 and 75.2271164 in the constrained
accepted sample. `matched_loading_comparison.json` contains further paired
points and clearly labels this fixed-state comparison.

### Actual termination and independent limiting-point diagnostic

The unchanged public termination code reports `vsc_capability_limit`,
`success=true`, `success_scope='configured_stop_policy'`,
`requested_endpoint_reached=false`, `nose_detected=false`, and
`stability_margin_validated=false`. The legacy success flag means an orderly
configured stop; it is not electrical convergence of the rejected candidate,
completion of the NOSE request, or full equipment feasibility.

An output-local instrumented copy records decisions and correction failures
without changing equations or decisions. Its complete lambda/bus trace is
identical to the final main trace. Ten converter re-corrections fail during
step reductions. The final rejected candidate is lambda **1.138536913915**,
after three capability iterations, with reported residual **1.41421356e6**
(the solver's invalid-state residual sentinel). The attempted step is
0.0001953125; halving it would violate the original 0.0001 minimum. The stop
is an electrical correction failure, not exhaustion of the ten capability
iterations or a requirement to terminate on first binding. No freeze occurs.

Separately, Python solves the augmented fold equations for the original
implemented converter current circle as an equality, G2's binding Q, and
the final fixed tap/shunt. It obtains lambda **1.138532854472**, V5=0.668119078,
V3≈0.943245366. Five-point numerical Jacobians at increments 0.001 and 0.0005
give the same loading; equation residual is 9.25e-13, augmented residuals
2.06e-10 / 5.30e-10, and smallest singular values 2.90e-11 / 3.57e-10.
Nonzero left-null projections of loading and quadratic directional derivatives
(about 1.11488 and 1.34982) support a simple local fold. Fixed-loading attempts
above it fail and remain recorded. This diagnoses a local fold of the surrogate
model, not nonexistence of every other AC/DC solution or a manufacturer-limit
stability boundary. The source CPF itself never claims to have located this fold.

Terminal lambda spread over the three CPF steps is **4.61e-6**; V5 spread is
**6.90e-4 pu**. Thus loading agrees within the original target tolerance, but
the returned voltage is not an invariant limiting-point voltage. Use the
independent fold only within its explicitly fixed-state, surrogate-model scope.

## Repairs, regression and preservation

1. `runpf_vsc_mtdc_unified` previously returned original input bus/gen/branch
   tables beside a solved expanded `ac` result. The base slack could appear
   as 0 MW in a public equipment audit while `ac.gen` showed 133.59 MW.
   The public return now maps solved buses by external ID and copies original
   generator/branch rows. The internal `__results` interface is unchanged.
   Fifteen new checks include reordered buses/generators and offline rows.
2. CPF previously settled PSS/E controls before capabilities, then accepted a
   capability-corrected voltage without settling newly necessary tap moves.
   Pre-repair evidence has unsettled accepted points in the 0.1 and 0.025
   traces, confirmed using effective options. After a converter change the
   solver now runs its existing PSS/E stage, then rechecks converter capability;
   after a generator change it also rechecks the existing converter stage.
   It retains existing iteration bounds, policy, projection rules, correction
   equations and tangent rebuilding. Event final values are refreshed after
   the handoff. No controller or capability policy was replaced.

`t_beerten_capability_batch6` passes **442** checks. It exercises both affected
step sizes and checks every point's electrical equations, effective control
settlement, original non-slack capabilities, loading and station data. Final
broader regressions passed **1953 checks**, with **0 failed, 97 skipped and
0 exceptions**. Counts are in `regressions_02/*/counts.json`; the suite
summary is `verification_summary.json`. Code Analyzer reported no issues in
the two changed solver files, two new tests, or named scenario. MP-Test failures, skips and exceptions
are captured separately. The independent artifact gate has **1609 passed and
1 failed verification check** (the published AC-only angle rounding issue),
plus **4 failed full-equipment scenario acceptance checks**, deliberately
retained. These are distinct from implementation-regression success.

MATLAB numerical work used MCP after `iniciar_proyecto`, with no path reset,
CLI fallback, integration failure or tolerance changes. `clear` was applied
only to specifically edited function names to refresh MATLAB's cached code.
Python used the project's `.venv`; the user-approved dependency installation
added pypdf, matplotlib and scipy after the sandbox denied network access.
The first Python prototype had a terminal-flow sign error and a NumPy JSON
serialization error; its results remain at the batch root and are superseded
by independent outputs explicitly named above. Early control reconstruction
omitted effective preparation and falsely used a 1e-5 tap tolerance; corrected
audits retain the original effective 0.005 and exposed the two real handoff
failures. These diagnostic corrections never changed physical tolerances.
The first finite-difference fold estimate was also retained before its more
accurate five-point derivative checks. Failed exploratory above-fold solves
remain failed, rather than being counted as successful verification.

`before/` stores every changed pre-existing file; `baseline_hashes.json`
preserves the entry scientific source hashes. `batch6.patch` is relative to
those working files, **not Git HEAD** (the project root has no Git repository).
`patch_validation.json` records scratch application and final hash equality;
`preservation.json` lists the only changed baseline scientific files.
No historical output, case rating or scientific case matrix was modified.
IEEE/Nordic/CIGRE conversion, TRANSPA, the hydro corridor and general control
policy rewrites were excluded.

## Artifacts and readiness for IEEE validation

- `final_04/results_table.csv`, `final_04/voltage_traces.png`,
  `final_04/control_traces.png`, and
  `final_04/independent_final/comparison.png`: tables and plots.
- `final_04/*.mat` and matching JSON: complete scenarios, three constrained
  traces, original unconstrained trace, base PF, point audits and actual
  termination diagnostic. `control_audit_02.json` includes effective control
  tolerances and fresh decisions.
- `author_reference.mat/.json/.log`: unmodified author implementation.
- `final_04/independent_final/`: independent per-point PF/equipment results,
  reference comparisons and precision checks, transition-bracketing solves,
  augmented fold diagnostics, paired load comparisons and pass/fail checks.
- Reproducible MATLAB/Python runners are at the batch root; use a fresh
  destination for new studies. [reproduce.md](reproduce.md) gives the execution order.

**Ready to begin IEEE AC base-case PF alignment:** yes, with an explicit
case version, independent reference and precision gate. The source separation,
fixed-state checks and repaired handoff provide a usable starting workflow.
**Ready to claim IEEE hybrid capability-compliant CPF margins or rank margins
against a validated Beerten installation:** no. Required prior decisions/data
include actual generator ratings/curves and slack handling, enforcement of
original P/Q boxes and branch/voltage limits on the unified path, converter
control-port and capability-envelope semantics, and a declared release rule.
Those unresolved limitations must travel with the benchmark runner; published
PF agreement alone does not remove them.
