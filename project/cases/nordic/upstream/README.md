# IEEE Nordic Test System

**The IEEE Nordic test system for voltage stability analysis, in RAMSES format.**

This repository holds the Nordic variant detailed in the IEEE PES technical report [PES-TR19, "Test Systems for Voltage Stability Analysis and Security Assessment"](https://resourcecenter.ieee-pes.org/publications/technical-reports/PESTR19.html), prepared for use with the [STEPSS](https://stepss.sps-lab.org/) power system simulation platform (RAMSES dynamic simulator and stepss Python API).

The system has 74 buses (including 20 generator buses), 20 synchronous machines with detailed dynamic models, and voltage levels of 400/220/130 kV plus generator and distribution buses. It is a well-known benchmark for long-term voltage stability studies and dynamic security assessment.

## Contents

| Path | Description |
|------|-------------|
| `lf_A.dat`, `lf_B.dat` | The network and the operating point: buses, lines, transformers, loads, generation and the solved voltages, for operating points A and B. Read by both engines |
| `lf_B_plus_*.dat` | Operating point B with total load increased by 25-500 MW |
| `dyn_A.dat`, `dyn_B.dat` | Dynamic data only (machines, exciters, governors, PSS, LTCs, OELs). Loaded together with the matching `lf_*.dat` |
| `volt_rat_A.dat`, `volt_rat_B.dat`, `volt_rat_B_plus*.dat` | Solved voltages and transformer ratios as the HELIOS `VT` command writes them. The `lf_*.dat` files already carry both, so a run does not need these |
| `obs.dat` | Observables selection |
| `settings1.dat` | Solver settings |
| `uvls.dat` | Undervoltage load-shedding (UVLS) controllers |
| `*.dst` | Disturbance scenarios: no-disturbance run, branch/generator trips, LTC changes, Jacobian export for eigenanalysis (`eigen.dst`, `dampJac.dst`) |
| `cmd.txt` | RAMSES command file for operating point A |
| `nordic.cfg` | STEPSS scenario file: opens operating point A with `trip_branch.dst` in the STEPSS GUI, through **File > Load configuration**. Paths are relative to this folder, so it travels with a copy or a move |
| `nordic.svg` | One-line diagram template, with `%A`-`%U` placeholder codes substituted by the Helios `1` command |
| `doc/` | Documentation: Nordic test system report V6 and operating-point variants description |
| `jupyterhub-tutorial/` | stepss tutorial notebooks used in the [EEN452 course](https://sps-lab.org/courses/een452/): a first dynamic simulation (`Execute.ipynb`) and the full HELIOS power-flow → RAMSES workflow (`PowerFlowToDynamics.ipynb`). They read the data files in this directory rather than keeping copies |

## Quick Start

With [stepss](https://stepss.sps-lab.org/python/):

```python
import stepss
case = stepss.cfg()
case.addData('lf_B.dat')
case.addData('dyn_B.dat')
case.addData('settings1.dat')
case.addDst('trip_gen.dst')
case.addObs('obs.dat')
sim = stepss.sim()
sim.execSim(case)
```

Or run the RAMSES executable directly with the `cmd.txt` command file. Run scripts from the repository root so that relative paths to the data files resolve.

### One-line diagram

`nordic.svg` is a one-line diagram template in the HELIOS placeholder format, following the
area grouping of Figure 1 in `doc/Nordic_test_system_V6.pdf` with the connections redrawn
orthogonally so the annotations fit. Solving any operating point and rendering the template
fills in every number:

```python
from stepss.helios import HeliosSession

with HeliosSession() as pf:
    pf.load_file("lf_B.dat")
    pf.solve()
    pf.write_diagram("nordic.svg", "nordic_B.svg")
```

The same substitution is available from the HELIOS text interface with the `1` command. The
template annotates the voltage magnitude and phase angle at every bus, the active and
reactive output of every machine, the active and reactive load at the 22 distribution buses,
the reactive output of the 11 shunt devices, and the active and reactive flow at both ends of
all 33 400 kV lines. Flows are given at the bus end shown, positive out of the bus into the
branch.

The 130 kV and 220 kV lines and the transformers are drawn but deliberately left unannotated:
annotating those as well puts about 450 numbers on one sheet and stops it being readable.

The template is drawn for operating point B, which models the plants at buses 4047, 4051 and
4063 as two units each and so has 77 buses and 23 machines. Operating point A models each of
those three as a single unit, so rendering `lf_A.dat` leaves the paired units `g15b`, `g16b`
and `g18b` reading `unknown`. Everything else on the sheet is complete for both, because the
two operating points differ in nothing else: same buses otherwise, same 52 lines, same
shunts.

## One file set, both engines

A case is its `lf_*.dat` and its `dyn_*.dat`, in that order, plus `settings1.dat`. RAMSES
reads all three; HELIOS reads the same three and takes what it recognises. There is no
separate power-flow file set to swap in.

```python
from stepss.helios import HeliosSession

with HeliosSession() as pf:
    pf.load_file("lf_A.dat")        # the same file the dynamic run loads
    pf.solve()
```

The dynamic files carry no buses, lines or transformers of their own, so nothing is declared
twice and the two engines cannot drift apart on what the network is.

## Status

**Runs.** Operating point A via `cmd.txt`, and operating point B with the `trip_branch.dst`
and `trip_gen.dst` scenarios, all initialise and simulate. Every operating point also solves
as a power flow and renders the one-line diagram.

`jupyterhub-tutorial/PowerFlowToDynamics.ipynb` is the reference tutorial for the whole
platform: it takes the system from a HELIOS power flow, through a load increase, to a RAMSES
dynamic simulation of a generator trip.

Verified against **stepss 3.77** (RAMSES 3.77, HELIOS 1.4.1) on Linux.

## Documentation

The data formats are documented in the STEPSS user guide at [stepss.sps-lab.org](https://stepss.sps-lab.org/). The test system itself is described in `doc/`:

- **Nordic_test_system_V6.pdf**: detailed system report (T. Van Cutsem);
- **variants.pdf**: description of the operating-point variants.

The defining IEEE PES technical report [PES-TR19](https://resourcecenter.ieee-pes.org/publications/technical-reports/PESTR19.html) is available from IEEE (© IEEE, not redistributed here).

## Citation

If you use this test system in your research, please cite the IEEE PES technical report:

> IEEE PES Task Force on Test Systems for Voltage Stability Analysis and Security Assessment, "Test Systems for Voltage Stability Analysis and Security Assessment," Technical Report PES-TR19, Aug. 2015.

## License

This repository is licensed under the [Apache License 2.0](LICENSE).

## Authors

Developed and maintained by the [Sustainable Power Systems Laboratory (SPS-L)](https://sps-lab.org/) at the Cyprus University of Technology, under the direction of Dr. Petros Aristidou.

Original test system data by Dr. Thierry Van Cutsem (University of Liège) and the IEEE PES Task Force on Test Systems for Voltage Stability Analysis and Security Assessment.
