# Beerten validation family

`variants/` contains all 16 existing `case5_vsc_mtdc_beerten*.m` functions, preserved exactly from the local project. These include base/target pairs and project control, capability and redispatch variants. They retain their original names so existing callers work.

`upstream/` holds the MatACDC archive and extracted reference cases. It is not on the MATLAB path. The original software examples and the local paper/control variants need parameter alignment before an independent numerical comparison.

The active runner lives in `studies/beerten/` at the project root. New outputs default to `outputs/beerten/`. Historical outputs remain in the archived audit collection.
