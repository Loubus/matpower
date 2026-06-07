# VSC-MTDC Capability Enforcement: Next Implementation Steps

Status: internal design note. Public user/developer reference material for the
implemented VSC-MTDC commands, case fields, options and helper APIs lives in
the MATLAB help text and Sphinx reference manual pages.

## Scope

This note documents the next implementation work for TESIS-style VSC-MTDC
capability handling in PF/CPF, without OPF or optimization. It focuses on four
items:

1. Precise VSC capability event location in CPF.
2. Explicit VSC saturation policy.
3. Active VSC capability enforcement in PF.
4. Per-converter capability parameters.

The current implementation already has VSC capability geometry, post-solve
auditing, CPF active-set enforcement, and basic event reporting. The remaining
work is mainly to make the behavior more exact, more explicit, and easier to
validate.

## Current Behavior Summary

The CPF enforcement loop detects a saturated converter after solving a CPF
point. It computes a projected saturated point with `vsc_capability_curve`,
changes the converter AC control mode, and re-corrects the CPF point at the
same loading level.

Important consequence:

- The point stored in `res.cpf.vsc` after the event is the re-corrected point.
- The original candidate point that violated the capability curve is not
  currently stored.
- The instantaneous projected point is not necessarily identical to the final
  re-corrected point, because the full AC/DC equations are solved again after
  the active-set change.

In the Beerten ULTC/switched-shunt CPF, VSC 2 saturated in this way:

- Without VSC enforcement, the voltage-control trajectory crossed the
  capability curve.
- The enforcement changed the converter from AC voltage control to fixed-Q
  control.
- The re-corrected point stayed inside the feasible capability region.

## 1. Precise VSC Capability Event Location in CPF

### Problem

At the moment, the VSC capability event is detected at a solved continuation
point. This is enough to enforce the limit, but it does not locate the exact
crossing of the capability margin:

```text
margin(lambda) = 0
```

This makes diagnostics and plots less clear. The first stored point after the
event is already re-corrected, while the true violating candidate may be
between CPF steps.

### Target Behavior

CPF should locate the first loading level where a converter reaches the
capability boundary, before applying the active-set change.

For each active converter, define a signed margin:

```text
g_k(lambda) = minimum capability margin for converter k
```

For a Q upper-limit saturation, for example:

```text
g_k(lambda) = Qmax(P_k(lambda), V_k(lambda)) - Q_k(lambda)
```

The event occurs when:

```text
g_k(lambda) = 0
```

with `g_k > 0` inside the capability region and `g_k < 0` outside.

### Proposed Implementation

Add a VSC capability monitor that can evaluate, for each converter:

- current `P`, `Q`, `V`;
- selected capability parameters;
- signed margin;
- active limiting surface;
- projected saturated point.

Then update CPF event handling so that, when a sign change is detected between
two continuation points, the code refines the event location. A simple first
implementation can use interpolation or bisection at fixed lambda. A later
version can integrate more deeply with the existing CPF callback/event
machinery.

The event record should store:

```text
converter index
lambda_event
P_candidate, Q_candidate, V_candidate
margin_candidate
active_limit
projection_mode
P_projected, Q_projected
from_ac_mode, to_ac_mode
final P, Q, V after re-correction
```

### Candidate Files

- `lib/runcpf_vsc_mtdc.m`
- `lib/check_vsc_capability.m`
- `lib/vsc_capability_curve.m`
- `lib/vsc_capability_geometry.m`
- `lib/t/t_vsc_mtdc.m`

### Validation

Add tests that verify:

- the VSC capability event lambda is close to the zero of the margin;
- the event record includes candidate, projected, and final re-corrected
  values;
- the final saved CPF point is inside the capability region;
- the event is reproducible with adaptive and non-adaptive CPF steps.

## 2. Explicit VSC Saturation Policy

### Problem

The current behavior depends on a default mode selection:

