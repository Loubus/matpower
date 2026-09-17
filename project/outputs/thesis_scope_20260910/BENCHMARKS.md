# Benchmark shortlist and collected sources

Reviewed 2026-09-10. Files in `upstream/` are unmodified reference inputs, not installed dependencies. No new benchmark was converted, executed or validated. [source_manifest.json](source_manifest.json) records exact source URLs, repository revisions, lengths and SHA-256 hashes. Matrix counts were inspected statically; they do not establish solver compatibility or correctness.

## Recommended selection

Updated after the user's clarification: use several transmission benchmarks, including Nordic, IEEE systems beyond New England 39, and an additional CIGRE case. The main suite is IEEE 30, New England 39, IEEE 57, Nordic, and CIGRE B4 DC Grid; Beerten and IEEE 14 support small checks. Build documented VSC additions/replacements from the AC baselines. CIGRE B4 is a planned member of the main suite with a hybrid AC/DC validation role; it is distinct from the Nordic AC network.

| Main benchmark | Existing source | Intended validation role |
|---|---|---|
| IEEE 30 | Local `matpower/data/case_ieee30.m` | First repeatable AC/VSC corridor comparison and control interaction tests |
| New England 39 | Local `matpower/data/case39.m` | Transfer/redispatch comparison on a different transmission topology |
| IEEE 57 | Local `matpower/data/case57.m` | Larger control-interaction and robustness checks |
| Nordic32, IEEE PES-TR19 variant | Downloaded RAMSES A/B files | Voltage-stability mechanisms and transformer/generator-limit interactions |
| CIGRE B4 DC Grid, initially the DCS1 two-terminal subsystem | Downloaded ELECTA transcription plus original publication/reference-report links | Independent VSC link power-balance, loss, voltage-control and capability checks; verify the transcription and subsystem mapping before use |

These roles are proposed experimental uses, not claims of completed validation. Use a shared runner, scenario schema and report format across the suite. Integrate cases sequentially while retaining all five in the agreed plan. IEEE 14 is available locally for faster control checks; it is not counted as one of the medium-sized cases. IEEE 118 is also available but is an optional later scale check. CIGRE B4 is already hybrid AC/DC, so its native reference validation differs from the paired corridor adaptations on the AC benchmarks. Added capability or discrete-control assumptions must be identified; the DCS1 subset has not yet been extracted or solved.

