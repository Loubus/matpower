# Repository cleanup: inventory and first migration

Prepared 2026-09-10. Inventory and checkpoint completed; no existing files moved, deleted or edited. No solvers were run. This is organizational work; ULTC/shunt algorithms, capability policies and numerical settings remain outside this cleanup.

## Revised priority after user clarification

The first active work is algorithm validation using Beerten, IEEE, Nordic and CIGRE. Preserve the full-network PSS/E RAW as the authoritative application input. The old reduced TRANSPA study is historical material to revisit later; it is no longer the first migration target. The proposed hydro corridor is the last application phase, after PF/CPF and controls are validated.

Archive PSS/E emulation studies and exact-compatibility comparisons from the main research workflow. Retain a compact set of essential control and import regressions. The name `psse` on a fixture does not determine its value: checks of tap direction/bounds, shunt legal states, generator limits and honest failure reporting still protect the algorithms. Examples occur in `matpower/lib/t/t_mpxt_psse.m` around lines 538, 626 and 702. Some test code directly loads RAW files in `psse_validation_suite`; missing files trigger `t_skip`. Extract or preserve those dependencies before relocating the legacy directories, and report test skips rather than interpreting them as passes. PSS/E-specific iteration counts, switching choices and out-of-scope device modes can move to a separate optional compatibility suite.

Proposed destination layout (not yet created):

```text
cases/
  full_network/raw/       # original full-network RAW and provenance
  beerten/               # original reference plus documented variants
  ieee/30/               # original AC data + later VSC/control adaptations
  ieee/39/
  ieee/57/
  ieee/14/               # small support case
  nordic/                # original RAMSES data + converted cases separately
  cigre/                 # original/transcribed data + mapped cases separately
studies/                 # configurations/runners grouped by those use cases
tests/fixtures/controls/ # minimal electrical/control fixtures; harness location reviewed separately
docs/                    # current scope, algorithms, validation status
outputs/                 # new runs grouped by case/study/run ID
archive/
  psse_compatibility/    # historical comparisons, cases, scripts and evidence
  transpa_reduction_v1/  # earlier reduction package, scripts and results together
```

Keep `matpower/`, `matpower-extras/` and the environment in place. Existing standard IEEE inputs can be referenced by manifests at first instead of duplicating vendor data. A study folder contains project-specific configurations and adapters; it must not imply a separate solver implementation. Preserve Beerten variant provenance rather than flattening them into one case.

The first implementation batch is: identify/extract essential test dependencies, establish the active case-family locations and a common documented runner interface, then transition legacy studies to the archive with working reference mappings. Do not change control equations during this organizational batch. Loading checks and relevant existing baseline checks precede algorithm changes. Case conversion, controller simplification and larger validation then proceed incrementally. No hydro-corridor construction is part of this phase.

## What the four TRANSPA files actually are

| File | Role |
|---|---|
| `case_transpa_reduced_v1.m` | Builder-generated network case: bus/gen/branch matrices and a load of the companion `psse` metadata when present |
| `case_transpa_reduced_v1_explicit.m` | More extensively documented case representation, embedded fallback control/reduction metadata, overlay from the companion file, explicit control flags and optional returned solver settings; current runner default |
| `case_transpa_reduced_v1_psse.mat` | Companion control metadata for the case functions; not an independent network |
| `transpa_reduction_v1.mat` | Saved reduction-build bundle: reduced case, equivalent, original/full and reduced PF results, retained buses/boundaries and validation records; not a fourth scenario |

The builder writes the generated case, companion metadata and build bundle. These are two case representations plus two supporting files, not four independent TRANSPA systems. The explicit case adds control settings after its metadata overlay, so the case functions should not be assumed interchangeable. Keep the complete old package together as deferred historical work; consolidation of its case representations can wait.

## Checkpoint and current state

- Root workspace has no operational Git repository. `matpower/` and `matpower-extras/` have separate repositories; preserve both layouts.
- MATPOWER HEAD: `7f04707f15c8348e7952f70c18933ca332a2fe60`. There are 818 changed tracked paths, including eight in `lib/`, and 891 untracked documentation paths. Do not treat these counts as 1,709 independent scientific edits or use `git clean`/reset to tidy them.
- `matpower-extras/` is clean at `bc217527ce5f2c958226d1c501971bd6527a9532`.
- [checkpoint.zip](checkpoint.zip) contains 2,035 selected files, approximately 12.8 MB compressed: changed/untracked repository files that exist, project scripts/docs/fixtures, the full-network RAW input, and the live TRANSPA cases/metadata. Deleted tracked files are represented in the saved patches.
- Separate staged, working-tree and net-from-HEAD binary patches are saved for each repository. ZIP member hashes and original source hashes matched; Git statuses remained unchanged. Git emitted line-ending warnings during read-only diffs; this task did not normalize files.
- This is a code/input recovery checkpoint, not a complete backup of historical outputs, dependency trees, configuration or Git objects. Retain the existing repository histories and historical results.

Evidence: [summary](summary.json), [checkpoint manifest](checkpoint_manifest.json), [directory inventory](directory_inventory.csv), [result disposition](results_disposition.csv), [active TRANSPA references](live_transpa_references.txt).