- DC voltage slack and DC droop converters default to `preservar_p`.
- Other converters default to `radial`.

This is technically implemented, but the policy should be explicit and
documented because the physical interpretation changes:

- `preservar_p` keeps active power and clips reactive power.
- `radial` scales `P` and `Q` together, preserving power factor.

In the Beerten test, VSC 2 was a DC voltage slack converter, so the projection
used `preservar_p`. It did not preserve power factor.

### Target Behavior

Make the saturation policy a documented and test-covered part of the VSC-MTDC
contract.

Recommended default policy:

```text
DC_MODE = VDC or DROOP:
    preserve P and clip Q when feasible

DC_MODE = PDC:
    use configured policy; default can remain radial unless a better physical
    rule is chosen

AC_MODE = V or Q:
    if P is preserved, switch to fixed Q

AC_MODE = PV or PQ:
    switch to fixed P-Q if P changes or was already fixed
```

This matches the current active-set behavior:

```text
if Psat changes:
    AC_MODE -> PQ
else:
    AC_MODE -> Q
```

### Proposed Implementation

Add a small policy resolver, for example:

```matlab
policy = vsc_capability_policy(vsc_row, mpopt, converter_index)
```

It should return:

```text
projection_mode
target_ac_mode_if_saturated
reason
```

The allowed projection modes should be explicit:

```text
preservar_p
radial
```

Optional future modes can be added later:

```text
preservar_q
preservar_pdc
min_norm
```

### Candidate Files

- `lib/vsc_capability_curve.m`
- `lib/vsc_capability_geometry.m`
- `lib/runcpf_vsc_mtdc.m`
- `lib/check_vsc_capability.m`
- `lib/t/t_vsc_mtdc.m`

### Validation

Add tests that verify:

- DC slack converters use `preservar_p` by default;
- droop converters use `preservar_p` by default;
- fixed-PDC converters follow the configured policy;
- `radial` preserves `Q/P`;
- `preservar_p` preserves `P` and clips `Q`;
- the resulting AC mode is `Q` if `P` is preserved and `PQ` if `P` changes.

## 3. Active VSC Capability Enforcement in PF

### Problem

CPF already has active VSC capability enforcement. PF currently needs a
similarly explicit solve-check-update loop if we want base PF runs to obey the
same TESIS-style limits.

Post-solve auditing is useful, but it does not change the solved operating
point. For consistent behavior, PF should be able to:

```text
solve PF
check VSC capability
change saturated VSC modes/setpoints
solve again
repeat until stable
```

### Target Behavior

Add an optional PF enforcement loop controlled by options such as:

```text
vsc_mtdc.capability_enforce = 1
vsc_mtdc.capability_pf_max_it = N
vsc_mtdc.capability_vsc_smax = ...
vsc_mtdc.capability_vsc_mode = ...
```

When enabled, PF should return a solution where all enforced VSCs are inside
their capability curves, or return a clear failure/report if the active set
does not converge.

### Proposed Implementation

Create a shared helper used by both PF and CPF, for example:

```matlab
[mpc_next, report] = enforce_vsc_capability_active_set(mpc, results, opt)
```

It should:

- run the same capability calculation used by CPF;
- update `AC_MODE`, `PAC_SET`, and `QAC_SET` as needed;
- report changed converters and active limits;
- stop when no converter changes mode/setpoint.

PF wrappers can then perform:

```text
for it = 1:max_it
    solve PF
    enforce VSC capability
    if no changes, stop
end
```

### Candidate Files

- `lib/runpf_vsc_mtdc.m`
- `lib/runpf_vsc_mtdc_unified.m`
- `lib/runpf_psse.m`
- `lib/check_capability_limits.m`
- `lib/check_vsc_capability.m`
- `lib/runcpf_vsc_mtdc.m`
- `lib/t/t_vsc_mtdc.m`

### Validation

Add tests that verify:

