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
- `runcpf_vsc_mtdc` still owns unified CPF orchestration, but its safest pure
  helper seams are now separated from the main continuation loop.

## API Boundary

The supported project/user entry points are `runpf_psse` and `runcpf_psse`.
The lower-level VSC-MTDC solver entry points, `runpf_vsc_mtdc` and
`runcpf_vsc_mtdc`, remain callable and documented for direct solver use and
focused tests.

`runcpf_vsc_mtdc` is not a project/user orchestration layer. It is the
lower-level unified CPF solver. Its public behavior includes the current CPF
trace, event order, event payloads, maximum-lambda behavior, final matrices, and
focused internal derivative-test dispatch. Those outputs are protected by
baseline-vs-after comparisons when the implementation is decomposed.

The CPF result metadata field `cpf.active_set_failure_policy` is a reporting
contract for unified active-set semantics. It names each enabled stage's
declared policy and observed outcome without changing PSS/E, capability, HVDC
derating, `NOSE`, or `FULL` trace behavior.

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
- `mp.psse_unified_active_set`
- `gen_capability_default_smax`
- `gen_capability_metadata_or_option_value`
- `vsc_mtdc_cpf_add_missing_event_fields`
- `vsc_mtdc_cpf_append_event`
- `vsc_mtdc_cpf_is_duplicate_event`
- `vsc_mtdc_cpf_is_duplicate_recovery_event`
- `vsc_mtdc_cpf_vsc_capability_event`
- `vsc_mtdc_cpf_gen_capability_event`
- `vsc_mtdc_cpf_hvdc_derating`
- `vsc_mtdc_cpf_policy_state`

Within `runcpf_vsc_mtdc`, the active-set stage runner and snapshot/restore
helpers are also implementation details. They intentionally remain nested
because they restore solver workspace state such as `mpcb`, `mpct`,
`cpf_policy_state`, context objects, and recorded-event indices.

The following responsibilities remain inside `runcpf_vsc_mtdc` by design after
the CPF-CX-002 decomposition checkpoint:

- the accepted-point continuation loop
- fixed-lambda solve/re-correct timing
- mutable policy state ownership
- policy-specific active-set freeze, stop, and recovery decisions
- actual tangent rebuilds after active-set invalidation
- context rebuild timing
- event append timing
- regular CPF `FULL` target-lambda closure
- profiling wrappers
- internal dispatch

Internal dispatch operations whose names begin with `__`, such as `__setup`,
`__mismatch`, `__jacobian` and `__cpf_system`, are not public API. They are
reserved for internal solver composition and focused derivative tests.

## Non-goals

- No `toggle_vsc_mtdc` userfcn extension path is introduced for this phase.
- No OPF capability-curve constraints are introduced.
- No attempt is made to rename the MATPOWER VSC model as a native PSS/E VSC
  HVDC implementation.
