from pathlib import Path
import hashlib
import json
import shutil

out = Path(__file__).resolve().parent
root = out.parent.parent
paths = ['matpower/lib/runpf_vsc_mtdc_unified.m',
         'matpower/lib/+mp/psse_branch_expand.m',
         'matpower/lib/+mp/psse_swdev_expand.m',
         'matpower/lib/+mp/psse_branch_collapse.m',
         'matpower/lib/+mp/psse_swdev_collapse.m',
         'matpower/lib/runcpf_vsc_mtdc.m',
         'matpower/lib/t/t_vsc_mtdc.m',
         'matpower/lib/t/t_mpxt_psse.m',
         'tests/t_control_acceptance_batch1.m', 'README.md',
         'docs/CONTROL_ACCEPTANCE.md', 'tests/README.md']
dest = out / 'before'
dest.mkdir(exist_ok=False)
record = {}
for rel in paths:
    src = root / rel
    target = dest / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, target)
    record[rel] = hashlib.sha256(src.read_bytes()).hexdigest()
(out / 'before_hashes.json').write_text(json.dumps(record, indent=2)+'\n')
