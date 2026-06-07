# VSC-MTDC Audit Resolution Plan

## Scope

This plan resolves the combined audit findings for the uncommitted VSC-MTDC,
PSS/E-aware CPF/PF and capability-curve work. The goal is not only to keep the
tests green, but also to make the code read, behave and document itself like
MATPOWER code.

The plan preserves the current architectural intent:

- VSC-MTDC PF/CPF remains a MATPOWER/PSS/E-compatible implementation.
- Capability handling remains TESIS-style PF/CPF solve-saturate-continue logic,
  not OPF constraint enforcement.
- No broad refactors, fixture rewrites or unrelated cleanup should be included
  unless needed to close a finding safely.

## Current Findings

1. `savecase` loses VSC-MTDC data (`busdc`, `branchdc`, `vsc`, related
   metadata) when `runpf_vsc_mtdc` or `runcpf_vsc_mtdc` saves a solved case.
2. `mpopt.vsc_mtdc.*` is accepted manually by VSC code but is not registered in
   `mpoption`, so normal calls such as `mpoption('vsc_mtdc.method', 'unified')`
   fail.
3. Public help/API text is stale or contradictory about capability curves,
   operating limits and enforcement.
4. Capability enforcement has silent `try/catch` paths that can hide real
   errors.
5. New public VSC-MTDC functions, data fields and tests are not integrated into
   MATPOWER Sphinx/reference documentation, `caseformat` or option docs.
6. `runcpf` delegates VSC-MTDC cases directly, while other pieces still look
   like an extension. The code needs a clear core-vs-extension decision.
7. Several helpers live as public `lib/` functions without a clear decision
   about whether they are stable public API or internal implementation details.
8. Commit hygiene issues remain: broad `.gitignore` entry for `results/`, mixed
   line endings and minor `checkcode` warnings.

## Phase 0 - Baseline

### Work

- Record `git status --short`.
- Run `git diff --check`.
- Run the current focused regression set:
  - `t_vsc_mtdc`
  - `t_cpf`
  - `t_mpxt_psse`
  - `t_psse`
- Keep the current passing milestone as the reference behavior before edits.

### Acceptance

- Baseline command outputs are saved in the working notes or final summary.
- Any existing warnings are classified before code changes begin.

## Phase 1 - Fix `savecase` Persistence

### Work

- Decide the MATPOWER-style integration path:
  - Preferred extension-style path: add `toggle_vsc_mtdc` with a `savecase`
    callback, similar to `toggle_dcline`.
  - Core-style path: teach `savecase` and `caseformat` directly about `busdc`,
    `branchdc`, `vsc` and related VSC metadata.
- Ensure solved cases preserve:
  - `mpc.busdc`
  - `mpc.branchdc`
  - `mpc.vsc`
  - `mpc.vsc_capability`, if present
  - `mpc.vsc_hvdc_dispatch`, if present and intended to be case data
- Add tests proving a saved VSC case can be loaded and solved again.

### Acceptance

- `savecase(tempfile, loadcase('case3_vsc_mtdc_2term'))` writes `busdc`,
  `branchdc` and `vsc`.
- Loading the saved file preserves the VSC matrices.
- `runpf_vsc_mtdc(..., solvedcase)` and `runcpf_vsc_mtdc(..., solvedcase)`
  produce reusable case files.
- `t_vsc_mtdc` passes.

## Phase 2 - Register `mpoption.vsc_mtdc`

### Work

- Add a registered option surface for VSC-MTDC.
- Include defaults for all options currently consumed by the implementation,
  including:
  - `method`
  - PF/CPF iteration and tolerance fields
  - `cpf_max_it`
  - `cpf_max_lam`
  - `dispatch_policy`
  - `psse_aware`
  - `psse_control_limit`
  - `psse_control_max_it`
  - capability enforcement fields
  - capability PF/CPF max iteration fields
  - VSC and generator capability parameter overrides
- Prefer MATPOWER's existing `mpoption_info_*` pattern if it fits cleanly.
- Replace ad hoc local default structs where possible with the registered
  option defaults.

### Acceptance

- `mpoption('vsc_mtdc.method', 'unified')` succeeds.
- `mpoption('vsc_mtdc.capability_enforce', 1)` succeeds.
- Invalid VSC-MTDC options fail with a clear `mpoption` error.
- Existing struct-style code paths still work for backward compatibility where
  required by tests.
- `t_vsc_mtdc`, `t_cpf`, `t_mpxt_psse` and `t_psse` pass.

## Phase 3 - Align Public Help Text

### Work

- Update `idx_vsc` so it describes current capability behavior accurately.
- Update `runpf_vsc_mtdc` to explain:
  - supported VSC-MTDC methods;
  - capability auditing vs active enforcement;
  - PF solve-saturate-continue behavior;
  - unsupported OPF/LCC/type-switching behavior.
- Update `runcpf_vsc_mtdc` to list all supported `mpopt.vsc_mtdc` fields.
- Update capability helper help blocks to use consistent terminology:
  - "post-solve saturation"
  - "active-set enforcement"
  - "not OPF constraints"
- Check all `See also` lists for useful MATPOWER navigation.

### Acceptance

- Help text no longer says capability curves or operating limit enforcement are
  absent when PF/CPF capability enforcement exists.
