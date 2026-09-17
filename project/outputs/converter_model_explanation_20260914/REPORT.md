# VSC model explanation — 2026-09-14

Open [the standalone illustrated report](REPORT.html). It includes nine engineering sections, complete project/reference single-lines, the detailed station, 43 vector-rendered equations, actual terminal-power examples, capability comparisons, an interactive historical trace, code excerpts and primary references. It works offline.

The full station equations are electrically consistent, but PAC_SET/QAC_SET and PAC/QAC refer to the internal converter terminal while the capability geometry uses PCC voltage. At the historical C2 endpoint the surrogate indicates 99.9998% current utilization versus 94.4811% from the full reactor current. The unified result's station-loss columns also remain zero placeholders despite nonzero reactor losses.

Fresh MATLAB MCP PF checks passed. Historical CPF points remain labeled as the older fixed-G2 dispatch; the new non-slack dispatch is a separate scenario. No new physical stability margin is claimed and no production code or case parameters were changed.

See [station_results.csv](station_results.csv), [evidence.json](evidence.json), [MATLAB evidence](evidence.mat), and [verification](verification/verification.json).
