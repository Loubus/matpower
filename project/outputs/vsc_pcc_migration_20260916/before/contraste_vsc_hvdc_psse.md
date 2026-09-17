# Contraste VSC HVDC PSS/E vs implementacion MATPOWER

## Alcance

Esta nota resume la investigacion sobre como PSS/E modela una linea VSC HVDC de dos terminales en regimen permanente y la compara con la implementacion VSC-MTDC actual en MATPOWER.

El objetivo es contrastar modelos, no copiar el comportamiento de PSS/E. Quedan explicitamente fuera de alcance:

- dinamica;
- OPF;
- capability curves;
- cambios al modelo de estacion ya implementado;
- limites fisicos VSC/DC como objetivo principal de esta etapa, salvo para entender la diferencia con PSS/E.

La conclusion principal es que PSS/E implementa un objeto especifico `vscdc` de dos terminales, mientras que la implementacion actual de MATPOWER apunta a un modelo VSC-MTDC mas general, con red DC explicita y estacion AC detallada.

## Fuentes revisadas

Documentacion local de PSS/E 36.6:

- `C:\Program Files\PTI\PSSE36\36.6\DOCS\DataFormats.pdf`
  - Seccion `1.19 Voltage Source Converter (VSC) DC Transmission Line Data`.
  - Seccion `1.19.1 VSC DC Line Data`.
- `C:\Program Files\PTI\PSSE36\36.6\DOCS\POM.pdf`
  - Seccion `6.3.17 DC Lines`.
- `C:\Program Files\PTI\PSSE36\36.6\DOCS\PSSE_Reference.pdf`
  - Referencias a entrada/salida y reporte de datos de VSC DC line.
- Sphinx/API local:
  - `C:\Program Files\PTI\PSSE36\36.6\DOCS\Sphinx\psspy\VscDcLineData.html`
  - `C:\Program Files\PTI\PSSE36\36.6\DOCS\Sphinx\psspy\VscDcLineConverterData.html`
  - `C:\Program Files\PTI\PSSE36\36.6\DOCS\Sphinx\pfcontrol\pfcntlvsc.html`
  - paginas `avscdc*` y `avscdcconv*`.

Archivos MATPOWER relevantes:

- `matpower\lib\idx_vsc.m`
- `matpower\lib\runpf_vsc_mtdc.m`
- `matpower\lib\runpf_vsc_mtdc_unified.m`
- `matpower\lib\runcpf_vsc_mtdc.m`
- `matpower\lib\apply_vsc_ac_model.m`
- `matpower\lib\calc_vsc_losses.m`
- `matpower\data\case5_vsc_mtdc_beerten.m`
- `matpower\lib\t\t_vsc_mtdc.m`

## Modelo two-terminal VSC en PSS/E

PSS/E define un modelo de VSC DC line de dos terminales. La documentacion indica que sirve para representar:

- un enlace punto a punto;
- un esquema back-to-back;
- dos convertidores VSC conectados por una resistencia DC.

No es un modelo MTDC general. La topologia esta cerrada en el objeto `vscdc`: una linea DC y dos convertidores.

### Formato RAW

El bloque VSC DC line usa tres registros principales:

```text
NAME, MDC, RDC, O1, F1, O2, F2, O3, F3, O4, F4
IBUS, TYPE, MODE, DCSET, ACSET, ALOSS, BLOSS, MINLOSS, SMAX, IMAX, PWF, MAXQ, MINQ, VSREG, NREG, RMPCT
IBUS, TYPE, MODE, DCSET, ACSET, ALOSS, BLOSS, MINLOSS, SMAX, IMAX, PWF, MAXQ, MINQ, VSREG, NREG, RMPCT
```

En RAWX, el objeto aparece como tabla `"vscdc"` con campos equivalentes:

