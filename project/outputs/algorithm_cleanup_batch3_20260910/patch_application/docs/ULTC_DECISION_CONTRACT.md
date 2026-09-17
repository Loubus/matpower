# ULTC decision contract — batch 3

The shared operation is a pure, single voltage-sampling pass. It chooses an
adjacent legal tap and its corresponding RAW winding value. It does not solve
electrical equations, accept a candidate, change limits, correct CPF, roll back
a failed solve, create/release locks, or resolve cycles.

## Inputs and output

`mp.psse_xfmr_tap_decision(state, vm, eligible)` takes the state built by
`psse_xfmr_states`, voltages indexed by that state's bus rows, and an explicit
logical eligibility mask supplied by the calling policy. It returns full-size
RAW and per-unit tap vectors. Nonselected devices retain their input values.

- State construction owns ACTAPS, transformer/winding and branch status,
  COD=1, nonzero CONT, valid regulated bus, NTP>=2, supported CW=1/2,
  compensation exclusion and supported TAB correction. It owns bus/branch
  mapping, direction conventions, grid conversion, sorting and initial snapping.
- The decision intersects the caller's mask with `controllable` and a positive
  regulated-bus index. It reads all devices from the same solved voltage vector
  and original tap vector, in state-row order. No sequential electrical update
  or priority between transformers occurs inside the pass.
- Voltage below `min(VMI,VMA)-vtol` requests raising voltage; voltage above
  `max(VMI,VMA)+vtol` requests lowering it. Both boundaries are inclusive.
  Multiply that request by the adapter's `side_sign`. This preserves signed
  CONT semantics, including reverse-action own-terminal declarations; it does
  not infer topology or silently replace declared directions with sensitivities.
- Choose the first sorted tap strictly above `current+1e-9`, or the last tap
  strictly below `current-1e-9`. Empty grids and outward requests at either bound
  retain state. RAW values use the same selected index; no interpolation occurs.
- `psse_xfmr_update` synchronizes branch TAP, WINDV and TAB-adjusted R/X. It
  remains outside the decision. No ratings or tolerances change in this batch.

## Explicitly preserved caller differences

| Concern | AC PF / AC CPF controller | Unified AC/DC direct pass |
|---|---|---|
| Eligibility | Excludes locked rows without clearing `controllable`; measures locked voltages separately | Clears `controllable` for locked rows before classification; locks combine inherited transformer flags and explicit solver mask |
| State lifetime | Retains iterations, visit history, best score and original base tap | Reconstructs state on each pass; outer solver owns settlement history |
| Initial normalization | `needs_initial_update` can request an electrical rebuild even without a subsequent move | Serializes initialized state on every pass; actual array changes drive report |
| Saturation report timing | Classifies the current, electrically solved tap before proposing a move | Reports final candidate bound using the pre-move voltage; this is provisional until solver re-solves |
| Cycling | Scores violations, their sum and distance from base tap; retains best visited state; may probe one step toward base | Direct pass has no cycle detector; outer unified PF/CPF retains existing detection/auxiliary recovery |
| Iteration limit | MXTPSS and unresolved-violation failure are checked here | Outer solver owns iteration/failure handling |
| Numerical rejection | Existing CPF replay guard owns candidate splitting, rollback and rejection diagnostics | Outer unified solver owns correction/rejection and recovery |
| Physical limit recovery | Saturation itself does not create a lock in the decision | Existing explicitly configured selective-freeze scenario can lock blocked devices in CPF; not enabled by this extraction |

These differences are unresolved scientific-policy choices, not a reason to
silently promote either caller to the other's behavior. The common mask is
explicit so callers retain their policy. Source inspection and acceptance tests
cover both paths; the helper is not an alternative controller implementation.

## Isolated prerequisite repair

The pre-extraction test found that unified `apply_control_lockout` erased locks
already loaded by `psse_xfmr_states`. Consequently a study-locked or numerically
rejected transformer moved on the next direct pass. The ULTC adapter now unions
these inherited flags with the unified mask before classifying/selecting. Study
labels and rebuild-rejection diagnostics retain their original provenance.
No automatic lock, release rule or switched-shunt behavior is added.

## Acceptance coverage

`t_ultc_acceptance_batch3` reuses the existing two-bus fixture and preserved
three-winding TAB RAW fixtures. It exercises both decision entry points before
extraction: terminal orientations and signed CONT; remote direction and solved
voltage response; nonconsecutive IDs and reordered measurements; CW=2 kV/TAB
conversion; three-winding CW/TAB; disabled conditions; deadband edges; both
bounds; declared and numerical locks; simultaneous interacting devices and
metadata permutation; an actual AC cycle and direct-pass reversal; numerical
replay rollback. Electrical checks use independent nodal balance at 1e-8 pu;
interface checks retain 1e-10 precision.

`t_mpxt_psse` retains its original detailed interface and recovery tests,
including three-winding fallback mapping, off-grid initial snapping, iteration
failure, CPF warmstart cycle reset and split replay. `t_psse` supplies the full
RAW import suite. The two preceding physical gates, full VSC/electrical/control
regressions and short Beerten PF/CPF evidence remain required. Batch 3's report
records results, skips and limits of that evidence.
