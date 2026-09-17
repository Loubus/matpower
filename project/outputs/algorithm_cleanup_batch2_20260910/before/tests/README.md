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

The independent historical suites remain callable, unchanged:

```matlab
t_vsc_mtdc(0);   % full 330-check electrical/control/compatibility regression
t_mpxt_psse(0);  % mixed physical/adapter/policy/PSS/E reference checks
t_psse(0);       % RAW import/interface regressions
```

These are MP-Test functions, not MATLAB `runtests` files. Their scope is broader
than the new focused gate. See the [acceptance contract](../docs/CONTROL_ACCEPTANCE.md)
for classification and additional coverage required before ULTC/shunt refactoring,
and the [batch report](../outputs/algorithm_cleanup_batch1_20260910/REPORT.md)
for measured results and open defects. Original historical output directories
and regression assertions are preserved.
