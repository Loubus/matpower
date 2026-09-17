# Explicit NOSE-mode comparison

The four variants were actually rerun with `cpf.stop_at = 'NOSE'`, at steps 0.10 and 0.05. These are new executions, not interpretations of the previous FULL flags. All cases, ratings, control requests and other options are unchanged. Production code and historical outputs are preserved.

| Variant | Step | NOSE endpoint reached? | Final lambda | Actual stop |
|---|---:|---|---:|---|
| Baseline | 0.10 | Yes | 1.245160631322 | nose_event |
| Baseline | 0.05 | No | 1.245254300937 | gen_capability_limit |
| Coupled current | 0.10 | Yes, local fold of traced branch | 1.245901716890 | nose_event |
| Coupled current | 0.05 | Yes, local fold of traced branch | 1.245901716889 | nose_event |
| Augmented correction + tangent transport | 0.10 | No; passes turning region without localization | 0.603064704847 | vsc_capability_limit |
| Augmented correction + tangent transport | 0.05 | No; passes turning region without localization | 0.603048242023 | vsc_capability_limit |
| Combined | 0.10 | No; passes turning region without localization | 0.603079754116 | vsc_capability_limit |
| Combined | 0.05 | No; passes turning region without localization | 0.603058660511 | vsc_capability_limit |

For augmented and combined variants, the final all-control tangent-transport revision from the preceding experiments was used. FULL completion is irrelevant to this request; the table specifically checks the requested NOSE endpoint. Failed NOSE endpoints retain a configured-stop-policy success flag, so the raw success flag alone is insufficient.

## Why the augmented variants do not stop at NOSE

The detector requires no active-set change on the step where it detects the positive-to-negative loading-tangent transition. The baseline condition is `~active_set_changed` at `matpower/lib/runcpf_vsc_mtdc.m:837`, followed by the NOSE-mode and tangent tests. That condition remains in the experimental copies: `continuation_limit/all_controls/b17a_cpf.m:853` and `coupled_limit/combined_all_controls/exd_cpf.m:858` under the previous experiment directory.

In both augmented variants, the loading tangent changes sign on the same accepted step where G2 changes from PV to PQ:

| Variant | Step | Accepted index | Previous loading tangent | New loading tangent | G2 bus type |
|---|---:|---:|---:|---:|---|
| Augmented | 0.10 | 22 | +0.240650 | -0.034877 | PV to PQ |
| Augmented | 0.05 | 43 | +0.192886 | -0.029714 | PV to PQ |
| Combined | 0.10 | 22 | +0.225900 | -0.069639 | PV to PQ |
| Combined | 0.05 | 43 | +0.177554 | -0.063466 | PV to PQ |

The event is therefore skipped. On the next step the incoming tangent is already negative, so the detector's requirement that the incoming loading tangent be positive is no longer met. The trace continues down the low-voltage branch until the later VSC 3 projection failure.

This means the variants get through the turning region, but do not establish an accurately localized smooth nose there. The governing equations change at G2's limit: a direction change across that transition is not automatically a smooth saddle-node of one fixed equation set. Simply removing the active-set guard and running the old same-branch localization would not be a justified fix. Event-aware localization must distinguish a smooth fold from a maximum associated with a control-limit transition.

## What the successful NOSE flags establish

The baseline 0.10 run ends at V5=0.678584996 p.u. Its normalized loading-tangent component is 3.7168e-6, within the configured 1e-5 nose tolerance. The 0.05 baseline still fails during generator-limit settlement, illustrating step/control-history sensitivity. Its slightly higher final lambda belongs to a different saturated-control history and is not evidence that the 0.10 nose is impossible.

The coupled-current runs end at V5 approximately 0.688338 p.u., with loading-tangent components 8.53e-8 and 9.17e-8. Thus both formally locate a local fold within tolerance, and their reported loading agrees closely. The preceding experiment's branch-selection caveat remains: the inherited tangent reset after G2's transition makes this variant approach its fold while V5 is increasing. These runs establish the local fold of that traced branch, not a certified common physical loadability maximum for all control formulations. The later current-control recovery issue seen in FULL occurs after these NOSE stops.

For the current request, the practical answer is: baseline is not robust across the tested steps; coupled current formally stops at a local nose at both steps; augmented and combined reach the descending side but need event-aware detection/localization before NOSE mode works as intended.

## Evidence and checks

Every accepted trace passed the 17 independent electrical/equipment/control-policy checks used in the preceding comparison. Raw results, options, warnings, events, trial journals and per-run audits are preserved alongside this report. No numerical warning was recorded in these eight runs. MATLAB MCP performed all solves and numerical audits.

- `comparison.json`: complete results and termination scopes.
- `turn_evidence.json`: last-finite-component tangent extraction, sign changes and PV/PQ types.
- `*_summary.json`, `*_audit.json`, `*_trace.csv`, `*.mat`: individual runs.
- `run_nose_comparison.m`: reproducible driver with overwrite protection.

An auxiliary JSON-export attempt initially tried concatenating structs with different fields; it was corrected to serialize the cell array. It did not affect any solver run or saved MAT result.
