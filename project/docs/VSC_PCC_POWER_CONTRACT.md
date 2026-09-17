# VSC PCC power and full-station capability contract

Effective 2026-09-16. This is a deliberate change of the AC power port. Existing
case numbers remain unchanged; running an old case now interprets its AC power
orders at the PCC. Historical result files are not migrated or rewritten.

## Public quantities

`PAC_SET`, `QAC_SET`, returned `PAC`, `QAC`, and public
`vsc_state.pac/qac` refer to station injection into the AC grid at the PCC.
Positive P/Q means injection. They are the negative transformer sending-end
flows, not net bus injection, and therefore exclude co-located loads and generators.
Units are MW/MVAr. `VAC_SET` and `VAC_PCC` are PCC voltage magnitudes.

New output columns `PCONV=45`, `QCONV=46` and state fields `pconv/qconv`
refer to the internal converter terminal. Existing columns 1–44 keep their indices.
The internal proxy generator or negative load still injects PCONV/QCONV.
Internal Newton/fixed-point variables named `pac/qac` remain private converter
terminal variables; they are not the public output column contract.

`PDC` is positive into the DC network. `PLOSS` is bridge loss only:

\[
P_c+P_{dc}+P_{loss}=0,\qquad
P_c-P_s=P_t+P_r+S_bG_f|u_f|^2.
\]

The loss polynomial uses internal terminal current
\(I_c=|P_c+jQ_c|/(S_b|u_c|)\), including terminal charging current if present.
`PTR_LOSS` and `PREACTOR_LOSS` are now populated from solved branch flows in
both PF methods. Filter conductance loss is separate and follows the equation above.

PQ fixes PCC P/Q; PV fixes PCC P and voltage; Q fixes PCC Q with active power
from the DC balance; V fixes PCC voltage with active power from the DC balance.
The DC reference retains VDC control when AC voltage support is saturated.
It must never receive a fixed PAC order as a substitute for DC balance.
If it cannot balance the DC system within its limits, local projection alone
cannot restore feasibility; enforcement must fail or the study must provide redispatch.

## One station capability formulation

All station quantities use one selected power base and consistent AC voltage bases.
With no pi charging or transformer phase shift, define
\(z_t=R_t+jX_t\), \(z_r=R_r+jX_r\), \(y_f=G_f+jB_f\), and
\(s_s=(P_s+jQ_s)/S_b\). Positive station current points towards the grid:

\[
i_s=\frac{s_s^*}{u_s^*},\quad
u_f=u_s+z_ti_s,\quad
i_c=i_s+y_fu_f,\quad u_c=u_f+z_ri_c.
\]

Thus

\[
A=1+y_fz_t,\ B=y_f,\ D=1+z_ry_f,\ E=z_t+z_rA,
\qquad i_c=Ai_s+Bu_s,\quad u_c=Du_s+Ei_s.
\]

Taking the PCC as angle reference, the actual constraints are

\[
\left|A\frac{s_s^*}{U_s}+BU_s\right|\le I_{c,max},\qquad
\left|E\frac{s_s^*}{U_s}+DU_s\right|\le U_{c,max}.
\]

`vsc_station_map` also includes both branch pi shunts and the existing transformer
phase shift. `vsc_station_capability` evaluates affine phasors directly and solves
quadratic intervals for projection. It does not replace resistance by reactance
magnitude or divide by zero/tiny station impedance. Scalar legacy geometry calls
are routed through the same engine as a filter-free reactive station.

PCC P/Q together with PCC voltage is now consistent. Converter current generally
is **not** \(|S_s|/U_s\) when filter or charging current exists; the station mapping
is essential. The formulation is exact for the represented linear station at the
given PCC voltage. PF/CPF must recorrect and recheck limits after voltage changes.

## Limits and policies retained

- `Snom`/`Smax` remains the converter current base: Imax=1 pu on that base.
  With no metadata, the minimum positive station branch MVA rating is the fallback.
  This is a rating assumption, not separate transformer and reactor thermal enforcement.
- The dispatch ceiling \(|P_s|\le Snom\) remains in addition to current/voltage limits.
- `VconvMax` remains the configured maximum; the fallback is 1.15 pu. There is
  still no minimum internal-voltage limit. This change does not invent a new rating.
- `preservar_p` holds PCC P when a feasible Q interval exists; `radial` follows
  the PCC power-factor ray. Empty feasible sets and rays are explicit errors.
- Exact zero impedances work in capability calculations. The explicit PF topology
  still requires nonzero transformer/reactor impedances; ideal branch contraction
  is outside this change. Existing small computational impedances are retained.
- The sequential method can require more than its default 20 iterations for
  filtered, high-impedance stations. Its defaults and tolerances are unchanged.

Capability plotting diagnostics now include complex `current_center` and
`voltage_center` in MW+jMVAr. A single Q-axis center is insufficient for the
general resistive station. The legacy symmetric `pFactible` diagnostic is NaN;
feasibility is determined by the full constraints and returned Q interval.

## Historical compatibility

Pre-migration outputs contain internal PAC/QAC. Do not feed those tables directly
to the new PCC capability audit or splice them into a new CPF trajectory. Re-solve
the source case, or explicitly obtain PCC flows from the saved transformer branches.
No automatic reinterpretation can recover missing terminal information reliably.

Source references: Beerten, Cole and Belmans (2010), DOI
[10.1109/PES.2010.5589968](https://doi.org/10.1109/PES.2010.5589968);
Beerten et al. (2012), section II-B, equations 12–24, DOI
[10.1109/TPWRS.2011.2177867](https://doi.org/10.1109/TPWRS.2011.2177867).
The MatACDC 1.0 author case data and manual remain archived under
`outputs/beerten_validation_batch6_20260911/reference/`.
