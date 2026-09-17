# Unified VSC-MTDC CPF termination reporting

Batch 5 separates an electrical point from acceptance by the automatic-control
scenario. It changes diagnostics and reporting, not controller decisions,
retries, limits, tolerances or recovery policy.

`results.bus`, `gen`, `branch`, `ac`, `vsc` and the final accepted trace column
remain the last accepted point. On a later control rejection,
`results.convergence.converged` describes that point's electrical solve;
`scope = 'last_accepted_point'` and `lambda` identify it.
`convergence.overall_success` mirrors `results.success`.
An unsuccessful base electrical solve no longer receives an unconditional
`converged = true` from the CPF result constructor.
If Newton cannot produce an electrical evaluation, `evaluation_available` is
false, `ac` is empty, and `convergence.state_vector` retains the failed iterate.
The returned input arrays are not claimed to be solved; there is no accepted
base point. This avoids an exception while packaging a numerical failure.

`results.cpf.termination` records the cause, overall success, requested stop,
whether that endpoint was reached, last accepted index/lambda, and whether
a NOSE event was detected. `max_lam` retains its existing meaning as the maximum
accepted trace sample. It is not an independently validated stability margin;
the metadata explicitly records `stability_margin_validated = false`.
A detected NOSE event is a solver event, not independent benchmark validation.

For compatibility, `success` retains the existing configured-stop-policy
semantics. In particular, numeric targets return false when a control bound
prevents reaching the target. NOSE/FULL requests can return true when the
declared stop policy terminates at a control bound. Such a result now explicitly
reports `requested_endpoint_reached = false` and `nose_detected = false`.
Consumers requiring a requested endpoint must inspect that field, not success
alone. This batch does not redefine historical freeze/recovery outcomes.

For terminal PSS/E control rejection, `cpf.failure.diagnostic` retains:

- The cause (`control_bound`, `control_unresolved`, `control_update_failed`,
  `control_cycle`, `control_iteration_limit` or `electrical_correction_failed`).
- The candidate lambda, state vector, full electrical result and explicit
  `candidate_electrical_converged` flag. The candidate is not appended to the
  accepted trace. Its `success` is an electrical-point flag, not control acceptance.
- Decision reports, input electrical results, proposed base/target active sets,
  and whether the final decision actually attempted a correction. Correction
  iteration count and residual are empty/zero when no correction was attempted.

Bounded controllers can remain electrically feasible outside their voltage band.
Under the existing stop policy this is a rejected control point, not a failed
Newton solve or evidence of voltage collapse. Allowing continuation with such
a saturated controller would be a separately justified recovery-policy change.

The batch-5 Beerten gate reproduces the immutable batch-4 fixture to lambda 0.8,
checks exact accepted-trace preservation, and independently solves explicit
fixed-control states around the event. Short lambda-0.4 runs remain separate
successful acceptance cases. See `tests/t_beerten_termination_batch5.m` and the
[batch-5 report](../outputs/algorithm_cleanup_batch5_20260911/REPORT.md).
