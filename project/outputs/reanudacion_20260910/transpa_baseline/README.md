# TRANSPA CPF/PSS-E run

Run id: `transpa_cpf_psse_all_disabled_pv_only`.

Case: `case_transpa_reduced_v1_explicit`.

Mode: `psse`.

Entry point: `runcpf_psse`.

Control values: `ACTAPS=0`, `SWSHNT=0`, `GENQ=0`, `VARLIM=0`, `GENERAL.PQBRAK=0`, `DCTAPS=0`, `FACTS=0`.

Options: `swshunt_repair=0`, `gen_capability=0`, `gen_capability_enforce=0`, `gen_redispatch=0`, `gen_pq_trace=0`.

Target: uniform `PD/QD = 2x` for nonzero-load buses.

Stop condition: `cpf.stop_at = NOSE`.

CPF step settings: `cpf.step = 0.001`, `cpf.step_max = 0.005`, `cpf.adapt_step = 1`.

## Results

- success: `1`
- max lambda: `0.239568152635`
- load factor at nose: `1.23956815263`
- CPF points: `678`
- CPF events: `1`
- physical buses plotted: `253`
- final minimum physical-bus voltage bus: `332`
- final minimum physical-bus voltage: `0.667215937298 pu`
- final minimum voltage bus: `1.00002e+06`
- final minimum voltage: `0.663764627409 pu`

## Timing

- CPF solve seconds: `41.944`
- plot/write seconds after CPF: `0.007`
- total script seconds: `42.630`

## Event Counts

- `NOSE`: `1`

## Figures

