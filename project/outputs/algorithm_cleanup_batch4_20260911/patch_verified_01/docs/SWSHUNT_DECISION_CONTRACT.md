# Switched-shunt shared decision contract

Batch 4 shares only group voltage requests and adjacent discrete BINIT selection.
It does not make the AC and unified AC/DC control loops equivalent.

## Inputs and outputs

`mp.psse_swshunt_group_action(state, members, v, eligible)` takes the state from
`psse_swshunt_states`, a column vector of indices in one regulated-bus group,
one solved voltage sample and an explicit row eligibility mask. It returns a
direction, weighted voltage target and the eligible members voting in that
direction. Ineligible rows neither vote nor move, including rows locked after
the group was constructed. No eligible request returns zero, NaN and empty.

Each band is ordered without changing its endpoints. NaN bands abstain.
MODSW=1 requests the nearest violated edge strictly outside VCTOLV; MODSW=2
requests the midpoint strictly outside VCTOLV. Weighted positive and negative
errors use literal RMPCT/100. An exact nonzero tie selects upward. Only voters
on the winning side are returned. Their target is weighted by literal RMPCT.
The state constructor retains ownership of default/invalid RMPCT handling.

`mp.psse_swshunt_discrete_next(state, k, direction)`, with direction +1 or -1,
chooses the nearest current
grid entry, then the next strictly higher/lower entry separated by more than
1e-9 MVAr. At a bound (or empty grid) it retains BINIT. The grid is the existing
sorted admissible grid from RAW blocks, including separate inductive and
capacitive cumulative steps through zero. It is not an enumeration of arbitrary
block combinations. Inputs are constructor-normalized; initial off-grid
normalization belongs to the constructor. This helper does not alter limits,
the voltage tolerance, RAW data, bus BS, locks or convergence flags.
The empty-grid guard retains unified defensive behavior; normal constructor
output always includes zero, so this is outside the shared operational domain.

## Adapter responsibilities and intentional differences

| Behavior | AC | Unified AC/DC |
|---|---|---|
| Voltage source | Solved data-model bus order | Solved bus values mapped by external identity |
| Simultaneous decisions | One voltage sample for all groups | One voltage sample for all groups |
| Continuous step | Prior group dV/dB when available; quarter-span fallback | Quarter-span step every direct pass |
| Candidate screening | Existing plain AC PF probe, Q-limit enforcement disabled for probe, voltage sanity range | Outer monolithic solver corrects provisional candidate |
| Cycling | Persistent BINIT history and best visited score | Outer solver owns settlement/recovery; direct pass is memoryless |
| Lock mask | No unified-mask API on AC shunt adapter | Explicit `psse.control_lockout.swshunt` suppresses voting and movement |
| Reporting | Pre-move solved voltage and cycle history | Pre-move voltage with post-move saturation; provisional until corrected |

Continuous sensitivities, clamps, screening, report timing, initial normalization,
fixed-BS/BINIT synchronization, MXTPSS, release/freeze rules and rollback remain
in their existing layers. Group metadata describes the constructed group, not
the current eligible subset. A physical bound does not create a numerical lock.
Caller removal of a unified lock permits a later request; this is no new
automatic release policy. No shared recovery policy is inferred from these tests.

## Acceptance boundary

`tests/t_swshunt_acceptance_batch4.m` exercises the two adapters on mixed-sign
blocks, both bounds, local/remote regulation, identity mapping, disabled modes,
deadband edges, competing votes, row permutations, fixed BS accumulation,
continuous history differences, candidate rejection and actual AC cycling.
Independent electrical solves check direction and complex AC nodal balance.
Explicit unified-lock failures must pass before extraction.

Short Beerten gates additionally check corrected PF/CPF states, shunt events,
combined ULTC/shunt controls, original grids/bounds, generator Q and AC/DC/VSC
balance. This is acceptance of the project variant, not benchmark conversion or
certification against the publication. Broader recovery, non-unit PQBRAK with
mixed FACTS/TWODC/VSC equivalent loads, TRANSPA and hydro remain deferred.
