# PSS/E-aware MATPOWER diagnostics

Run id: `beerten_vsc`

Source folder: `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\beerten_vsc`

Primary MAT file: `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\beerten_vsc\beerten5_cpf_psse_nose_vschvdc_on_actaps1_swshnt1_vsccap_gencap.mat`

## Summary

- solver type: `unified_vsc_mtdc`
- success: `1`
- max lambda: `2.93061921892198`
- CPF points: `82`
- events: `203`
- generator trace source: `cpf.gen`
- bus trace table: `492 rows`
- branch trace table: `656 rows`
- VSC trace table: `246 rows`

## Warnings

- Missing optional gen_pq_trace.mat; generator traces may be reconstructed from CPF/event history.

## Exports

- `branch_trace.csv`
- `branchdc_trace.csv`
- `bus_trace.csv`
- `busdc_trace.csv`
- `capability_audit.csv`
- `cpf_points.csv`
- `event_timeline.csv`
- `gen_trace.csv`
- `index_map_branch.csv`
- `index_map_branchdc.csv`
- `index_map_bus.csv`
- `index_map_busdc.csv`
- `index_map_gen.csv`
- `index_map_vsc.csv`
- `vsc_trace.csv`
- `warnings.csv`
- `run_manifest.json`
- `plotting_manifest.json`

## Assumptions

- Full CPF traces are preserved in exported tables; compact trace metadata is used for visual curves when available.
- Generator technology labels use the same online-generator remapping convention as the CPF redispatch policy state.
- VSC plotting is opt-in through `opts.plot_modules`; VSC/DC trace CSVs are emitted when present.
- Plot summaries are appended here after plotting is generated.

## Plots

- selected modules: `pv, gen_pq, events, redispatch`
- bus groups: `boundary_ports, buses_500kv, worst_voltage_drop, lowest_final_voltage`
- branch groups: `top_loading`
- generated files: `5`
- `pv` plots: `2`
- `gen_pq` plots: `2`
- `events` plots: `1`

### Plot files

- `plots/pv_worst_voltage_drop.png` (`pv`)
- `plots/pv_lowest_final_voltage.png` (`pv`)
- `plots/gen_pq_capability_page_01.png` (`gen_pq`)
- `plots/gen_pq_lambda_page_01.png` (`gen_pq`)
- `plots/event_timeline.png` (`events`)

### Plot warnings and skipped modules

- `pv`: PV bus group has no buses: boundary_ports
- `pv`: PV bus group has no buses: buses_500kv
- `redispatch`: redispatch_technology_trace is empty
- PV bus group has no buses: boundary_ports
- PV bus group has no buses: buses_500kv
