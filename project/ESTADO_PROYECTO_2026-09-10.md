# Estado de la tesis y verificación del entorno

Revisión local del 10 de septiembre de 2026. Evidencia nueva en `outputs/reanudacion_20260910/`.

## Pruebas nuevas y bloqueos confirmados

| Prueba | Resultado |
|---|---|
| PSS/E CLI: batería de validación | 69/69 casos convergieron, sin errores batch, con reportes, SAV y RAW exportados |
| MATPOWER: misma batería de validación | 69/69 casos convergieron con `runpf_psse` y la opción de coordinación usada por el comparador histórico |
| PSS/E CLI: casos TOTAL de 14 y 30 barras | Ambos correctos |
| PSS/E CLI: RAW completo `V26p_Trs_2532.raw` | Convergió en 2 iteraciones; reportes y exportaciones correctos |
| MATLAB: importador `t_psse` | 296/296 pruebas aprobadas |
| MATLAB: extensión `t_mpxt_psse` | 508/508 pruebas aprobadas |
| MATLAB: VSC-MTDC `t_vsc_mtdc` | 326/330 pruebas aprobadas; cuatro fallos |
| MATLAB: RAW completo | Convergió tanto con `runpf` como con `runpf_psse` |
| TRANSPA CPF sin controles | `success=1`, máximo lambda 0,239568152635; factor de carga 1,239568152635 |
| TRANSPA CPF con controles y capacidad | `success=0`; falla la resolución posterior a un cambio de capacidad de generador |
| Beerten CPF VSC-HVDC con controles y capacidad | `success=1`, 82 puntos, 203 eventos; aproximadamente 650 segundos, con avisos de matriz casi singular |
| Diagnósticos `psse_study_diagnostics` | Correctos sobre el resultado Beerten; 26 archivos exportados, con gráficos del diagnóstico desactivados en esta prueba |
| Python: gráficos existentes | 77 figuras generadas con Python instalado y `.venv`; una figura representativa inspeccionada visualmente |
| PowerShell: parser de scripts | Runner, generador y resumidor de la batería sin errores de sintaxis |

La regresión completa realizó **1.134 comprobaciones: 1.130 aprobadas y cuatro fallidas**, sin saltos. Duración: 733,58 segundos. El log general es `outputs/reanudacion_20260910/matlab_tests.log`; el detalle VSC se registra en `vsc_tests_detailed.log`.

Los cuatro fallos reproducidos de `t_vsc_mtdc` son:

| Nº de prueba | Área | Diferencia observada |
|---:|---|---|
| 110 | PF unificado VSC + shunt | No informa el cambio de conjunto de controles esperado para el switched shunt |
| 111 | PF unificado VSC + shunt | `BS=0`, mientras la prueba espera `BS=9` |
| 283 | CPF unificado VSC + GENQ | La barra queda PV (`2`), mientras la prueba espera PQ (`1`) |
| 284 | CPF unificado VSC + GENQ | `QG≈-33,8559`, mientras la prueba espera `QG=-20` |

Estos son desacuerdos con las expectativas de regresión; por sí solos no prueban cuál de las dos partes es incorrecta. Debe revisarse el comportamiento de los controles y la vigencia de las expectativas antes de modificar el código o los tests. No son errores de importación ni paquetes faltantes.

La comparación actual de los 69 casos usa los RAW recién exportados por PSS/E 34.9.3, no las referencias históricas de PSS/E 36. Con el criterio uniforme de revisión `max|dVM| > 0,005 pu`, aparecen siete casos: las cuatro variantes integradas de 14 barras (aproximadamente 0,00680–0,00682 pu) y tres variantes de estrés de 40 barras (0,00758–0,00879 pu). Son cuatro casos no destinados a estrés y tres de estrés; el criterio uniforme no debe confundirse con el filtro del informe histórico, que destacaba cuatro casos. Todos convergen, pero todavía hay diferencias de modelo/control. Evidencia: `suite_comparison_psse34.csv`, `matpower_suite.csv` y `psse_suite_runner.log`. Los casos de estrés emitieron avisos de matriz casi singular durante intentos intermedios, antes de devolver éxito.

