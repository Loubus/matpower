from pathlib import Path
import json,shutil
root=Path.cwd();out=Path(__file__).resolve().parent
paths=['tests/t_ultc_beerten_batch3.m','tests/t_swshunt_beerten_batch4.m']
manifest=json.loads((out/'existing_files.json').read_text())
for rel in paths:
    p=out/'before'/rel;assert not p.exists();p.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(root/rel,p);manifest.append(rel)
(out/'existing_files.json').write_text(json.dumps(manifest))