## Disposition

| Current area | Disposition | Proposed action |
|---|---|---|
| `matpower/`, `matpower-extras/` | Keep | Preserve repositories and scientific changes; no vendor pruning or broad formatting |
| `iniciar_proyecto.m`, `.codex/`, `.venv/` | Keep | Preserve environment; update only explicit case paths when migrating inputs |
| Beerten canonical runner | Keep active | Document its entry point; retain directory depth initially because code computes the project root with `fileparts` |
| TRANSPA reduction runner/build tools | Deferred/archive target | Preserve together with old inputs/results; remove active startup dependencies only through a verified transition |
| `auditoria_psse_matpower/tools/`, validation fixtures and suites | Split by purpose | Keep essential algorithm/import fixtures; archive PSS/E emulation studies after resolving test consumers |
| `results/transpa_reduccion_v1` | Mixed/live today; deferred research | Preserve the entire package; unlink safely from active workflows before archiving |
| Other 85 experiment result directories | Archive candidates, not certified disposable | Review script/data consumers first; preserve content and legacy path mapping |
| `PSSE/RAW`, source RAW files and CLI runners | Keep | Retain numerical reference data and execution route |
| `PSSE/SOLVED*` and dated scenario output directories | Historical evidence | Consider indexed archive only after reference checks; SAV/RAW files can be comparison inputs |
| `outputs/reanudacion_20260910` | Verification baseline | Preserve as dated evidence, including failures |
| `outputs/thesis_scope_20260910` | Active planning plus collected upstream inputs | Promote current documents to `docs/`; place selected external benchmark data under `cases/benchmarks/upstream/` during a later batch, retaining source manifest and licenses |
| Old wrapper scripts | Compatibility | Keep initially; wrappers are small and reduce migration risk |
| `.tmp_codex`, `.codex_tmp`, `Codex-Sessions` | Unclassified | Inspect ownership, content and consumers before proposing removal |

The result-disposition CSV labels candidates conservatively. Static reference searches cannot prove absence of runtime/dynamic consumers. No folder has been approved for irreversible deletion by this inventory.

## Deferred migration option: TRANSPA inputs (superseded as first batch)

Create `cases/transpa/reduced_v1/` as the proposed canonical location. The first payload is:

- `case_transpa_reduced_v1_explicit.m`
- `case_transpa_reduced_v1.m`
- `case_transpa_reduced_v1_psse.mat`

Both case functions load the sidecar relative to their own file, so the trio must remain together. Preserve exact bytes when copying. Retain `transpa_reduction_v1.mat` and numerical audit tables as reduction provenance; decide their eventual location after checking all consumers. Leave original historical files intact during the initial path transition.

Update the explicit path references in `iniciar_proyecto.m`, `cpf_psse_runner/transpa_cpf_run.m`, `export_cpf_genq_raw_arrays.m`, and `run_cpf_genq_ultc_swshunt_diagnostic.m`. Re-run the reference search before editing. Keep the builder's generation destination distinct from promotion of a validated input: `build_transpa_reduced_case` already accepts an output-directory argument. Do not rerun it or regenerate scientific cases simply to move folders. Its historical default and generated provenance strings require a documented migration decision rather than blind search-and-replace.

With historical copies retained, ensure MATLAB resolves the new canonical copies first and report `which -all` so shadowed copies are visible. Stop adding the mixed result directory to active paths where it is no longer needed. Preserve historical embedded provenance strings; they are not necessarily executable dependencies.

## Verification for that batch

Before any MATLAB work, follow `.codex/MATLAB_MCP.md`, initialize from the project root with `iniciar_proyecto`, and use MCP. Record a task-specific output directory.

1. Capture the original case matrices and metadata before path changes, then load the canonical copies and compare them exactly, including the PSS/E sidecar. Loading a case is not numerical proof of a study.
2. Check resolved function paths and the canonical runner's configured cases/output paths.
3. Run a small PF smoke check and the relevant representative TRANSPA baseline with identical settings before/after if it is needed to exercise the changed path. Save outputs separately; compare success, voltages and relevant CPF summary values. Do not rerun every historical experiment for a path-only migration.
4. Report pre-existing numerical failures separately. A failed controlled TRANSPA CPF remains failed; folder organization cannot resolve its generator-capability rebuild problem.
5. Record exact edited files and hashes. Rollback restores the changed path files from this checkpoint; the old inputs have not been removed. Restore only those files, never reset the whole working tree.

## Following batches

Add a root project overview linking current scope, the five-system benchmark suite (IEEE30, New England39, IEEE57, Nordic, CIGRE B4), canonical runners and known failures. Promote active documents and benchmark sources using a path manifest. Then archive completed experiments in bounded groups under `archive/experiments/`, preserving original relative paths and updating or retaining consumers. Recheck resolved absolute source/destination paths before every move. No algorithm removal is part of these batches.

The earlier TRANSPA migration description is retained as a dependency note, not the next action. The revised algorithm-first priority at the top of this document governs subsequent work.