**TRANSPA con capacidad activa:** el fallo quedó identificado como `control='gen_capability'`, `stage='post_control_cpf'`, con mensaje `PSS/E gen_capability control rebuild failed after rollback`. Se registraron 718 puntos y 28 eventos, con máximo lambda 0,222674742017. Aunque `cpf.done_msg` contiene un mensaje de límite de carga, el resultado global es fallido: esa cifra no debe presentarse como margen validado de estabilidad. El reporte automático etiqueta el factor como “at nose” incluso en esta corrida fallida; prevalecen `success=0` y `control_failure`. Evidencia en `transpa_failure_detail.log` y `transpa_controls/`.

**Comparación nueva de la red completa contra PSS/E 34.9.3:** se alinearon por número de barra 4.650 barras físicas activas comunes, excluyendo barras aisladas y auxiliares sintéticas. Se utilizaron los controles y tolerancias propios de cada ruta; es una comparación del resultado operativo, no una demostración de equivalencia exacta de algoritmos.

| Solver MATPOWER | Convergió | Máximo error VM (pu) | RMS error VM (pu) | Máximo error VA (grados) |
|---|---|---:|---:|---:|
| `runpf` | Sí | 0,202969784 | 0,019667359 | 6,484374339 |
| `runpf_psse` | Sí | 0,035363586 | 0,002843736 | 3,227144111 |

La extensión reduce la discrepancia, pero todavía no reproduce completamente el resultado PSS/E. Los ángulos se compararon directamente, sin ajuste adicional de referencia. Datos en `full_raw_comparison.csv`; verificación reproducible en `verify_full_comparison.m`.

**Beerten:** el preset `paper_controls_cap_nose` terminó en un límite de capacidad VSC, con lambda máximo 2,93061921892. Aunque el preset solicita `NOSE`, el mensaje final identifica un límite de capacidad, no necesariamente una nariz puramente AC. Registró 190 eventos `VSC_CAPABILITY_MARGIN_INCREASE`, además de cambios de controles/capacidad. La curva se exportó y se inspeccionó visualmente. Los avisos de matrices casi singulares y el coste de unos 11 minutos merecen revisión antes de emplear este caso en barridos extensos. Evidencia en `beerten_vsc/README.md`, `beerten_vsc/pv_curves.png` y `project_checks.log`.

## En qué punto quedó el proyecto

El proyecto tiene una implementación avanzada de flujo de potencia (PF) y flujo de continuación (CPF) sobre un fork de MATPOWER, con controles tipo PSS/E y modelos explícitos VSC-MTDC. La validación de los modelos reducidos y de los controles combinados sigue abierta. No corresponde considerar todos los escenarios listos para producir conclusiones finales de tesis.

Las líneas de trabajo presentes son:

- Importación RAW y controles PSS/E: generadores/reactiva, taps ULTC, shunts, FACTS, enlaces LCC de dos terminales, switching devices y opciones del solver. Entradas principales: `runpf_psse` y `runcpf_psse`.
- CPF AC/DC con VSC-MTDC: métodos secuencial/unificado, capacidad de convertidores y generadores, eventos y políticas de redispatch. El modelo explícito VSC-MTDC no pretende replicar íntegramente el dispositivo VSC de PSS/E.
- TRANSPA: equivalente externo multipuerto, caso explícito reducido, runner configurable, curvas PV y diagnósticos.
- Beerten: runner configurable de CPF para el caso VSC-HVDC, con variantes AC y límites de capacidad.
- SADI: reducción con inyecciones P/Q fijas en fronteras internacionales. Los últimos estudios, del 28 de junio, convergían con `ACTAPS=0`, pero no con `ACTAPS=1`, incluso aplicando la máscara de bloqueos de taps. El informe histórico atribuye el problema dominante a la respuesta de regulación eliminada por el equivalente fijo; esa explicación requiere validación adicional.

El último commit local de `matpower/` es `7f04707f`, del 25 de junio de 2026, rama `master`. Hay ocho archivos de código con cambios locales anteriores a esta revisión: controles TWODC/ULTC, estados/reportes de transformadores, `task_cpf_psse`, `runpf_psse` y su prueba `t_mpxt_psse`. Estos cambios son parte del estado efectivamente probado. No se revisaron ramas remotas.

Se guardó una copia de esas diferencias de código en `outputs/reanudacion_20260910/matpower_local_changes.patch`, junto con el estado e historial Git. El parche no se aplicó ni se creó ningún commit.

Git también muestra 810 cambios en documentación y copias de dependencias; al inspeccionar un ejemplo, un enlace simbólico versionado aparece materializado como contenido de código. No interpretar todo ese volumen como desarrollo nuevo. La raíz del proyecto no es un repositorio Git operativo; `matpower/` sí lo es.

