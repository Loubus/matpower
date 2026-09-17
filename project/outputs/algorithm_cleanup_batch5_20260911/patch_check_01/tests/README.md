# Control validation

Initialize MATLAB from the project root with `iniciar_proyecto`, using the
project's [MCP guide](../.codex/MATLAB_MCP.md).

```matlab
addpath(fullfile(pwd, 'tests'));
t_control_acceptance_batch1(0, fullfile(pwd, 'outputs', 'acceptance_new_run'));
```

Use a new output directory on each run. This physical gate saves inputs,
effective result tolerances, complete PF/CPF results, individual checks and
the four unchanged legacy observations. It intentionally fails if a physical
requirement fails. Do not interpret a saved MAT/JSON file as a passing test.

Run the handoff gate before changing control policies:

```matlab
t_control_handoff_batch2(0, fullfile(pwd, 'outputs', 'handoff_new_run'));
```

It covers proxy/indexing round trips (including offline generators and P/Q cost
rows), both topology expansion paths, fixed versus switched shunts, load totals,
VM versus VG, independent legal-state enumeration, and a genuine GENQ crossing
with accepted-point and CPF step checks. It saves full MAT evidence and JSON
checks in the requested fresh directory.

The broader suites remain callable:

```matlab
t_vsc_mtdc(0);   % full 330-check regression using repaired-model expectations
t_vsc_mtdc(0, true); % replay the original auxiliary-model snapshots
t_mpxt_psse(0);  % mixed physical/adapter/policy/PSS/E reference checks
t_psse(0);       % RAW import/interface regressions
```

These are MP-Test functions, not MATLAB `runtests` files. Their scope is broader
than the new focused gate. See the [acceptance contract](../docs/CONTROL_ACCEPTANCE.md)
for classification and additional coverage required before ULTC/shunt refactoring,
and the [batch report](../outputs/algorithm_cleanup_batch1_20260910/REPORT.md)
for measured results and open defects. Original historical output directories are preserved. Five obsolete auxiliary
assertions remain runnable via the second argument of `t_vsc_mtdc`. Their default
replacements use the full-model legal grid, original Q limits and nodal balance;
see the [batch 2 report](../outputs/algorithm_cleanup_batch2_20260910/REPORT.md).

Additional electrical and derivative coverage:

```matlab
t_pf_ac(0); t_pf_dc(0); t_cpf(0);
t_jacobian(0); t_hessian(0);
```

MP-Test may return normally after failed checks. Inspect its passed/failed/skip
counts and any exception, not only the function exit status. Batch 2 uses the
output-local `run_batch2_suite.m` runner to retain this distinction.

Batch 3 adds ULTC decision/interface/physical coverage and short Beerten
controls-active verification:

```matlab
t_ultc_acceptance_batch3(0, fullfile(pwd,'outputs','ultc_new_run'));
t_ultc_beerten_batch3(0, fullfile(pwd,'outputs','ultc_beerten_new_run'));
```

The first exercises both AC and unified control entry points, including declared
lock handoff, simultaneous tap moves, actual cycling and numerical replay. The
second retains the existing Beerten variant's limits and bands: uniform growth
to lambda 0.6 and growth of load bus 7 to lambda 0.8, with an accepted tap event.
It checks every accepted point against an independent full-model fixed-state
PF, materializes each stored CPF state to check full AC balance, checks DC/converter
balance, and compares automatic endpoint PF and half-step CPF. It does not
certify agreement with the published Beerten reference. See the
[tap-decision contract](../docs/ULTC_DECISION_CONTRACT.md) for preserved caller
policy differences and the [batch 3 report](../outputs/algorithm_cleanup_batch3_20260910/REPORT.md)
for measured outcomes. The output-local `run_batch3_suite.m` retains counts,
warnings in logs and exceptions; every rerun needs a fresh destination.

Batch 4 adds switched-shunt acceptance and short shunt-event Beerten cases:

```matlab
t_swshunt_acceptance_batch4(0, fullfile(pwd,'outputs','shunt_new_run'));
t_swshunt_beerten_batch4(0, fullfile(pwd,'outputs','shunt_beerten_new_run'));
```

The first compares AC and unified decisions, checks mixed-sign blocks and
explicit lock eligibility, and independently solves physical candidates. It
retains continuous sensitivity, candidate screening and cycling differences.
The second uses the original Beerten control variant's shunt data, with
shunt-only and combined ULTC/shunt cases to lambda 0.4 under bus-5 growth.
Every accepted state is checked for physical balance and legal states, with
independent fixed-state PF, automatic endpoint PF and half-step CPF comparisons.
See the [shared shunt contract](../docs/SWSHUNT_DECISION_CONTRACT.md) and
[batch 4 report](../outputs/algorithm_cleanup_batch4_20260911/REPORT.md).

Batch 5 reproduces the saved long Beerten control-bound event and checks
termination reporting without changing automatic-control acceptance:

```matlab
t_beerten_termination_batch5(0, fullfile(pwd,'outputs','termination_new_run'));
```

The gate loads the immutable batch-4 `beerten_probe.mat` inputs/options. It
checks exact accepted-trace preservation, separate accepted/rejected electrical
states, original control bands and capability, independent full-equation PF
solutions around the event, finer CPF steps, and numeric versus NOSE stop
reporting. Fixed-state diagnostics do not replace automatic-control acceptance.
See the [termination contract](../docs/CPF_TERMINATION_CONTRACT.md).
