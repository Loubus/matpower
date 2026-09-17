# TRANSPA CPF/PSS-E run

Run id: `transpa_cpf_psse_load200_actaps1_swshnt1_genq0_pqbrak0_swrepair_gencap`.

Case: `case_transpa_reduced_v1_explicit`.

Mode: `psse`.

Entry point: `runcpf_psse`.

Control values: `ACTAPS=1`, `SWSHNT=1`, `GENQ=0`, `VARLIM=0`, `GENERAL.PQBRAK=0`, `DCTAPS=0`, `FACTS=0`.

Options: `swshunt_repair=1`, `gen_capability=1`, `gen_capability_enforce=1`, `gen_redispatch=0`, `gen_pq_trace=0`.

Switched-shunt zero-width voltage bands repaired from similar retained records:

- bus `566`: `0.99-1.01` copied from bus `222` (row `6`), replacing `1-1`
- bus `570`: `0.99-1.01` copied from bus `222` (row `6`), replacing `1-1`
- bus `230231`: `0.97-1.03` copied from bus `334` (row `13`), replacing `1-1`

Target: uniform `PD/QD = 2x` for nonzero-load buses.

Stop condition: `cpf.stop_at = NOSE`.

CPF step settings: `cpf.step = 0.001`, `cpf.step_max = 0.005`, `cpf.adapt_step = 1`.

## Results

- success: `0`
- max lambda: `0.222674742017`
- load factor at nose: `1.22267474202`
- CPF points: `718`
- CPF events: `28`
- physical buses plotted: `253`
- final minimum physical-bus voltage bus: `332`
- final minimum physical-bus voltage: `0.626896709024 pu`
- final minimum voltage bus: `332`
- final minimum voltage: `0.626896709024 pu`

## Timing

- CPF solve seconds: `126.941`
- plot/write seconds after CPF: `0.002`
- total script seconds: `127.587`

## Event Counts

- `NOSE`: `1`
- `PSSE_GEN_CAPABILITY`: `2`
- `PSSE_SWSHUNT`: `1`
- `PSSE_XFMR`: `24`

## Figures

