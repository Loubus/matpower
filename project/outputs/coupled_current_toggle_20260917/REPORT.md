# Optional coupled-current limits

The unified CPF option `vsc_mtdc.coupled_current_limits` accepts 0/1 (or logical false/true). Default: **1**, preserving the previously integrated behavior. Missing or empty options use that default.

```matlab
options = mpoption(options, 'vsc_mtdc.coupled_current_limits', 0); % projected Q
options = mpoption(options, 'vsc_mtdc.coupled_current_limits', 1); % coupled I (default)
```

Augmented capability correction, tangent transport and nose-skip detection remain active in either setting. The chosen formulation is reported in `results.cpf.coupled_current_limits`.

Turning the option off restores the existing projected-Q current-limit treatment, including its saturation margin. It does not discard already saved active-current state: a CPF input with a positive `vsc_current_limit` entry conflicts with the off option and is rejected. Use the original unsaturated base/target cases to compare formulations. The lower-level PF can still replay saved active-current states.

## Verification

MATLAB MCP was initialized with `iniciar_proyecto` and used for all numerical execution. The saved G2-150-MW ULTC/switched-shunt inputs were run with NOSE and initial step 0.1:

| Setting | Last accepted lambda | Termination | NOSE reached |
|---|---:|---|---|
| Missing option (default) | 1.245668942302 | limit_induced_turn | Yes |
| Explicit on | 1.245668942302 | limit_induced_turn | Yes |
| Explicit off | 1.245549498833 | turn_localization_failed | No |

The default and explicit-on traces match exactly. Off activates projected capability limits and creates no coupled-current state. The off run remains numerically unable to localize the turn; `success=false`, `nose_detected=false` and `requested_endpoint_reached=false` accurately report that result. This is not a MATLAB integration failure. All 17 independent physical checks pass on the accepted points of each run; that does not turn the off run into a successful NOSE solve. No numerical warnings were returned.

All **18 toggle regression checks** passed: option registration/default, on/off selection and reporting, retained turn detection, actual activation/projection, invalid-value rejection and saved-state conflict rejection. Results and MAT snapshots are in `final/`.

The first off trial exposed a pre-existing fallback reference to a sibling function's local `z`. Repeated projection can produce an unchanged candidate, which exercises that fallback. It now maps the shared carried tangent by variable identity. A separate initial test-harness assumption about old option structures was also corrected. Initial artifacts remain preserved; the complete verification is in `final/`.

## Files

- `matpower/lib/mpoption.m`: registered toggle and help.
- `matpower/lib/runcpf_vsc_mtdc.m`: validated toggle, activation gate, resolved-setting report, saved-state conflict check and tangent fallback correction.
- `tests/t_cpf_current_toggle.m`: reusable regression accepting base, target, options and a new output directory.
- `docs/CPF_LIMIT_CONTINUATION.md`: usage and scope.

Source snapshots and diffs are retained here. Case parameters and historical scientific outputs were not changed.