- `help runpf_vsc_mtdc`, `help runcpf_vsc_mtdc` and `help idx_vsc` are enough
  for a user to find the option and data contracts.
- `checkcode` does not introduce new avoidable warnings.

## Phase 4 - Remove Silent Capability Failures

### Work

- Audit all capability-related `try/catch` blocks.
- Replace silent catches with one of:
  - a clear error for invalid inputs or programmer mistakes;
  - a structured report field for expected non-fatal infeasibility;
  - a warning only when continuing is intentional and safe.
- Preserve TESIS-style behavior: solve, detect violation, saturate, continue.
- Add tests for malformed capability metadata and invalid option lengths.

### Acceptance

- Capability metadata errors are visible.
- Expected infeasible capability regions are reported deterministically.
- No enforcement path silently skips a converter or generator because a helper
  threw unexpectedly.
- `t_vsc_mtdc` passes.

## Phase 5 - Integrate MATPOWER Documentation

### Work

- Update `caseformat` to document:
  - `busdc`
  - `branchdc`
  - `vsc`
  - optional VSC capability metadata
  - optional VSC dispatch metadata
- Update `mpoption` documentation or generated option reference for
  `vsc_mtdc`.
- Add Sphinx/ref-manual pages and index entries for public functions:
  - `runpf_vsc_mtdc`
  - `runcpf_vsc_mtdc`
  - `runpf_vsc_mtdc_unified`, if public
  - `idx_busdc`
  - `idx_branchdc`
  - `idx_vsc`
  - `makeGdc`
  - public capability helpers
  - `t_vsc_mtdc`
- Decide whether `docs/other/VSC-MTDC-Capability-Next-Steps.md` remains an
  internal design note or should be rewritten into user/developer docs.

### Acceptance

- Sphinx index contains the new public VSC-MTDC pages.
- `caseformat` describes every new case-data field needed to write a VSC case.
- Option docs match the registered `mpoption` defaults.

## Phase 6 - Decide Core vs Extension Architecture

### Work

- Make one explicit decision:
  - Core feature: integrate consistently into legacy command flow,
    `caseformat`, `mpoption`, `savecase`, docs and tests.
  - Extension: provide a `toggle_vsc_mtdc`/userfcn-style activation path or an
    MP-Core extension path, keeping core `runcpf` changes minimal.
- Revisit direct VSC delegation in `runcpf`.
- Ensure `runpf_psse` and `runcpf_psse` dispatch VSC-MTDC consistently with the
  chosen architecture.

### Acceptance

- The code no longer sits halfway between extension and core feature.
- The chosen architecture is documented in a short developer note or in the
  relevant help/docs.
- Existing PSS/E-aware VSC regressions remain green.

## Phase 7 - Public API vs Internal Helpers

### Work

- Classify each new helper in `lib/`:
  - public API;
  - developer/testing API;
  - internal implementation detail.
- Keep public helpers in `lib/` and document them.
- Move or encapsulate internal helpers where appropriate.
- Replace magic test dispatch strings such as `__setup`, `__mismatch`,
  `__jacobian` and `__cpf_system` with a clearer internal/test API, or document
  them if intentionally supported.

### Acceptance

- Public `lib/` functions have complete help blocks and ref-manual entries.
- Internal-only implementation details are not accidentally advertised as
  stable user API.
- Jacobian tests still have access to the required internals through a clear
  test seam.

## Phase 8 - Cleanup and Style Hygiene

### Work

- Revisit `.gitignore` entry for `results/` and narrow it if needed.
- Normalize line endings for touched files according to repository convention.
- Address minor `checkcode` warnings where the fix is low-risk:
  - sparse assembly in `makeGdc`;
  - dynamic growth of `history` in `runpf_vsc_mtdc_unified`;
  - any new warnings introduced by the plan.
- Avoid unrelated style churn.

### Acceptance

- `git diff --check` is clean.
- `checkcode` has no new avoidable warnings in touched files.
- `.gitignore` does not hide unintended nested result directories.

## Phase 9 - Final Regression

### Work

- Run:
  - `t_vsc_mtdc`
  - `t_cpf`
  - `t_mpxt_psse`
  - `t_psse`
- If practical, run `test_matpower`.
- Re-run the targeted manual checks:
  - `mpoption('vsc_mtdc.method', 'unified')`
  - `savecase` round-trip of a VSC case
  - `help runpf_vsc_mtdc`
  - `help runcpf_vsc_mtdc`
  - `help idx_vsc`

### Acceptance

- All focused regressions pass.
- Manual MATPOWER user workflows work:
  - options can be set with `mpoption`;
  - VSC cases can be saved and loaded;
  - public help text reflects actual behavior.
- Final summary maps each original finding to the change and regression that
  closes it.

## Suggested Execution Order

1. Phase 0: Baseline.
2. Phase 1: `savecase`.
3. Phase 2: `mpoption`.
4. Phase 3: public help text.
5. Phase 4: silent capability failures.
6. Phase 5: docs/ref-manual/caseformat.
7. Phase 6: architecture decision.
8. Phase 7: helper/API cleanup.
9. Phase 8: style hygiene.
10. Phase 9: final regression.

The first two implementation phases should be treated as highest priority,
because they are the places where a normal MATPOWER user will immediately hit a
broken workflow.
