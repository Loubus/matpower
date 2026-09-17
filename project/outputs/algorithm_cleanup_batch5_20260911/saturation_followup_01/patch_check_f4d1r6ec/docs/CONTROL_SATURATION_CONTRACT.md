# Unified PF/CPF physical control saturation

The batch-5 follow-up adopts `vsc_mtdc.psse_control_limit = 'saturate'`
as the default for unified AC/DC/VSC automatic voltage controls. This is a
declared study-policy change authorized after the original batch-5 diagnosis.
The voltage band remains a regulation objective. Exhausting a physical shunt
or tap range is not by itself electrical failure or a voltage-stability limit.

For a supported controller, a point is settled when the full electrical
equations converge and a fresh control pass requests no state change. Each
remaining regulation violation must be classified as an outward request at a
physical bound. Any available legal movement requires another full electrical
correction before acceptance. Cycling, unsupported control modes, unresolved
requests and failed corrections do not qualify as saturation.

Saturation changes no device status, range, deadband, voltage tolerance,
generator/converter rating, capability option or controller eligibility.
The next point evaluates the original voltage rule again. An opposite request
can move the controller away from its bound. Merely returning inside the band
does not cause a reverse movement. Existing explicit study/numerical locks
remain distinct from physical saturation; this policy neither creates nor
releases those locks.

`stop` remains an explicit historical scenario, rejecting an electrically
solved point with unmet regulation. `freeze` retains its existing CPF recovery
semantics and is not the new default. Saved option structures specifying
`stop` continue to request that behavior; loading an old fixture does not
silently migrate it. For the new scenario set:

```matlab
options.vsc_mtdc.psse_control_limit = 'saturate';
```

This contract applies to the unified PF/CPF control-settlement layers. It does
not consolidate the AC-only controller loops, their cycle policies, continuous
shunt sensitivities or broader recovery mechanisms. Other enabled capability
and termination checks retain their existing behavior. A successful configured
run is not certification against every possible operational constraint.

## Full-model authority and reporting

Independently of the policy change, unified PF must not certify tap/shunt
regulation from an auxiliary AC voltage while returning a different full-model
voltage. A settled auxiliary active set is reclassified on the unchanged full
solution for supported direct controls. Auxiliary proposals that change the
active set still require a full electrical solve. Unsupported auxiliary
families do not acquire a new saturation exemption.

PF reports `convergence.converged` for the returned electrical point and
`convergence.overall_success` for the complete PF/control outcome. Its control
report is `convergence.psse_controls`, with an `acceptance` substructure when
the supported direct classification is available. CPF places that acceptance
structure in `convergence.psse_controls` at the accepted point. It records
`policy`, `status`, `accepted`, `saturated`, `regulation_satisfied`, full-model
voltage provenance and violation counts. The existing per-device reports
retain below/above-band and blocked rows instead of declaring them in band.
Regulation counts concern eligible controllers; an explicitly locked or
disabled device is still identified by its separate per-device status and is
not certified as regulated by an aggregate zero count.

CPF emits `PSSE_CONTROL_SATURATED` at accepted saturated samples. These are
informational samples, not additional switching operations or failure events.
No freeze event is emitted for normal saturation. The existing termination
contract still identifies the last accepted point, requested endpoint and
detected nose separately. Under `saturate`, failure to settle a later control
transition is unsuccessful even for a NOSE/FULL request; the legacy orderly
control-stop success convention remains confined to explicit `stop`.

The focused gate is `tests/t_control_saturation_batch5.m`. Original batch-4
inputs and batch-5 stop-policy evidence remain unchanged and independently
replayable. New evidence is in
`outputs/algorithm_cleanup_batch5_20260911/saturation_followup_01/`.
