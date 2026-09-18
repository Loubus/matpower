# CPF study endpoint decision — 2026-09-18

The user selected studies through the **first loading maximum** (`cpf.stop_at = 'NOSE'`). Further lower-branch recovery work is deferred. Keep the existing coupled converter-current equation, generator capability curves, physical tap/shunt saturation and declared dispatch policies.

The Beerten nonslack scenario already selects NOSE. The configurable Beerten runner now defaults to NOSE as well, including its no-argument preset. The explicitly named FULL preset continues to request FULL, preserving diagnostic access. Saved cases, options and historical results are unchanged.

## Validated result and interpretation

For `beerten_constant_pq_nonslack_dispatch`, the corrected NOSE runs at initial steps 0.10 and 0.05 reach λ approximately 1.245668945, corresponding to total demand approximately **463.96055 MW** under `PD = 165 + 240 λ` MW. The solver classifies this maximum as `limit_induced_turn`; it is not a demonstrated smooth saddle-node or validated dynamic stability limit.

Reaching NOSE does not certify every point as operationally acceptable. Continue to report first bus-voltage, thermal or other operating restrictions separately from the mathematical first maximum. These results use the current nonslack dispatch and are not historical batch-6 margins.

## Included fixes and tests

- Solved generator capability contacts, including exact G2 P saturation at λ = 11/24 and retention of voltage regulation until its Q boundary.
- Local, continuous converter-current release with state continuity and forward feasibility checks; no remote voltage-restoration branch jump or forced loading-tangent sign.
- Persisted current-limit mode provenance and incremental-policy state handling.
- 146/146 event/study checks, 23/23 local release checks and 330/330 existing VSC checks passed on the solver implementation. A fresh NOSE closure check accompanies this commit.

See [the verified report](../outputs/cpf_branch_preserving_release_20260918/REPORT.md) and [the closure verification](../outputs/cpf_nose_closure_20260918/verification.json).

## Deferred limitations

FULL continuation of this scenario still stops near λ = 0.60305 during VSC 3 radial capability settlement. The last accepted point converges. This is an unresolved saturation transition, not a collapse certificate. Its [diagnosis](../outputs/cpf_endpoint_diagnosis_20260918/REPORT.md) is retained; no proposed radial/complementarity redesign was implemented.

Q-first generator increasing-P boundary following also remains outside this closure. The validated scenario reaches G2's P maximum first. The configurable runner and other scenarios must retain their own declared control/dispatch assumptions and acceptance checks.
