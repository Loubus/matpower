# Repository cleanup batch 1 — 2026-09-10

Completed: organize case families, separate active Beerten studies from historical audit work, preserve regression fixtures, and update path/output lookup. No solver equations, control decisions, numerical defaults, or test assertions were changed.

## Final organization

- `cases/full_network/raw/`: exact copy of the full-network RAW.
- `cases/beerten/variants/`: all 16 existing project functions; published inputs stay under `upstream/`.
- `cases/ieee/14`, `30`, `39`, `57`: exact local case snapshots; hybrid upstream references remain separate.
- `cases/nordic/upstream/`, `cases/cigre/upstream/`: collected sources, pending conversion/reference audit and numerical validation.
- `studies/beerten/`: active runner, physically relocated; outputs now default to `outputs/beerten/`.
- `tests/fixtures/controls/legacy_regression/`: 14 RAW fixtures required by the existing regression suite.
- `docs/`: current study design and benchmark inventory; `cases/source_manifest.json` records relocated sources and local snapshots.
- `archive/`: grouped references to historical audit and TRANSPA reduction work, excluded from normal initialization.

Historical audit/reduction directories retain their original physical paths because MATLAB canonicalizes junction paths and their scripts use location-relative project-root calculations. Archive entries link to those directories. The original Beerten path instead links to the new active study folder, which preserves its original depth. The final layout is recorded in [legacy_path_layout.json](legacy_path_layout.json) and [archive notes](../../archive/README.md). Original vendor case files and the RAW under `PSSE/` remain for compatibility. No historical disk-space reduction is claimed.

`iniciar_proyecto` loads the active case/study folders and removes former historical paths from an existing session. `iniciar_proyecto_legacy` enables the historical paths explicitly. Returning to normal initialization was verified. Both initializers leave MATLAB MCP support and unrelated paths intact.

## Verification

All MATLAB work used the configured MCP session. See [numerical_verification.json](numerical_verification.json), `baseline_results.mat`, `cases_before.mat`, and `after_results.mat`.

| Check | Result |
| --- | --- |
| `t_mpxt_psse(1)` before cleanup | 508 passed, 0 failed, 0 skipped |
| Same suite after fixture/path changes | 508 passed, 0 failed, 0 skipped |
| Loaded case structures: IEEE 14/30/39/57 and base Beerten | Exactly equal to pre-cleanup structures |
| IEEE 14 AC power flow | Success before/after; bus/gen/branch arrays exactly equal |
| Base Beerten VSC power flow | Success before/after; bus/gen/branch/vsc arrays exactly equal |
| Relocated Beerten controlled CPF runner | Success; four accepted trace points, max lambda 0.0499999229727; correct new output location |
| Normal -> legacy -> normal startup | Historical runner resolves at original physical path; 332-bus reduced case loads; historical paths removed on return |
| MATLAB Code Analyzer | Zero messages for both initializers, changed test file and Beerten runner |

The CPF smoke run used the existing default model/control options, with only `stop_at=0.05`, plotting off and a separate run/output name. It checks runner integration and output placement; it is not a full nose trace or new stability validation. Its log is [beerten_runner_smoke.log](beerten_runner_smoke.log), and generated files are under `outputs/beerten/cleanup_batch1_smoke_20260910/`.

File verification found:

- All 22 downloaded source files retain their recorded hashes.
- All 39 migration copies, including backups and 21 local case snapshots, retain their recorded hashes.
- All 2,035 checkpointed files remain accessible: 2,030 are unchanged; five differences are the intended initializer, test lookup, Beerten runner/README, and the previously agreed algorithm-first study-design update.
- All 86 result-directory counts/bytes match the earlier inventory when using its ordinary Windows-path view. Extended-path enumeration additionally finds 80 long-path files that the earlier view omitted: 2,954 files totaling 4,376,676,693 bytes. This is a count/size check, not a pre/post hash comparison of every historical result.

See [file_verification.json](file_verification.json), [result_tree_verification.json](result_tree_verification.json), and [path_changes.diff](path_changes.diff). The preflight checkpoint and original Git patches remain in `outputs/repo_cleanup_preflight_20260910/`.

## Migration corrections and limits

The initial directory move followed nested Windows junctions. Their contents were located and restored using checked, same-volume directory renames; only newly created empty target directories were removed. Later MATLAB checks demonstrated that even intact junctions canonicalize to the new physical paths. The audit/reduction moves were therefore reversed and the links inverted to preserve historical root discovery. `migration.json` records the initial actions; `legacy_path_layout.json` records the final correction. The migration scripts refuse to rerun after their records exist.

Startup initially encountered the same canonicalization when removing old paths. The initializer now filters only the explicit legacy entries, including their canonical archive forms. The initial failing legacy-return assertion passed after this correction. The first preservation check also detected the earlier study-design update and Windows long-path omissions; both were inspected and are separately recorded above.

The existing regression suite still mixes physical and exact PSS/E compatibility expectations. No assertion was dropped to obtain a pass. The separate four VSC test disagreements and TRANSPA generator-capability rebuild failure in the dated audit remain open; this cleanup did not rerun those failing studies or resolve them. Nordic/CIGRE are organized source inputs, not ready-to-run validated project cases. Archived workflows were not exhaustively executed.

## Next implementation boundary

Separate physical/control acceptance criteria from exact PSS/E matching, establish the Beerten reference, and simplify one control policy at a time with those checks. Integrate IEEE 30/39/57, Nordic and CIGRE B4 into a common validation workflow sequentially. Reassess the TRANSPA reduction and construct the hydro AC/VSC corridor after algorithm validation.