No se encontró un manuscrito propio de tesis en Word/LaTeX dentro del árbol revisado; sí hay informes técnicos Markdown, referencias, manuales y resultados. Este informe evalúa principalmente el estado computacional.

## Entorno y requisitos

| Componente | Estado comprobado |
|---|---|
| MATLAB | R2025b; ejecución por `-batch` y flujo `case9` correctos |
| MCP de MATLAB | Comprobado adicionalmente mediante `evaluate_matlab_code`: responde, inicializa el proyecto y resuelve `case9` con éxito |
| MATPOWER | 8.1.1-dev; se usa el fork local, con MP-Core |
| Dependencias MATLAB | MP-Test 8.1, MIPS 1.5.2, MP-Opt-Model 5.1-dev y MOST 1.3.2-dev disponibles |
| PSS/E | 34.9.3, ejecutable `C:\Program Files (x86)\PTI\PSSE34\PSSBIN\pssecmd34.exe` |
| Capacidad PSS/E | La consola declara 50.000 barras; el RAW grande fue resuelto y exportado efectivamente |
| Python genérico | Inicialmente faltaba; se instaló Python 3.12.10 para el usuario mediante WinGet y se añadió al PATH |
| Python del proyecto | `.venv/Scripts/python.exe`, con NumPy 2.3.5 y Pillow 12.3.0; `pip check` correcto y 77 figuras generadas |
| Datos | RAW grande y sidecar `case_transpa_reduced_v1_psse.mat` presentes; los casos principales cargaron correctamente |

Los solvers de optimización externos que `mpver` informa como ausentes no son requisitos de los PF/CPF ejecutados. Python 2.7 también existe en la máquina, pero no sirve para el script moderno de gráficos.

## Correcciones de entorno realizadas

1. `PSSE/Solve-RawPowerFlow.ps1` ahora detecta las instalaciones conocidas 36.6, 36.1 y 34, manteniendo la selección explícita mediante `-PsseRoot`.
2. En PSS/E 34 usa `BAT_SOLUTION_PARAMETERS_4` (5 enteros y 19 reales) y `BAT_RATE_2`. La primera prueba había convergido pero rechazaba los comandos `_5` y `_3` de PSS/E 36. La corrección se contrastó con el manual API instalado y con ejecuciones posteriores.
3. La versión de RAW exportado se ajusta a la versión instalada; se registra el ejecutable utilizado en cada log.
4. Se añadió `iniciar_proyecto.m`, que configura las rutas de MATLAB para la sesión, y se corrigió la ruta faltante al subdirectorio del runner en el README de TRANSPA.
5. Se registraron las dependencias verificadas del script Python en `auditoria_psse_matpower/transpa_reduccion/requirements.txt`.
6. Con autorización expresa del usuario, se instaló Python 3.12.10 fuera de Codex y se creó `.venv` con esas dependencias. No depende del Python interno de PSS/E ni del runtime de Codex.
7. Se comprobó el MCP de MATLAB mediante llamadas reales. Su configuración local en `.codex/config.toml` apunta al ejecutable existente y a MATLAB R2025b. Se amplió `tool_timeout_sec` de 600 a 1800 segundos inicialmente y luego a 3600 segundos por solicitud del usuario. La configuración TOML se validó; el nuevo timeout queda sujeto a la recarga de configuración de Codex, sin una prueba de duración de una hora. La segunda verificación ejecutó directamente por MCP `runpf_psse` sobre `case9`, el analizador de `iniciar_proyecto.m` (cero incidencias) y el script `outputs/reanudacion_20260910/verify_mcp.m`: CPF hasta lambda 0.2, exportación PNG y guardado MAT, todos correctos. La sesión siguió respondiendo después. El modo efectivo es `nodesktop` (JVM disponible), admitido explícitamente por la ayuda del servidor v0.13.0; los registros indican modo de sesión `auto`. No se encontraron errores ni advertencias en los registros MCP disponibles de hoy. No se reprodujo el antiguo error de modo recordado por el usuario, ni fue necesario ejecutar los cálculos mediante CLI. Esta prueba verifica la integración MCP y no resuelve los fallos numéricos documentados en otras secciones.

Las referencias históricas RAW/SAV y sus resultados se conservaron; las verificaciones de hoy escriben en un directorio propio.

## Cómo retomar