```text
name, mdc, rdc,
o1, f1, o2, f2, o3, f3, o4, f4,
ibus1, type1, mode1, dcset1, acset1, aloss1, bloss1, minloss1, smax1, imax1, pwf1, maxq1, minq1, vsreg1, nreg1, rmpct1,
ibus2, type2, mode2, dcset2, acset2, aloss2, bloss2, minloss2, smax2, imax2, pwf2, maxq2, minq2, vsreg2, nreg2, rmpct2
```

### Campos de linea

- `NAME`: identificador de la linea VSC DC.
- `MDC`: estado de la linea.
  - `0`: fuera de servicio.
  - `1`: en servicio.
- `RDC`: resistencia DC en ohmios.
- `O1..O4`, `F1..F4`: propietarios y fracciones.

### Campos de convertidor

- `IBUS`: bus AC del convertidor.
- `TYPE`: modo de control DC del convertidor.
- `MODE`: modo de control AC del convertidor.
- `DCSET`: consigna DC, cuyo significado depende de `TYPE`.
- `ACSET`: consigna AC, cuyo significado depende de `MODE`.
- `ALOSS`, `BLOSS`, `MINLOSS`: parametros de perdidas.
- `SMAX`: rating MVA del convertidor.
- `IMAX`: rating de corriente AC.
- `PWF`: factor de ponderacion para reduccion de P/Q ante violacion de limites.
- `MAXQ`, `MINQ`: limites de potencia reactiva.
- `VSREG`, `NREG`: bus/nodo regulado en modo tension AC.
- `RMPCT`: participacion relativa en control de tension compartido.

## Controles PSS/E

### Control DC: `TYPE`

PSS/E define tres modos principales de control DC:

- `TYPE = 0`: convertidor fuera de servicio.
- `TYPE = 1`: control de tension DC.
- `TYPE = 2`: control de potencia activa MW.
- `TYPE = 3`: control de angulo del bus AC del convertidor.

Restriccion importante:

- si los dos convertidores estan en servicio, exactamente uno debe estar en `TYPE = 1`, es decir, debe haber un unico convertidor controlando tension DC.

Interpretacion de `DCSET`:

- con `TYPE = 1`, `DCSET` es la tension DC programada en kV;
- con `TYPE = 2`, `DCSET` es la demanda de potencia activa en MW;
- con `TYPE = 3`, `DCSET` es el angulo AC del bus convertidor en grados.

La convencion de signo documentada para `TYPE = 2` es:

- `DCSET > 0`: el convertidor inyecta potencia activa hacia la red AC en `IBUS`;
- `DCSET < 0`: el convertidor absorbe potencia activa desde la red AC.

### Control AC: `MODE`

PSS/E define dos modos AC principales:

- `MODE = 1`: control de tension AC.
- `MODE = 2`: factor de potencia fijo.

Interpretacion de `ACSET`:

- con `MODE = 1`, `ACSET` es la tension AC regulada en pu;
- con `MODE = 2`, `ACSET` es el factor de potencia objetivo.

En `MODE = 1`, PSS/E tambien permite regular un bus remoto mediante:

- `VSREG`;
- `NREG`;
- `RMPCT`.

`RMPCT` permite repartir la contribucion reactiva con otros equipos que regulan el mismo bus, por ejemplo generadores, switched shunts, FACTS shunt o algun otro convertidor VSC.

## Perdidas PSS/E

PSS/E usa una ley de perdidas de convertidor basada en corriente DC:

```text
loss_kW = ALOSS + BLOSS * Idc
```

Ademas aplica un minimo:

```text
loss_kW >= MINLOSS
```

Esto contrasta con el modelo actual MATPOWER, que usa una ley tipo Beerten basada en corriente AC del convertidor y coeficientes `LOSS_A`, `LOSS_B`, `LOSS_C`.

## Limites PSS/E

PSS/E incluye limites estaticos de convertidor:

