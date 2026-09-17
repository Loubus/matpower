# Beerten 5-bus CPF run

Run id: `cleanup_batch1_smoke`.

Case: `case5_vsc_mtdc_beerten_paper_controls_cap_explicit`.

Target: `case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit`.

Mode: `psse`.

Entry point: `runcpf_psse`.

VSC-HVDC enabled: `1`.

Controls: `ACTAPS=1`, `SWSHNT=1`.

Devices: `switched_shunt=1`, `ultc_transformer=1`.

Stop condition: `cpf.stop_at = 5.000000e-02`.

CPF step settings: `cpf.step = 0.025`, `cpf.step_max = 0.025`.

## Results

- success: `1`
- max lambda: `0.0499999229727`
- CPF points: `4`
- CPF events: `0`
- final minimum active-bus voltage bus: `5`
- final minimum active-bus voltage: `0.988823529404 pu`
- final minimum voltage bus: `5`
- final minimum voltage: `0.988823529404 pu`
- done message: `Reached desired lambda 0.05 in 3 continuation steps.`

## Timing

- CPF solve seconds: `0.877`
- plot/write seconds after CPF: `0.000`
- total script seconds: `0.930`

## Event Counts


## Figures