- PF detects a VSC outside its curve;
- PF switches the saturated VSC to the expected mode;
- PF re-solves and returns a point inside the capability curve;
- PF reports failure when the active set cannot converge within max
  iterations;
- CPF and PF use the same projection policy for the same converter state.

## 4. Per-Converter Capability Parameters

### Problem

Current tests often use a global nominal value such as:

```text
vsc_mtdc.capability_vsc_smax = 250
```

This is useful for controlled experiments, but real VSC capability curves
should be parameterized per converter.

Different converters may have different:

```text
Snom
Imax
Vconv,max
Pdc,max
station transformer/reactor impedance
thermal ratings
```

### Target Behavior

Capability evaluation should use each converter's own base and limits. Global
options can remain as fallbacks or test overrides, but the preferred behavior
should be per-converter data.

All P-Q calculations should be performed internally in p.u. on the converter's
own MVA base, then converted back to MW/MVAr for MATPOWER result matrices.

### Proposed Data Sources

Use this priority order:

1. Explicit per-converter capability metadata in the case.
2. Existing VSC station ratings, such as transformer/reactor ratings, when
   physically meaningful.
3. Global `mpopt.vsc_mtdc` overrides, for tests and studies.
4. Safe documented defaults only when no better data exists.

Possible case metadata shape:

```matlab
mpc.vsc_capability = struct( ...
    'Snom',      [...], ...
    'Imax',      [...], ...
    'VconvMax',  [...], ...
    'PdcMax',    [...], ...
    'mode',      { ... } );
```

The implementation should still support scalar options for convenience:

```text
capability_vsc_smax = 250
capability_vsc_vmax = 1.15
capability_vsc_mode = 'preservar_p'
```

but should also accept vectors or per-converter structs.

### Candidate Files

- `lib/vsc_capability_curve.m`
- `lib/vsc_capability_geometry.m`
- `lib/check_vsc_capability.m`
- `lib/runcpf_vsc_mtdc.m`
- `lib/runpf_vsc_mtdc.m`
- `lib/runpf_vsc_mtdc_unified.m`
- VSC case files under `data/`
- `lib/t/t_vsc_mtdc.m`

### Validation

Add tests that verify:

- two converters with different `Snom` have different p.u. capability curves;
- the same MW/MVAr point can be inside one converter curve and outside another;
- vector/scalar option handling is deterministic;
- case metadata overrides global defaults when both are present;
- station reactance is converted to the converter's own MVA base.

## Open Design Decisions

### Releasing Saturated VSCs

The current active set is effectively one-way: once a converter saturates, it
stays in the saturated mode. A future enhancement could allow release if the
capability curve expands and the converter has enough margin to return to its
original control mode.

This should not be implemented implicitly. It needs a separate policy because
it can introduce chattering:

```text
release only if margin > hysteresis
release only after N stable CPF steps
never release during the same CPF run
```

### Exact Meaning of Active Power Preservation

For DC slack converters, preserving AC `P` is a practical local rule, but the
full AC/DC solve may still change final `P` slightly after re-correction due to
losses, DC balance, and network equations. Documentation should distinguish:

```text
projected P/Q from the local capability calculation
final P/Q after the fixed-lambda re-correction
```

## Suggested Implementation Order

1. Add event diagnostics and precise candidate/projected/final storage.
2. Extract and document the VSC saturation policy resolver.
3. Add PF active-set enforcement using the shared helper.
4. Add per-converter capability metadata and vectorized options.
5. Add canonical plotting utilities for VSC capability traces and events.

## Minimal Acceptance Checklist

Before considering this complete:

- `t_vsc_mtdc(0)` passes.
- CPF VSC capability events include candidate, projected, and final values.
- PF can enforce at least one VSC capability violation and re-solve.
- Per-converter `Snom` and `VconvMax` affect the capability curve as expected.
- Plots can show the candidate outside point, projection, final point, and
  trajectory without auxiliary no-enforcement runs.
