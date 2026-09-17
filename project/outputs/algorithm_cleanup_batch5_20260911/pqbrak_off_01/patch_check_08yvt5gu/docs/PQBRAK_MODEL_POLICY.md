# PQBRAK modeling policy — 2026-09-11

PQBRAK low-voltage load scaling is **off by default throughout the MATPOWER
PSS/E PF and CPF paths**, including unified VSC/MTDC and the optional
coordinated active-set solver. This is a user-requested modeling change, not
a repair of the earlier PQBRAK control-settlement failure.

`mpoption('exp.psse_pqbrak', 0)` is the default. Older saved option structures
that omit this field also disable the model. Explicit
`mpoption('exp.psse_pqbrak', 1)` permits historical PQBRAK-on experiments;
merely having `GENERAL.PQBRAK` in a RAW case does not enable it.

RAW thresholds, the historical 0.7 PSS/E default, and the scaling formula are
preserved. Solver-policy reports mark PQBRAK disabled when the option is off.
Preparation removes cached native-load scaling by external bus ID, preserves
other equivalent demand, and records a disabled, unit-scale cache. Repeated
preparation does not repeatedly restore load. Controllers cannot re-enable
PQBRAK from stale prepared metadata. The separate PSS/E executable and its
historical CLI experiments are unchanged.

The requested Beerten run uses constant scheduled P/Q demand, automatic taps
and switched shunts, and the previously authorized saturation acceptance
policy. Other controls, ratings, enforcement options, tolerances, and step
settings remain as saved. A constant-load nose is a property of that selected
model; it is not evidence that every equipment constraint is satisfied.

Evidence: `outputs/algorithm_cleanup_batch5_20260911/pqbrak_off_01/REPORT.md`.
Regression: `tests/t_pqbrak_off_batch5.m`. The historical full PSS/E control
suite explicitly opts into PQBRAK to preserve its original scientific checks.
