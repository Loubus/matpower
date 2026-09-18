# All voltage curves — corrected restoration policy

Measured source: `../verified/full_050_release1.mat`, 90 accepted points. See [the report](../REPORT.md) for the implementation and verification.

- `all_ac_bus_pv.png`: seven AC network buses.
- `all_station_node_pv.png`: six station filter/internal AC nodes.
- `all_dc_bus_pv.png`: three DC buses, with a magnified voltage scale.
- Matching `.fig` files retain editable MATLAB figures.
- `all_voltage_traces.csv`: all 16 voltage traces and common loading coordinates.
- `summary.json`: exact peak, final point, restoration count and termination flags.

Blue denotes increasing demand; orange denotes continuation after the first maximum. Red crosses mark the last accepted point. The FULL request stops at `vsc_capability_limit`, before λ = 0; these curves do not represent completed FULL continuation or a validated stability margin. They include points beyond operating voltage criteria.

Regenerate using `render_branch_preserving_pv` after adding the parent folder to the initialized MATLAB project path.
