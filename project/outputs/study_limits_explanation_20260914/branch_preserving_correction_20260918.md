# Correction to voltage-control restoration results

The previous restoration implementation could jump to a different equilibrium and force a negative loading tangent. Its apparent FULL completion is superseded by [the corrected implementation and measured reruns](../cpf_branch_preserving_release_20260918/REPORT.md).

The corrected trace remains continuous through the lower branch, with no restoration event in this scenario. It reaches a first maximum of 463.96055 MW and subsequently stops at an existing VSC capability restriction, at a last accepted demand of 309.73167 MW. The requested FULL endpoint is **not reached**. These are results for the current dispatch, not historical batch-6 margins.

All seven AC bus, six station-node and three DC voltage curves are available in [the new plot folder](../cpf_branch_preserving_release_20260918/all_pv_curves/README.md). Historical artifacts remain preserved.