- `SMAX`: rating de potencia aparente MVA;
- `IMAX`: rating de corriente AC;
- `MAXQ`, `MINQ`: limites de potencia reactiva;
- `PWF`: ponderacion para decidir como se reducen P y/o Q ante una violacion.

Segun el POM, la logica de power flow revisa limites de forma distinta segun el modo:

- en factor de potencia fijo, los limites se revisan durante las iteraciones;
- en control de tension AC, los limites se revisan cuando se alcanza convergencia;
- si se viola el limite MVA/corriente, PSS/E reduce la carga del convertidor usando `PWF`;
- `PWF = 0` privilegia reducir potencia activa;
- `PWF = 1` privilegia reducir potencia reactiva;
- valores intermedios reparten la reduccion.

Esto no es OPF. Es parte del comportamiento de power flow estatico de PSS/E.

## Restricciones de buses en PSS/E

La documentacion impone restricciones sobre el bus AC del convertidor:

- para `TYPE = 1` o `TYPE = 2`, el bus debe ser tipo 1 o tipo 2;
- para `TYPE = 3`, el bus debe ser tipo 3;
- un convertidor no debe compartir bus con ciertos terminales FACTS incompatibles;
- tampoco debe quedar conectado por rama de impedancia cero a buses que violen esas restricciones.

Estas restricciones son especificas del modelo y del solucionador PSS/E.

## API PSS/E relevante

Las paginas Sphinx/API permiten consultar cantidades de linea y convertidor.

### Linea VSC DC

Algunas magnitudes reales de linea:

- `DCCUR`: corriente DC en amperes.
- `RDC`: resistencia DC en ohmios.
- `PLOSS`: perdidas activas MW.
- `QLOSS`: perdidas reactivas Mvar.

Algunas magnitudes enteras:

- `FROMNUMBER`, `TONUMBER`;
- `MDC`;
- propietarios.

### Convertidor VSC

Algunas magnitudes reales de convertidor:

- `ACAMPS`: corriente AC;
- `PUCUR`: corriente en pu;
- `PCTMVA`: porcentaje de carga sobre rating;
- `KVDC`: tension DC;
- `DCSET`, `ACSET`;
- `ALOSS`, `BLOSS`, `MINLOSS`;
- `SMAX`, `IMAX`;
- `PWF`, `RMPCT`;
- `PAC`, `QAC`, `MVA`;
- `PLOSS`, `QLOSS`;
- `MAXQ`, `MINQ`.

Algunas magnitudes enteras:

- `DCTYPE`;
- `ACMODE`;
- `IREG`;
- `NREG`;
- numero de convertidor.

La API `pfcntlvsc` permite leer/modificar algunas cantidades durante automatizaciones PCI:

- `DCSET`;
- `ACSET`;
- `ALOSS`;
- `BLOSS`;
- `QMAX`;
- `QMIN`;
- `QSET`.

## Implementacion MATPOWER actual

La implementacion VSC-MTDC actual esta organizada alrededor de:

- `mpc.busdc`;
- `mpc.branchdc`;
- `mpc.vsc`;
- modelo AC de estacion explicito;
- solucion PF secuencial y unified;
- solucion CPF unified monolitica.

### Estructura VSC

`idx_vsc.m` define columnas de entrada como:

- `VSC_BUS`;
- `BUSDC`;
- `VSC_STATUS`;
- `AC_MODE`;
- `DC_MODE`;
- `PAC_SET`;
- `QAC_SET`;
- `VAC_SET`;
- `PDC_SET`;
- `VDC_SET`;
- `KDROOP`;
- coeficientes de perdidas `LOSS_A`, `LOSS_B`, `LOSS_C`;
- parametros de transformador, filtro y reactor.

Tambien define columnas de salida como:

- `PAC`;
- `QAC`;
- `PDC`;
- `VDC`;
- tensiones internas de estacion;
- `PLOSS`;
- perdidas de transformador/reactor;
- flags e indices de buses/ramas generados.

### Modos DC

