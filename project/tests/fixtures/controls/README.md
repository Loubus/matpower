# Small control regression inputs

`legacy_regression/` preserves the 14 RAW inputs currently required by `matpower/lib/t/t_mpxt_psse.m`: nine generator-Q cases, one integrated 40-bus case and four transformer/integrated suite cases. The test lookup searches here first, with the old audit path as a compatibility fallback. Every copied input has a hash in the cleanup migration record.

These are test fixtures, not thesis benchmark studies. Small isolated tests remain necessary for tap direction/grid/bounds, shunt states, capability limits, import mapping and solver behavior. Many such tests also construct cases inline.

The existing suite mixes physical checks with exact PSS/E compatibility expectations. This organization-only batch preserves all assertions, including the compatibility-specific ones. A subsequent algorithm batch should split those expectations deliberately and retain physical acceptance criteria before simplifying policies. Archiving large PSS/E studies does not require discarding their only useful regression inputs.
