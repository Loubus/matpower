# VSC direction-dependent loss contract

Introduced 2026-09-16. Optional equipment metadata; existing cases retain their numerical data and original loss law.

## Measurement port and units

The current and direction are evaluated at the **internal converter AC terminal**, using `PCONV`, `QCONV`, and `VAC_INTERNAL`. `PAC_SET`, returned `PAC`, and DC control schedules are not direction selectors. Power consumed in the transformer/filter/reactor can make a small PCC active power and the internal active power have different signs.

\[
I_c=\frac{\sqrt{P_c^2+Q_c^2}}{S_b|U_c|},\qquad
P_\mathrm{loss}=a+bI_c+c(P_c)I_c^2.
\]

Here powers are MW/MVAr, voltage and current are pu on the system base, `a` is MW, `b` is MW/pu-current and `c` is MW/pu-current². The balance remains

\[
P_c+P_\mathrm{dc}+P_\mathrm{loss}=0.
\]

The passive station losses remain in the transformer/filter/reactor model. The new coefficient selection does not alter those impedances or their loss equations.

## Input API

Keep all existing `vsc` matrix columns unchanged. Optional scalar struct `mpc.vsc_loss` supports:

| Field | Meaning |
|---|---|
| `c_positive` | Quadratic coefficient when internal `PCONV > 0`, i.e. active injection towards the AC system |
| `c_negative` | Quadratic coefficient when internal `PCONV < 0`, i.e. active absorption from the AC system |
| `transition_MW` | Optional nonnegative transition half-width; default zero |

Each value is a finite, nonnegative scalar or a vector with one entry per VSC row, including offline rows. Both coefficient fields are required when metadata is supplied. Scalars broadcast; row and column vectors normalize to columns. Unknown fields, missing coefficients, negative/nonfinite values and incorrect dimensions are rejected.

Without metadata (or with empty metadata), both directions use that row's legacy `LOSS_C`. Equal positive and negative coefficients reproduce the original model. `savecase` preserves the metadata. CPF treats it as fixed equipment data and rejects differing effective base/target characteristics. Selection updates at every residual/state evaluation, including CPF.

## Reversal and differentiability

With zero transition width:

\[
c(P_c)=\begin{cases}c_- & P_c<0,\\(c_-+c_+)/2 & P_c=0,\\c_+ & P_c>0.\end{cases}
\]

This empirical branch model is discontinuous at zero active power when reactive current is nonzero and the two coefficients differ. The mean at exactly zero is an explicit numerical convention, not measured device physics. The analytic Jacobian gives the branch derivative; a Newton or continuation path crossing the jump is not guaranteed to converge.

A strictly positive user-chosen half-width `w = transition_MW` enables a C1 cubic interpolation inside −w < Pc < w, retaining the exact directional coefficients outside that interval:

\[
t=\frac{P_c+w}{2w},\quad h(t)=3t^2-2t^3,\quad
c(P_c)=c_-+(c_+-c_-)h(t).
\]

\[
\frac{dc}{dP_c}=(c_+-c_-)\frac{3t(1-t)}{w},\qquad
dP_\mathrm{loss}=(b+2cI_c)dI_c+I_c^2\frac{dc}{dP_c}dP_c.
\]

The unified Newton/CPF Jacobian includes the final term. Sequential PF uses the same coefficient law at each state update. No transition width is silently chosen. The 2 MW width in the regression is a test setting, not a recommended device calibration. For reversal studies, choose/calibrate a band or use a more detailed converter loss map; do not mistake the sign-only branch model for a universal semiconductor model.

## Physical rationale and reference translation

An IGBT bridge contains semiconductor switches and antiparallel diodes with different conduction drops, switching energies and reverse-recovery characteristics. Changing active power direction changes their conduction duties and loss sharing. Separate empirical coefficients can therefore be justified. Ordinary passive copper losses remain symmetric in current direction. See [Infineon's manufacturer derivation](https://community.infineon.com/t5/Knowledge-Base-Articles/Calculate-IGBT-losses-for-a-SPWM-voltage-source-converter/ta-p/381757), equations 1–14, and [Beerten et al. 2012](https://lirias.kuleuven.be/retrieve/246525), equations 10–11, for the aggregate current-based representation. The quadratic coefficient is a fitted aggregate parameter, not simply transformer resistance. Actual losses also depend on reactive operation, modulation, switching frequency and temperature; sign-only selection is an approximation.

The archived MatACDC 1.0 `calclossac.m` lines 40–50 selects `LossCrec` for positive Pc and `LossCinv` for negative Pc, despite its documented positive-AC-injection convention. Our API avoids translating those labels into physical rectifier/inverter names. To match that archive's executable behavior at 100 MVA / 345 kV:

| Our sign field | Archived field and conversion | Value, MW/pu-current² |
|---|---|---:|
| `c_positive` | `LossCrec × [100/(√3 × 345)]²` | 0.0807953511167122 |
| `c_negative` | `LossCinv × [100/(√3 × 345)]²` | 0.1224112581390464 |

At exactly Pc=0, the archived implementation's two strict sign comparisons set its quadratic contribution to zero. We intentionally use the mean instead, preserving the quadratic loss associated with nonzero reactive current. Consequently the new hard-switch model matches the archive away from Pc=0, but does not reproduce that isolated zero-power convention.

## Implementation and verification

- `matpower/lib/vsc_loss_coefficients.m`: shared selection, validation and derivative.
- `matpower/lib/calc_vsc_losses.m`: evaluates the loss using optional sixth argument `mpc`.
- `runpf_vsc_mtdc.m`, `update_vsc_state.m`: sequential initialization and solved-state update.
- `runpf_vsc_mtdc_unified.m`: residuals and analytic derivatives, reused by CPF.
- `runcpf_vsc_mtdc.m`: validates invariant loss equipment metadata.
- `savecase.m`: persists metadata without changing matrix columns.
- `tests/t_vsc_directional_losses.m`: both PF methods/directions, independent balances, finite-difference derivatives, reversal CPF, legacy equality, invalid inputs and persistence.

Evidence and a separate translated author-case file are in `outputs/vsc_directional_losses_20260916/`. Historical outputs and existing production case parameters were preserved.
