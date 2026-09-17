# Case families

Each family has its own folder. `source_manifest.json` records exact paths, hashes and provenance; paths in that manifest are relative to this folder.

- `full_network/raw/`: full PSS/E input preserved without conversion.
- `beerten/variants/`: the 16 existing project case functions, including targets and control variants. They are not 16 independent published benchmarks.
- `beerten/upstream/`: original MatACDC reference bundle and extracted cases, separate from project variants.
- `ieee/14`, `ieee/30`, `ieee/39`, `ieee/57`: exact snapshots of the current local MATPOWER case functions. The 30-bus selection is `case_ieee30`, not `case30`.
- `ieee/upstream/PowerModelsACDC/`: downloaded hybrid references, pending adapter work.
- `nordic/upstream/`: downloaded Nordic A/B loadflow and dynamic/control data.
- `cigre/upstream/`: downloaded CIGRE B4 implementation, pending audit and DCS1 extraction.

Published data, local modifications and future VSC/control adaptations must remain distinguishable. Upstream files have not been converted or validated by this cleanup. The vendor originals remain in `matpower/data` for existing tests and tooling; normal project startup prioritizes the organized copies. Do not edit both copies independently.

See [benchmark details](../docs/BENCHMARKS.md) for source variants, intended roles and limitations.