Audit the exact baseline versions before adaptation: local `case_ieee30.m` documents a 2025 transformer-tap modification; `case30.m` is a different modified formulation and should not be silently substituted. `case57.m` also documents generator-Q-limit changes. AC case files do not automatically provide complete ULTC deadbands, switched-shunt blocks, converter bases, or capability curves. Added or inferred parameters must be recorded as thesis assumptions. See the [MATPOWER data repository](https://github.com/MATPOWER/matpower/tree/master/data) and [IEEE PES-TR19](https://resourcecenter.ieee-pes.org/publications/technical-reports/pestr19) for source context.

The previously collected hybrid cases below are additional references; they do not define the required topology of the new paired AC/VSC experiments.

| Candidate | Actual size in gathered source | Available material and status | Recommendation |
|---|---|---|---|
| Beerten/Stagg | 5 AC; 2 DC for point-to-point or 3 DC for MTDC | Official MatACDC1.0 archive and 8 original case files downloaded; local project variants already exist | First PF reference and point-to-point mapping check |
| IEEE RTS-derived AC/DC | 50 AC + 7 DC, 7 converters | Original MatACDC AC/DC pair plus combined PowerModelsACDC `.m` file downloaded. Filename `case24` refers to its RTS ancestry, not the total bus count | Alternative larger benchmark |
| New England 39-bus AC/DC adaptation | 39 AC + 10 DC, 10 converters | PowerModelsACDC `.m` file downloaded; adapter and control/capability audit required | Additional PF reference; main paired study starts from the AC baseline |
| IEEE PES Nordic / Nordic32 | Operating point A: 74 AC/20 machines; B: 77 AC/23 machines. 32 denotes transmission buses | RAMSES A/B loadflow and dynamic/control data downloaded from SPS-L; no native VSC | Best control/voltage-stability candidate; AC conversion first |
| CIGRE B4-based implementation | Gathered file: 11 AC + 15 DC rows, 11 converters | ELECTA transcription downloaded; embedded note says converter parameter assumptions will be provided. Function/file names differ. Full fidelity unverified | Main suite: verify against original tables, then map DCS1 first; full meshed-grid extensions remain outside the initial implementation |
| Published modified IEEE9 | 9 AC with a 3-terminal VSC adaptation reported by Yuan et al. | Paper located; no machine-readable VSC case download verified in this search | Literature lead, not ready-to-run input |
| Published “16-bus AC/DC” | Huang et al.: 14 AC + 2 DC | Article located; no machine-readable download verified | Optional paper replication; not a standard IEEE16 AC network |

The local `matpower/data/case9.m` is an AC starting point, not evidence of a validated VSC9 model. Local `case16ci.m` and `case16am.m` describe distribution networks and are not suitable merely because their names contain 16. Any added VSC, ULTC or shunt must be distinguished from the original published data.

## Sources and provenance notes

**MatACDC.** The author's [KU Leuven page](https://www.esat.kuleuven.be/electa/teaching/matacdc) provides the [archive](https://www.esat.kuleuven.be/electa/teaching/matacdc/MatACDC1_0) and [manual](https://www.esat.kuleuven.be/electa/teaching/matacdc/MatACDCManual). Its [2015 software paper](https://doi.org/10.1049/iet-gtd.2014.0545) explains the reference framework. The license page permits personal modification and requires acknowledgment, but requires written permission for redistribution or distribution of derivatives. Preserve the local reference bundle and do not assume it can be republished with the thesis code. The archive includes software/manual as supplied; only case files were extracted, and nothing was added to MATLAB's path.

**PowerModelsACDC.** [Maintainer repository](https://github.com/Electa-Git/PowerModelsACDC.jl), [39-bus data](https://github.com/Electa-Git/PowerModelsACDC.jl/blob/b6d7cdb07ff6ae864f41c1187ed289aa289a78d3/test/data/case39_acdc.m), [RTS-derived data](https://github.com/Electa-Git/PowerModelsACDC.jl/blob/b6d7cdb07ff6ae864f41c1187ed289aa289a78d3/test/data/case24_3zones_acdc.m). Repository license is BSD-3-Clause; retain case-specific notices too. The [format documentation](https://electa-git.github.io/PowerModelsACDC.jl/dev/parser/) describes its extensions. This is a data source and potential independent PF reference; the Julia package was not installed. Published PF/OPF inputs are not prevalidated CPF benchmarks.

**Nordic.** [SPS-L repository](https://github.com/SPS-L/stepss-IEEE-Nordic-Test-system) identifies the IEEE PES-TR19 system and documents the A/B bus-count difference. License: Apache-2.0. [IEEE PES-TR19](https://resourcecenter.ieee-pes.org/publications/technical-reports/pestr19) is the defining report. Preserve generator/transformer/load details and map relevant LTC/OEL rules from the dynamic files. A CPF approximation to those rules must be declared; it cannot claim reproduction of the original dynamic trajectory. The source's report that its cases run is not a local verification.

**CIGRE.** [Original B4 publication](https://www.e-cigre.org/publications/detail/elt-270-9-the-cigre-b4-dc-grid-test-system.html) and [DIgSILENT/UC3M loadflow report](https://www.digsilentiberica.es/uploads/articles/CIGRE%20B457%20B458%20DC%20GRID%20TEST%20SYSTEM%20for%20LF%20in%20PowerFactory.pdf) provide the reference context. Original converter-terminal counts and DC junction/pole counts must not be conflated. The downloaded [ELECTA transcription](https://github.com/Electa-Git/PowerModelsTopologicalActions.jl/blob/83db29405c522311c10fc681935291861c80ff17/test/data_sources/cigre_b4_dc_grid.m) is a later implementation, not an untouched official case. Its file header specifies CC BY 4.0, while the surrounding repository has BSD-3-Clause licensing; retain the file-specific attribution. Its placeholder header and converter-assumption note require review before using it as a numerical oracle. A two-terminal subset is more relevant to the hydro corridor than implementing the entire meshed benchmark. The newer [TB804 package](https://www.e-cigre.org/publications/detail/804-dc-grid-benchmark-models-for-system-studies.html) has access/payment conditions; it was not purchased or downloaded.

**9/16-bus literature leads.** [Yuan et al., dynamic VSC-MTDC study](https://doi.org/10.1049/iet-gtd.2017.0589) uses a modified IEEE9 network; [Huang et al., holomorphic AC/DC PF](https://ietresearch.onlinelibrary.wiley.com/doi/full/10.1049/iet-gtd.2020.1227) includes the 14 AC + 2 DC example. These findings do not establish complete accessible input datasets. The [PNNL-38364 report](https://www.pnnl.gov/main/publications/external/technical_reports/PNNL-38364.pdf) is another VSC/MTDC modeling lead, but its EMT-focused 9-bus and MVDC 16-bus applications are lower priority for this project.

## Import gate for any selected benchmark

1. Preserve originals and citations. Record all adaptations separately.
2. Map AC and DC bases, number of poles, DC resistance, voltage conventions, converter power signs, loss units, transformer/filter/reactor data and ratings.
3. Identify control modes and valid references for every AC/DC island. Do not treat `.convdc` as interchangeable with this project's `.vsc` table.
4. Reproduce a source PF solution under matching assumptions; audit capability feasibility separately from convergence. Do not quietly change source values to pass.
5. Add one feature at a time and define a CPF stress/dispatch path. A source lacking discrete control metadata cannot validate that feature without a declared extension.

The collection helper is [collect_sources.py](collect_sources.py). It deliberately refuses to overwrite existing downloaded files; use a fresh task directory if recollecting. It performs network downloads and static inventory only. The original MatACDC archive is retained alongside the selected data and licenses.
