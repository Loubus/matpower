# IEEE / New England transmission benchmarks

The project startup adds the four numbered folders to the MATLAB path:

| Folder | Case function | Role |
| --- | --- | --- |
| `14/` | `case14` | Small AC checks |
| `30/` | `case_ieee30` | Medium transmission benchmark |
| `39/` | `case39` | New England transmission benchmark |
| `57/` | `case57` | Additional medium transmission benchmark |

These are exact snapshots of the current local case files, including their documented prior modifications. `case_ieee30` and `case30` are different formulations. Existing transformer ratios and fixed susceptances do not specify complete automatic ULTC/shunt controls. Future additions need explicit parameters and provenance.

`upstream/PowerModelsACDC/` contains separate downloaded hybrid references. It is not added to the path and is not yet adapted to this solver. No paired AC/VSC corridor scenarios were created in the cleanup.
