# B2: preserve incoming tangent across all active-set stages

This is an isolated follow-up to Experiment B. The only numerical change is initialization of the carried tangent at the start of each CPF trial: use the accepted incoming tangent and its variable identities, rather than an empty carrier. Existing VSC and generator transitions can replace that carrier as before. The outgoing tangent is therefore transported and oriented consistently even when the sole active change is a tap or shunt move.

Discrete tap/shunt electrical settlement stays at fixed lambda. Converter Q/P projection and its inward margin, generator limits, cases, options, tolerances, and endpoint definition are unchanged. Exact event localization remains unimplemented. This variant does not introduce coupled physical-limit equations.

`incremental.diff` isolates the change from B. `b17a_run(.1)` and `b17a_run(.05)` write new standard result files without overwriting B results. Production and historical outputs remain untouched.

## Completed numerical runs

Both requested CPF runs completed their configured stopping policy, but neither completed FULL:

| Quantity | Step 0.1 | Step 0.05 |
|---|---:|---:|
| Accepted points | 43 | 77 |
| Maximum accepted loading | 1.243784919600 | 1.244125681401 |
| Final accepted loading | 0.603064704847 | 0.603048242023 |
| Decreasing-loading steps | 21 | 34 |
| Augmented correction attempts | 73 | 83 |
| Terminal stage | VSC capability | VSC capability |
| Solver success scope | configured stop | configured stop |
| FULL endpoint reached | No | No |

These trajectories reproduce B's behavior to numerical roundoff. In B, the descending tap changes already coincided with a converter projection correction that supplied the incoming tangent. Thus extending the carrier to all stages does not materially change this particular projection-based trajectory. It is nevertheless necessary for the general algorithm: a coupled current-boundary formulation does not perform those repeated Q projections, so a tap-only change can expose the original reset-to-positive-loading error.

The terminal mechanism and limitations remain those documented in `../summary.md`: converter 3 reaches its current limit near bus-5 voltage 0.23570226 p.u.; repeated radial projection and network recorrection drive a worsening voltage/current feedback. Event localization is still approximate, and the maximum accepted loading is not an exact nose value. The all-controls tangent transport repairs traversal orientation; it does not repair the physical boundary enforcement policy or certify infeasibility.
