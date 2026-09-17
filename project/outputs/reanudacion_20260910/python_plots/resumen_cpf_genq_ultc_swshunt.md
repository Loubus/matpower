# CPF TRANSPA con GENQ, ULTC y switched shunts activos

Escenario diagnostico sobre `case_transpa_reduced_v1_explicit`.

## Configuracion

- `solved_snapshot_policy.enable_genq_control = true`
- `psse.system.solver.VARLIM = 99`
- `psse.system.solver.ACTAPS = 1`
- `psse.system.solver.SWSHNT = 1`
- `cpf.enforce_q_lims = 0`; se usa GENQ PSS/E, no el limite Q generico de MATPOWER.
- Target de carga: `1.15x`.
- Entrada efectiva: `runpf_psse + active-set sync + runcpf` con `mp.xt_psse`.

Nota de graficacion: las curvas PNG unen puntos aceptados antes de calcular el nuevo tangente. Las `*_accepted_curve_v5.png` conectan todos los puntos finales; las `*_accepted_segmented_v6.png` cortan la curva cuando una re-correccion PSS/E produce un salto discreto; las `*_accepted_event_bridges_v7.png` evitan huecos largos mostrando esos saltos con trazo punteado diagnostico.

## Resultado

| Metrica | Valor |
|---|---:|
| success | 1 |
| max_lambda | 0.942857500711276 |
| points | 354 |
| events | 301 |
| final_min_v_bus | 322 |
| final_min_v | 0.515356633046949 |
| load_scale | 1.15 |

## GENQ final

| Campo | Valor |
|---|---:|
| enabled | 1 |
| active | 48 |
| local | 45 |
| remote | 3 |
| limited_count | 16 |
| at_min_count | 3 |
| at_max_count | 13 |
| num_adjustments | 16 |

## Eventos

| Evento | Conteo |
|---|---:|
| NOSE | 1 |
| PSSE_GENQ | 9 |
| PSSE_SWSHUNT | 34 |
| PSSE_XFMR | 257 |

## Figuras

- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_boundary_ports_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_buses_500kv_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_switched_shunt_buses_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_generator_buses_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_genq_regulated_buses_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_ultc_terminal_buses_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_worst_40_voltage_drop_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_curve_only_v2.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_accepted_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_accepted_segmented_v6.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_accepted_event_bridges_v7.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_complete_curve_v3.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_complete_curve_v5.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_lowest_40_final_voltage_accepted_points.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_page_01.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_page_02.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_page_03.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_page_04.png`
- `C:\Users\Santiago\Documents\PROYECTO FINAL DE CARRERA - MATPOWER\outputs\reanudacion_20260910\python_plots\pv_all_physical_page_05.png`
