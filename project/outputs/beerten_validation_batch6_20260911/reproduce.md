# Reproduce batch 6 without overwriting evidence

Run from the project root. Read `.codex/MATLAB_MCP.md` and use MATLAB MCP,
`iniciar_proyecto`, and the project `.venv\Scripts\python.exe`. The original
base/target and the historical unconstrained MAT file are immutable inputs.
The isolated patch is relative to `before/`, not a Git commit. It has already
been applied to the current working files; do not apply it again here.

## Fresh destination and source material

Choose a new directory, such as `outputs/beerten_validation_batch6_rerun_YYYYMMDD_01`.
Do not reuse `final_04` in the original batch directory. The example uses this
new name so existing results are preserved. In PowerShell:

```powershell
$b6src = 'outputs/beerten_validation_batch6_20260911'
$b6run = 'outputs/beerten_validation_batch6_rerun_YYYYMMDD_01'
if (Test-Path -LiteralPath $b6run) { throw 'Choose a fresh destination' }
New-Item -ItemType Directory -Path "$b6run/final_04" | Out-Null
Copy-Item -LiteralPath "$b6src/reference" -Destination $b6run -Recurse
foreach ($b6name in @('inputs.json', 'run_author_reference.m', 'run_project_study.m',
  'audit_controls_corrected.m', 'run_regressions.m', 'independent_validation.py',
  'diagnose_transitions.py', 'build_results.py')) {
  Copy-Item -LiteralPath "$b6src/$b6name" -Destination $b6run
}
```

`inputs.json` contains the frozen original case matrices for the independent
implementation, including the local five-bus input. Author source is an exact
copy of the collected ZIP, verified member by member in `preservation.json`.
This is a local reproducibility copy subject to the author's original license.

## Author reference, project CPF and effective controls

Execute via MATLAB MCP with `project_path` set to the project root:

```matlab
iniciar_proyecto;
b6run = fullfile(pwd,'outputs','beerten_validation_batch6_rerun_YYYYMMDD_01');
addpath(b6run, '-begin');
run_author_reference(b6run);
b6ref = load(fullfile(b6run,'author_reference.mat'));
assert(b6ref.success == 1);
run_project_study(fullfile(b6run,'final_04'));
audit_controls_corrected(fullfile(b6run,'final_04'));
```

The author runner installs only scoped paths and removes them after the run.
The project runner loads the saved constant-PQ fixture, enables the three
declared options, runs steps 0.1/0.05/0.025, materializes every point and exports
the saved unconstrained trace. It does not regenerate or replace that historical
nose. Expect `vsc_capability_limit`, not a constrained CPF nose. Inspect the
full termination record rather than interpreting `success` alone.

The named scenario can independently be obtained with:

```matlab
addpath(fullfile(pwd,'studies','beerten'));
[base,target,options,study] = beerten_constant_pq_capability_batch6;
```

## Independent electrical implementation and plots

From the project-root PowerShell session after MATLAB has completed:

```powershell
& .venv/Scripts/python.exe "$b6run/independent_validation.py"
& .venv/Scripts/python.exe "$b6run/diagnose_transitions.py"
& .venv/Scripts/python.exe "$b6run/build_results.py"
```

These scripts derive paths from their own directory. They read its `final_04`,
write `final_04/independent_final`, and never call MATLAB or the project solver.
The last runner also creates the results CSV and voltage/control plots.
Expected retained findings include the single 2010 AC-only angle rounding
failure, failure of all four full-equipment scenario acceptance checks, and
failed exploratory fixed-loading solves above the surrogate fold. Script exit
success is not a declaration that those scientific checks passed. Read
`validation_counts.json`, individual check records, transition samples and
both fold files. The first derivative estimate is intentionally retained;
the five-point refinements provide the reported limiting-point diagnosis.

## Actual termination instrumentation

`final_04/runcpf_vsc_mtdc_b6_diagnostic.m` adds observations only. Its manifest
records the source version, and `diagnostic_trace_equality.json` certifies
exact lambda, bus, generator, converter and termination equality to the main
run. To repeat this diagnostic against this unchanged production version,
copy that file to the fresh run's `final_04`. Via MATLAB MCP:

```matlab
copyfile(fullfile(pwd,'outputs','beerten_validation_batch6_20260911', ...
 'final_04','runcpf_vsc_mtdc_b6_diagnostic.m'),fullfile(b6run,'final_04'));
addpath(fullfile(b6run,'final_04'),'-begin');
clear runcpf_vsc_mtdc_b6_diagnostic;
s = load(fullfile(b6run,'final_04','scenario.mat'));
[bf,~,o] = mp.psse_prepare_case(s.base,s.options,'cpf_base');
[bt,~] = mp.psse_prepare_case(s.target,o,'cpf_target');
o = mpoption(o,'vsc_mtdc.psse_aware',1);
global b6capdiag; b6capdiag = [];
dr = runcpf_vsc_mtdc_b6_diagnostic(bf,bt,o);
main = load(fullfile(b6run,'final_04','capability_step_100.mat'));
assert(isequaln(dr.cpf.lam,main.result.cpf.lam));
assert(isequaln(dr.cpf.bus,main.result.cpf.bus));
save(fullfile(b6run,'final_04','termination_diagnostic.mat'),'dr','b6capdiag','o');
```

If production changes later, create and review a fresh diagnostic copy; do not
assert that the archived copy still represents the changed solver.

## Regressions and integrity

Via MATLAB MCP, after previous calls finish:

```matlab
addpath(fullfile(pwd,'tests'));
run_regressions(fullfile(b6run,'regressions'));
```

The final recorded suite has 1953 passed / 0 failed / 97 skipped / 0 exceptions.
The two new tests contain 15 reporting checks and 442 capability/handoff checks.
Each suite writes its own `counts.json` and log. Skips are preserved.
`code_analysis.json` records no Code Analyzer issues in the five new/changed
MATLAB implementation/test/scenario files.

`close_batch.py` is a packaging record, not a numerical runner. Its default
scratch destination is deliberately single-use. It builds `batch6.patch`,
checks application to the captured working-file baseline, checks byte-for-byte
equality with final files, verifies original scientific-file hashes and author
archive members, and packages the final count/source manifests. Do not rerun
it in the evidence directory without first choosing fresh packaging outputs.
