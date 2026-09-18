# Project workspace snapshot — 2026-09-18

This folder versions the thesis-level work that was originally outside the MATPOWER Git repository: `tests/`, `studies/`, `docs/`, `cases/`, `outputs/`, startup scripts, project instructions and the MATLAB MCP guide. `SNAPSHOT_MANIFEST.json` records the original relative paths, byte sizes and SHA-256 hashes. The copied files preserve their original contents; source and case changes inside MATPOWER are committed in the normal repository locations.

The parent workspace remains the working location. This is a checked snapshot, not an automatic synchronization mechanism. Subsequent changes to the parent workspace must be copied here deliberately before committing.

## Reconstructing the original layout

Clone this repository into a directory named `matpower` inside a separate workspace. Copy the contents of this `project` directory, including `.codex/MATLAB_MCP.md`, into that workspace, alongside `matpower/`. Run `iniciar_proyecto` from the reconstructed workspace. Do not run the copied startup function directly inside `matpower/project`, because it intentionally retains the original relative layout.

The original companion `matpower-extras` checkout uses upstream commit `bc21752` (MATPOWER Extras 8.1). Vendor manuals, local environments, credentials, agent-session history, and the separate historical PSS/E tooling/archive directories are not part of this snapshot. Historical reports may reference those original external locations. The included Beerten fixtures, studies and verification outputs remain under their original relative paths after reconstruction.

## Current validation

The current study endpoint is NOSE, per [the scope decision](docs/CPF_STUDY_SCOPE_20260918.md). The [fresh closure check](outputs/cpf_nose_closure_20260918/verification.json) reaches the first loading maximum at 463.96055 MW and exactly matches the verified trace. The [capability/release verification](outputs/cpf_branch_preserving_release_20260918/REPORT.md) records 146/146 study checks, 23/23 local release checks and 330/330 existing VSC checks. FULL lower-branch recovery is deferred; its unresolved radial saturation transition remains documented rather than certified as collapse.

The earlier [checkpoint replay report](outputs/cpf_checkpoint_replay_20260917/REPORT.md) and other historical results retain their original dates and failure evidence. Their presence is not a claim that every historical run passed. The general Beerten runner now defaults to NOSE; explicitly selected FULL presets and historical option files retain their meanings.

All included files, including MATLAB results and binary archives, are stored directly in Git. GitHub rejected new LFS objects for this public fork, so this snapshot does not depend on Git LFS. The full snapshot is approximately 1.3 GB before Git compression, with each individual file below 100 MiB. Documentation symlinks elsewhere in the repository retain their original Git entries; Windows materialization changes are deliberately left out of this scientific snapshot.