Los modos DC implementados son:

- `VSC_DC_VDC`: control de tension DC/slack DC;
- `VSC_DC_PDC`: control de potencia DC;
- `VSC_DC_DROOP`: droop DC.

### Modos AC

Los modos AC implementados son:

- `VSC_AC_Q`: Q fija, P queda determinada por el balance DC/perdidas;
- `VSC_AC_V`: tension AC controlada, P queda determinada por el balance DC/perdidas;
- `VSC_AC_PQ`: P y Q fijas;
- `VSC_AC_PV`: P fija y tension AC controlada.

### Modelo de estacion

El modelo de estacion incluye:

- transformador;
- filtro;
- reactor;
- bus interno del convertidor;
- bus PCC;
- perdidas distribuidas segun los parametros de la estacion.

Este punto es mas detallado que el modelo PSS/E two-terminal, que abstrae la estacion dentro del objeto convertidor.

### Perdidas MATPOWER

La funcion `calc_vsc_losses.m` implementa perdidas con coeficientes `LOSS_A`, `LOSS_B`, `LOSS_C`, dependientes de la corriente AC del convertidor.

Conceptualmente:

```text
P_loss = A + B * Iac + C * Iac^2
```

Esto es coherente con el modelo de estacion/convertidor tipo Beerten, pero no coincide con la ley PSS/E:

```text
P_loss = ALOSS + BLOSS * Idc
```

## Comparacion campo por campo

| PSS/E | MATPOWER actual | Comentario |
| --- | --- | --- |
| `NAME` | no equivalente principal | Se podria preservar como metadata. |
| `MDC` | `VSC_STATUS` y estado de ramas DC | Hay equivalencia conceptual, pero no objeto unico de linea VSC. |
| `RDC` | `branchdc` | Requiere conversion ohmios/pu. |
| `IBUS` | `VSC_BUS` | Equivalencia directa conceptual. |
| `TYPE = 1` | `DC_MODE = VDC` | Equivalencia razonable. |
| `TYPE = 2` | `DC_MODE = PDC` | Equivalencia parcial; requiere convencion de signos. |
| `TYPE = 3` | sin equivalente | No implementado. |
| `MODE = 1` | `AC_MODE = V` o `PV` | Equivalencia parcial; falta regulacion remota. |
| `MODE = 2` | sin equivalente directo | Falta factor de potencia fijo. |
| `DCSET` | `VDC_SET` o `PDC_SET` | Depende de `TYPE`; requiere mapping claro. |
| `ACSET` | `VAC_SET` o relacion PF ausente | Para tension si; para power factor no. |
| `ALOSS`, `BLOSS`, `MINLOSS` | `LOSS_A/B/C` | Modelos de perdidas distintos. |
| `SMAX`, `IMAX` | ausentes | Limites no implementados. |
| `PWF` | ausente | Reduccion P/Q ante limites no implementada. |
| `MAXQ`, `MINQ` | ausentes | Limites Q no implementados. |
| `VSREG`, `NREG` | ausentes en VSC | No hay regulacion remota VSC formal. |
| `RMPCT` | ausente en VSC | No hay reparto Mvar VSC estilo PSS/E. |
| two-terminal cerrado | MTDC general | MATPOWER actual es mas general en red DC. |

## Diferencias importantes de filosofia

### PSS/E

PSS/E modela el VSC HVDC como un dispositivo de power flow de dos terminales. El objeto contiene:

- red DC minima;
- dos convertidores;
- modos de control;
- perdidas;
- limites;
- reglas de participacion reactiva.

Es compacto y orientado a compatibilidad RAW/SAV.

### MATPOWER actual

La implementacion actual modela:

- una red DC explicita;
- convertidores como equipos conectando red AC y DC;
- estacion AC detallada;
- posibilidad MTDC;
- PF/CPF unified;
- validacion Beerten.

Es mas academica y extensible para MTDC, pero menos compatible con la semantica exacta de PSS/E.

