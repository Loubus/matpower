# VSC-MTDC Architecture Decision

## Decision

Project VSC-MTDC workflows use the PSS/E-aware entry points:

- `runpf_psse` for PF.
- `runcpf_psse` for CPF.

The explicit VSC-MTDC equations remain MATPOWER AC/DC/VSC equations. They are
not intended to be a full replica of a PSS/E VSC HVDC device model. The PSS/E
entry points provide the project orchestration layer, including PSS/E-aware
control handling where available.

## Consequences

- Standard `runpf` remains unchanged.
- Standard `runcpf` rejects explicit VSC-MTDC cases instead of silently running
  an AC-only CPF that ignores `busdc`, `branchdc` and `vsc`.
- `runpf_vsc_mtdc` and `runcpf_vsc_mtdc` remain lower-level solver entry points
  used by the PSS/E wrappers and by focused solver tests.
- Sequential VSC-MTDC CPF under `runcpf_psse` uses `runpf_psse` for the AC
  subproblem.

## API Boundary

The supported project/user entry points are `runpf_psse` and `runcpf_psse`.
The lower-level VSC-MTDC solver entry points, `runpf_vsc_mtdc` and
`runcpf_vsc_mtdc`, remain callable and documented for direct solver use and
focused tests.

The public VSC-MTDC data and audit helpers are:

- `idx_busdc`
- `idx_branchdc`
- `idx_vsc`
- `has_vsc_mtdc`
- `makeGdc`
- `make_vsc_hvdc_dispatch_target`
- `check_capability_limits`
- `check_vsc_capability`
- `check_gen_capability`
- `vsc_capability_curve`
- `gen_capability_curve`

The following functions are implementation details, even though they live in
`lib/` while the model is still evolving:

- `runpf_vsc_mtdc_unified`
- `apply_vsc_ac_model`
- `calc_vsc_losses`
- `solve_vsc_dc_pf`
- `update_vsc_state`
- `enforce_vsc_capability_active_set`
- `make_cpf_gen_dispatch_target`
- `vsc_capability_geometry`
- `vsc_capability_params`
- `vsc_capability_policy`
- `mp.psse_unified_control_update`

Internal dispatch operations whose names begin with `__`, such as `__setup`,
`__mismatch`, `__jacobian` and `__cpf_system`, are not public API. They are
reserved for internal solver composition and focused derivative tests.

## Non-goals

- No `toggle_vsc_mtdc` userfcn extension path is introduced for this phase.
- No OPF capability-curve constraints are introduced.
- No attempt is made to rename the MATPOWER VSC model as a native PSS/E VSC
  HVDC implementation.
