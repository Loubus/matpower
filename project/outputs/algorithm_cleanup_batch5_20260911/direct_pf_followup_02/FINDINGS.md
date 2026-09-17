# Direct PF at the rejected CPF loading

These follow-up runs address the user's question about direct PF at the exact
rejected CPF loading, starting from original case voltages and controls rather
than CPF warm starts. No production code or solver tolerances were changed.
Full inputs/options/results are in `results.mat`; flags, balances and capability
audits are in `summary.json`. The earlier follow-up at 0.45/0.8 is separate.

| Loading | Automatic PF success | Bus-5 voltage | Shunt BINIT |
|---|---:|---:|---:|
| Last accepted CPF lambda 0.410557523581632 | 1 | 0.950009965624 pu | 15 MVAr |
| Rejected CPF lambda 0.410704696470272 | 1 | 0.949985565573 pu | 15 MVAr |

At the rejected loading, direct full-equation fixed-state PF also succeeds:
with original controls (B=0, tap=1), bus 5 is 0.935924537409 pu; with B=15 and
tap=1.011111111111111, it is 0.949985564747 pu. The latter differs from the
automatic PF by only 8.26e-10 pu in maximum AC voltage magnitude.
All six direct PF runs meet 1e-8 pu AC/DC/converter balance and their unchanged
post-solve generator/converter capability audits report zero violations.

The automatic PF's success is not proof of satisfying the control band:
0.949985565573 is below 0.94999, the original lower edge including VCTOLV.
Nevertheless its stored shunt report says inside_band=1 and blocked_low=0.
Reapplying the common direct decision to the actual solved full-model voltages
reports changed=0, control_violations=1 and swshunt_blocked_low=1.
`acceptance_discrepancy.mat` preserves this independent reclassification.

Source inspection identifies a PF/CPF path difference: the regular unified PF
falls through to its auxiliary AC PF when the direct report is unsatisfied,
and can return its control report without replacing the full-model electrical
solution. CPF consumes the direct blocked-control report. The auxiliary replay
is retained separately in `auxiliary_replay.mat`: its bus-5 voltage is
0.949998093641 pu (inside the band), versus the actual unified voltage
0.949985565573 pu (outside the band). The approximately 1.25e-5 pu projection
difference explains the contradictory control classifications at this point.

This establishes an additional PF control-acceptance/report inconsistency that
was not repaired in batch 5. It does not invalidate the electrical solution or
turn this control-band crossing into an instability point. Further policy or
implementation work must not treat the regular PF success flag as evidence
that the full-model voltage band is met. No further repair is claimed here.