## Brechas relevantes si se quisiera compatibilidad PSS/E

No hace falta cambiar el modelo de estacion. Las brechas estan en la capa de compatibilidad y en controles/limites estaticos:

1. Importacion/preservacion de `vscdc`
   - Guardar todos los campos RAW/RAWX PSS/E.
   - Mapear a `busdc`, `branchdc`, `vsc`.
   - Mantener metadata para round-trip o diagnostico.

2. Conversion de unidades
   - `RDC` de ohmios a pu DC.
   - `DCSET` kV/MW segun `TYPE`.
   - `ALOSS/BLOSS/MINLOSS` en kW.
   - `IMAX` en amperes.
   - tensiones AC/DC en bases coherentes.

3. Convencion de signos
   - PSS/E `DCSET > 0` en `TYPE = 2` significa inyeccion activa hacia la red AC.
   - En MATPOWER, `PAC`, `PDC` y el balance `Pac + Pdc + Ploss = 0` requieren una conversion explicita.
   - Este punto no debe quedar implicito porque es fuente probable de errores.

4. Factor de potencia fijo
   - Falta equivalente de `MODE = 2`.
   - Se puede emular en un punto con Q fija, pero no como relacion funcional durante la solucion.

5. Regulacion remota y reparto Mvar
   - Falta `VSREG/NREG/RMPCT` en el control VSC.
   - Hoy existen controles PSS/E externos para otras familias, pero el VSC no participa formalmente como equipo regulador remoto estilo PSS/E.

6. Modelo de perdidas PSS/E
   - Falta opcion `ALOSS + BLOSS * Idc` con `MINLOSS`.
   - No conviene reemplazar el modelo Beerten; conviene permitir ambos.

7. Limites estaticos
   - Falta `SMAX`.
   - Falta `IMAX`.
   - Falta `MAXQ/MINQ`.
   - Falta `PWF`.
   - Falta la logica de reduccion de P/Q usada por PSS/E cuando se violan limites.

8. `TYPE = 3`
   - Falta control de angulo AC del bus convertidor.
   - Puede implementarse como modo estatico o rechazarse explicitamente con mensaje claro.

9. Casos de prueba PSS/E
   - Faltan regresiones especificas two-terminal VSC.
   - Idealmente deberian compararse contra PSS/E cuando haya caso RAW/SAV disponible.

## Que no parece necesario copiar

No parece necesario copiar PSS/E en estos puntos:

- restringir el modelo a dos terminales;
- eliminar la red DC explicita;
- eliminar el modelo de estacion;
- abandonar el modelo unified;
- convertir el VSC-MTDC en un objeto monolitico tipo `vscdc`;
- agregar dinamica;
- agregar OPF;
- agregar capability curves.

La implementacion actual ya cubre mejor que PSS/E el caso MTDC como red DC general. PSS/E es mas fuerte como formato industrial de entrada/salida y en reglas especificas de control/limite de su objeto two-terminal.

## Recomendacion

La mejor estrategia no seria reemplazar el modelo actual por el de PSS/E, sino agregar una capa de compatibilidad:

1. `psse_vscdc` como metadata preservada.
2. Conversor `vscdc` -> `busdc/branchdc/vsc`.
3. Opcion de perdidas `psse`.
4. Modo AC de factor de potencia fijo.
5. Regulacion remota VSC con `VSREG/RMPCT`, si se quiere fidelidad PSS/E.
6. Limites estaticos PSS/E como eventos/active-set de power flow, no como OPF.
7. Rechazo explicito o implementacion acotada de `TYPE = 3`.

Para la tesis y el modelo Beerten/MTDC, la implementacion actual es conceptualmente suficiente. Para decir que se soporta de forma fiel el VSC two-terminal de PSS/E, faltaria principalmente esa capa de importacion, controles PSS/E y perdidas/limites estaticos compatibles.

