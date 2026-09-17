# Experiment A: coupled current-limited VSC control

## Scope and isolation

The saved 150 MW generator study cases/options are loaded directly from `outputs/ultc_swshunt_g2_150mw_20260916/main_run.mat`. Both the 0.1 and 0.05 CPF step runs retain FULL mode and all original tolerances, controls, ratings, setpoints, iteration limits and failure policies. No case parameter is edited. Only new, uniquely named solver copies are called: `exa_psse`, `exa_cpf`, `exa_pf`. All helpers not copied continue to resolve to the existing project implementation. The production source and historical outputs are preserved.

This isolates proposal 1: capability re-correction still solves at **fixed lambda**, with the same Newton damping and iteration bound as production. The normal CPF corrector remains augmented, as it already was. Proposal 2 (continuation inside limit transitions) is not added here.

## Implemented equation

For a pure current violation under existing `preservar_p` priority, replace the converter's AC Q control row with

\[
g_I=\frac{P_c^2+Q_c^2}{S_B^2 U_c^2 I_{\max,B}^2}-1=0,
\qquad I_{\max,B}=\frac{S_N}{S_B}.
\]

The implementation evaluates exactly the solver's actual bridge current (`eval.iac`), including transformer/filter/reactor network states. It uses the system-base current, consistent with the existing converter loss function. Its analytic Jacobian row is

\[
\mathrm d g_I=\frac{2(P_c\mathrm dP_c+Q_c\mathrm dQ_c)}{S_B^2U_c^2I_{\max,B}^2}
-\frac{2 I_c^2}{U_c I_{\max,B}^2}\mathrm dU_c.
\]

Existing analytical `dPac`, `dQac` and `dUc` matrices supply the derivatives. The replacement occurs after normal PCC rows are assembled and before the bridge/DC rows; no DC voltage or bridge-balance row is removed. VSC 2 therefore changes from AC voltage control to current-limited Q freedom while its DC voltage remains fixed and its real power still follows DC balance and losses.

The limit equality is active in every residual and Jacobian: fixed-lambda correction, CPF augmented correction, tangent construction and subsequent control handoffs. Active current limits are carried as explicit case metadata; both context-cache and active-set signatures include this metadata. The original P/Q orders are retained, but Q is no longer imposed on an active current branch.

## Changes deliberately accompanying equation replacement

The production 0.1% Q clipping margin is not used for current-limited modes, because Q is now a solved variable and the physical equality is the nameplate current limit. This is a documented algorithm change, not an equipment-rating change. No replacement physical derating is introduced. Other converter projection policies and generator/control logic are unchanged.

An explicit guard rejects a second internal-voltage or dispatch-ceiling violation while the current equation is active; this prototype cannot enforce two simultaneous independent boundaries with one released control. Such rejection is logged separately. The prototype does not implement current-limit release back to the requested voltage/Q control. The relevance of this restriction must be assessed on the actual traced branch; it cannot establish correctness for arbitrary returning or multi-converter branches.

## Evidence to check

- Both complete attempted CPF runs, with raw success scope and FULL completion distinguished.
- All accepted PCC schedules, station phasors, AC/DC balances, bridge loss balance, current and internal-voltage limits.
- Generator P/Q capability and ULTC/shunt discrete state acceptance.
- Independent central differences of the replaced analytic current row.
- Turn detection from accepted lambda/tangent arrays, separately from the unchanged raw FULL-mode nose event flag.
- Failure stage and rejected-candidate metadata; a numerical failure is not a proof of physical infeasibility.
