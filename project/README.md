# Power flow and voltage-stability thesis

The thesis compares a 500 kV AC corridor with VSC-HVDC for hydro generation in the TRANSPA system. First validate power flow, CPF, ULTC, switched shunts, and generator/converter limits on benchmarks. Develop the hydro corridor after the algorithms are reliable. Exact PSS/E emulation is no longer the research objective.

## Working layout

| Folder | Purpose |
| --- | --- |
| `cases/full_network/raw/` | Preserved full-network PSS/E RAW; TRANSPA application input |
| `cases/beerten/` | Existing project variants and separate published reference inputs |
| `cases/ieee/` | IEEE 14, 30, New England 39, IEEE 57; separate upstream hybrid references |
| `cases/nordic/upstream/` | Nordic source data, pending conversion and validation |
| `cases/cigre/upstream/` | CIGRE B4 transcription, pending reference audit and DCS1 mapping |
| `studies/beerten/` | Current Beerten CPF runner |
| `tests/fixtures/controls/` | Small regression inputs, separate from study benchmarks |
| `matpower/`, `matpower-extras/` | Existing scientific implementation and dependencies |
| `outputs/` | New results and dated verification evidence |
| `docs/` | Agreed study scope and benchmark inventory |
| `archive/` | Historical PSS/E compatibility studies/results and TRANSPA reduction |

The organized case copies preserve the current data exactly. Original MATLAB vendor case files and `PSSE/V26p_Trs_2532.raw` remain for compatibility. Treat `cases/` as the starting point for future project adaptations; record differences explicitly. Downloaded upstream folders are reference data and are not added to the MATLAB path. Historical audit/reduction folders retain their original physical paths and are grouped through archive links, preserving their location-dependent scripts; they are excluded from normal startup.

## Start MATLAB

From this project root:

```matlab
iniciar_proyecto;
mpopt = mpoption('verbose', 0, 'out.all', 0);
pf = runpf_psse('case14', mpopt);
assert(pf.success);
```

For the current Beerten study, see [the runner guide](studies/beerten/cpf_runner/README.md). New Beerten results go to `outputs/beerten/` by default. Current function names containing `psse` remain valid; cleanup has not renamed or simplified the solver.

Use `iniciar_proyecto_legacy` only when revisiting archived workflows. [Archive notes](archive/README.md) explain the compatibility links. Run `iniciar_proyecto` again to remove those historical paths from the current session. Follow [the MATLAB MCP guide](.codex/MATLAB_MCP.md) for agent execution.

## Validation and next work

The first cleanup batch changes organization and path lookup only. It retains all assertions in `t_mpxt_psse`; some still check historical compatibility behavior and need a later deliberate separation from physical correctness tests. Small tests remain useful even though exact PSS/E replication is no longer a goal.

See [cleanup verification](outputs/cleanup_batch1_20260910/REPORT.md), [study design](docs/STUDY_DESIGN.md), [benchmark inventory](docs/BENCHMARKS.md), and [input provenance](cases/source_manifest.json). The [dated numerical audit](ESTADO_PROYECTO_2026-09-10.md) includes four existing VSC test disagreements and a TRANSPA generator-capability rebuild failure. Folder cleanup does not resolve those findings.

Algorithm cleanup batch 1 has a separate [physical control acceptance contract](docs/CONTROL_ACCEPTANCE.md), a focused runner at `tests/t_control_acceptance_batch1.m`, and [VSC investigation evidence](outputs/algorithm_cleanup_batch1_20260910/REPORT.md). The original regression assertions remain intact. Follow the reported gate status before refactoring ULTC or shunts; physical failures are not waived by passing compatibility checks.

Next: resolve the focused physical gates, establish the Beerten reference, and simplify one control policy at a time. Integrate IEEE 30/39/57, Nordic, and CIGRE B4 sequentially into a common validation workflow. Keep the full RAW available while the historical reduction and hydro corridor remain deferred.
