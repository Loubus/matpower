# Critical-bus P–V plots

Bus 5 has the lowest voltage among the original physical buses at the endpoint of all eight saved NOSE-mode runs. The horizontal axis is actual bus-5 active demand, P5 = 60 + 240 lambda MW; reactive demand follows the original study direction. All four variants and both predictor steps are included.

- [Full accepted traces](pv_bus5_overview.png) — [vector PDF](pv_bus5_overview.pdf).
- [Turning-region close-up](pv_bus5_near_nose.png) — [vector PDF](pv_bus5_near_nose.pdf).
- [One panel per variant, comparing steps](pv_bus5_by_case.png) — [vector PDF](pv_bus5_by_case.pdf).

Stars mark detected local noses; diamonds mark the first accepted point after generator 2 changes to PQ; crosses mark other terminations. Lines connect accepted samples in their recorded order. Connecting segments across control-mode transitions are not localized power-flow solutions and must not be interpreted as precisely resolved folds. The coupled-current variant's inherited branch-direction caveat remains relevant.

The augmented and combined runs continue into the descending branch because NOSE detection skips their G2 mode-change step; their later termination is at converter capability correction. These figures intentionally show the complete accepted traces, not an artificial truncation at their largest sample.

Source: the eight saved MAT files in the parent directory, produced by explicit NOSE runs. MATLAB MCP generated the figures from those results. No solver rerun, production modification or case change was required. PNG figures were visually inspected; vector PDFs are exports of the same figures. The CSV records endpoint values and the minimum-voltage physical-bus check.
