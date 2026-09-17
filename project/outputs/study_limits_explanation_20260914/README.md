# Operational limits and voltage loadability

Start with **operational_limits_and_voltage_loadability.pdf** (17 illustrated pages) or **report.html** (offline, with rendered SVG figures and equations). `REPORT.md` is the text companion. This package is an explanation, evidence review and proposed methodology, not a production policy change.

The main result is the distinction between an operational restriction, a capability/dispatch restriction, and a supported mathematical endpoint. For the declared PG2 = 40 + 240 lambda schedule and retained 80 MW generic ceiling, lambda = 1/6 is an analytical upper bound on admissible loading (40 MW additional demand; 205 MW total). No new voltage-collapse margin is claimed.

## New diagnostic finding

The unchanged solver reports target success at lambda = 0.20 but projects PG2 to 80 MW rather than the scheduled 88 MW. These points are **dispatch-invalid**, not valid continuation of the user's scenario. A separate run to lambda = 1/6 returns 0.166666661623 and PG2 = 79.9999987895 MW, preserving the schedule at its saved samples. Neither run detects a nose.

- `diagnostic_evidence.json`: inspected case/options, real-valued trace evidence and raw termination/convergence fields.
- `diagnostic_points.csv`: nine samples from two runs, with schedule error, bus voltage extrema and original-branch terminal loading.
- `scenario_inspection.mat`, `boundary_diagnostic.mat`, `dispatch_diagnostic.mat`: full MATLAB inputs/results, including complex states.
- `boundary_diagnostic.log`, `dispatch_diagnostic.log`: preserved diagnostic transcript, including entry-point and JSON packaging errors. No numerical warning was returned by either completed run.
- `event_acceptance_table.csv`: compact proposed event contract extracted from the report.
- `figures/`: eight reusable PNG/SVG scientific diagrams/charts and rendered equation assets. Every plotted source class is labeled.
- `source_hashes_before.json`, `preservation_check.json`: preservation check of inspected production/study/contract files and key historical inputs/results. The baseline was recorded after the first read-only diagnostic; no production writes occurred before it.
- `verification.json`: artifact/evidence checks; explicitly retains dispatch acceptance failures.
- `qa/`: rendered PDF pages and visual inspection artifacts.

Historical batch-6 curves are read directly from `../beerten_validation_batch6_20260911/final_04/`. They hold PG2 at 40 MW and must not be attributed to the new scenario.

## Reproduction

Run Python from the project root using the project virtual environment:

```powershell
.venv/Scripts/python.exe outputs/study_limits_explanation_20260914/build_report.py
```

This rebuilds only this package's report/figure files from already saved evidence. NumPy/Matplotlib/Pillow/pypdf come from the project environment; the builder appends the discovered bundled ReportLab package directory. No dependency installation was needed.

For a new numerical replay, use MATLAB MCP from the project root, initialize with `iniciar_proyecto`, then call `reproduce_diagnostics` with a **new, nonexistent absolute destination directory**. Add this output directory to the session path if needed. The function refuses to overwrite a destination. It executes `runcpf_psse` with the two bounded endpoints; no solver/capability/control parameters are altered. Follow `.codex/MATLAB_MCP.md`; do not use `restoredefaultpath`.

Decisions still needed are listed on report page 15: the operating criterion set, permitted analytical continuation scope, the purpose/dispatch of any separate experiment beyond G2's ceiling, and actual comparison boundaries/contingencies. A narrow dispatch-preservation fix is proposed for a later task; none is applied here.
