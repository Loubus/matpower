# Beerten 5-bus CPF run

Run id: `beerten5_cpf_psse_nose_vschvdc_on_actaps1_swshnt1_vsccap_gencap`.

Case: `case5_vsc_mtdc_beerten_paper_controls_cap_explicit`.

Target: `case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit`.

Mode: `psse`.

Entry point: `runcpf_psse`.

VSC-HVDC enabled: `1`.

Controls: `ACTAPS=1`, `SWSHNT=1`.

Devices: `switched_shunt=1`, `ultc_transformer=1`.

Stop condition: `cpf.stop_at = NOSE`.

CPF step settings: `cpf.step = 0.05`, `cpf.step_max = 0.05`.

## Results

- success: `1`
- max lambda: `2.93061921892`
- CPF points: `82`
- CPF events: `203`
- final minimum active-bus voltage bus: `5`
- final minimum active-bus voltage: `0.658677692915 pu`
- final minimum voltage bus: `5`
- final minimum voltage: `0.658677692915 pu`
- done message: `Reached VSC-MTDC monolithic VSC capability loading limit in 81 continuation steps, lambda = 2.93062.`

## Timing

- CPF solve seconds: `636.304`
- plot/write seconds after CPF: `13.227`
- total script seconds: `649.734`

## Event Counts

- `PSSE_CONTROL`: `7`
- `GEN_CAPABILITY`: `1`
- `PSSE_CONTROL_SELECTIVE_FREEZE`: `2`
- `VSC_CAPABILITY`: `1`
- `PSSE_CONTROL_FREEZE`: `1`
- `VSC_CAPABILITY_MARGIN_INCREASE`: `190`
- `VSC_CAPABILITY_LIMIT`: `1`

## Figures

- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\beerten_vsc\pv_curves.png`
