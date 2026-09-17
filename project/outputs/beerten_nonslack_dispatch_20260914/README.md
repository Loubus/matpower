# User-declared Beerten dispatch scenario — 2026-09-14

Entry point: `studies/beerten/beerten_constant_pq_nonslack_dispatch.m`.
This creates a separate scenario from the batch-6 loader. Historical cases,
batch-6 source, saved results and published reference inputs remain unchanged.

Declared changes: AC slack generator MBASE is 1,000 MVA in base and target;
generator 2 at original bus 6 supplies the scheduled incremental demand with
PG2 = 40 + 240 lambda MW. The slack supplies the base balance and changes in
system losses. The load direction remains Ptotal = 165 + 240 lambda MW and
Qtotal = 40 + 40 lambda MVAr. MBASE does not alter PMAX or the generic slack
capability exemption. PQBRAK-off, saturation and supported capability settings
are inherited from batch 6.

MATLAB MCP initialization and a short CPF to lambda 0.05 succeeded. Generator 2
produces 52 MW as scheduled. `smoke.mat` preserves inputs, options and output;
`summary.json` records the result. This is not a full continuation or new margin.

The non-slack generator retains MBASE=100 MVA and its generic thermal curve.
That curve's active maximum is 80 MW, reached by the scheduled direction at
lambda = 1/6. Do not silently transfer further scheduled increments to the slack,
clip generation, or interpret later points as feasible without evaluating how
the current solver handles this constraint. No redispatch-at-limit or rating
change was introduced.