Desde MATLAB, situado en la raíz del proyecto:

```matlab
iniciar_proyecto
r = runpf('case9', mpoption('verbose', 0, 'out.all', 0));
assert(r.success)

% Baseline TRANSPA sin controles: usar una carpeta nueva para cada estudio.
opts = transpa_cpf_preset('all_disabled_pv_only');
opts.outdir = fullfile(pwd, 'outputs', 'mi_transpa_baseline');
r = run_transpa_cpf_psse(opts);
assert(r.success)
```

Desde PowerShell, situado en la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\PSSE\Solve-RawPowerFlow.ps1 -RawFile TOTAL\psse_integrated_controls_14bus.raw -OutputDir ..\outputs\mi_psse_smoke -WriteSolvedRaw

powershell -NoProfile -ExecutionPolicy Bypass -File .\PSSE\Solve-RawPowerFlow.ps1 -RawFile V26p_Trs_2532.raw -OutputDir ..\outputs\mi_psse_full -WriteSolvedRaw
```

Las rutas relativas de `RawFile` y `OutputDir` se resuelven desde `PSSE/`. `-PsseRoot` permite fijar una instalación. Las comparaciones deben conservar la versión utilizada: los históricos de PSS/E 36 no son automáticamente intercambiables con los resultados nuevos de PSS/E 34.

El script Python se verificó sobre una copia de sus siete CSV de entrada, generando 77 figuras. Para repetir exactamente esa verificación desde la raíz:

```powershell
.\.venv\Scripts\python.exe outputs\reanudacion_20260910\verify_python.py
```

El entorno independiente de Codex ya está instalado. La ruta base es `%LOCALAPPDATA%\Programs\Python\Python312\python.exe`. Para usar el comando genérico `python` en una consola abierta antes de la instalación puede ser necesario abrir otra consola; la ruta `.venv\Scripts\python.exe` funciona directamente. No se modificó el Python de PSS/E.

## Documentos para recuperar el contexto

- `matpower/docs/other/VSC-MTDC-Architecture-Decision.md`: arquitectura y entradas soportadas.
- `auditoria_psse_matpower/transpa_reduccion/cpf_psse_runner/README.md`: runner TRANSPA actual.
- `auditoria_psse_matpower/beerten_5bus/cpf_runner/README.md`: runner Beerten actual.
- `auditoria_psse_matpower/psse_validation_suite/suite_comparison_summary.md`: último resumen histórico de 69 casos; registra cuatro casos en revisión. El informe fechado 24 de junio tiene resultados anteriores y no es el último estado.
- `auditoria_psse_matpower/results/sadi_pq_equivalent_actaps1_raw_snapshot_study_locked/study_locked_comparison_summary.md`: último bloqueo histórico del SADI.
- `auditoria_psse_matpower/16_auditoria_integral_reduccion_transpa_v1.md`: alcance y límites del equivalente TRANSPA, con cifras históricas.

Los README iniciales y `PSSE/CONTEXTO_PROYECTO.md` contienen rutas de PCs anteriores y estados de mayo; deben leerse como antecedentes.

## Orden sugerido para continuar la tesis

1. Resolver o justificar las cuatro discrepancias de la regresión VSC-MTDC y corregir la reconstrucción posterior a límites de capacidad de generadores en el CPF TRANSPA. No relajar las pruebas o desactivar límites para declarar resueltos estos problemas.
2. Usar la nueva solución PSS/E del RAW completo como referencia, conservando la versión y los parámetros efectivos. Priorizar las barras y controles responsables de la discrepancia residual de tensión.
3. Retomar la reducción SADI: distinguir validación del punto base con equivalentes P/Q de la capacidad del equivalente de reproducir respuestas de tensión/reactiva ante movimientos de taps.
4. Definir la matriz de escenarios y criterios de comparación que entrarán en la tesis. Separar parada por nariz, límite de capacidad, límite de control y fallo numérico en tablas y figuras.
5. Consolidar los cambios locales en una versión identificable y trasladar los resultados validados al manuscrito. Esta auditoría no modifica el historial Git ni las decisiones de modelado pendientes.

La verificación cubre los runners principales, las pruebas de regresión relacionadas con la tesis y la batería de 69 casos. No ejecuta todos los scripts históricos de experimentación ni toda la batería general de optimización de MATPOWER. Los estudios SADI de junio se inspeccionaron como antecedentes; no se reconstruyeron durante esta revisión.
