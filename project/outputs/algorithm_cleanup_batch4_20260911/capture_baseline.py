from pathlib import Path
import hashlib, json, subprocess
root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
paths = list((root/'matpower/lib').rglob('*.m')) + list((root/'matpower/data').glob('*.m')) + list((root/'tests').rglob('*')) + list((root/'docs').glob('*.md'))
paths += list((root/'outputs/algorithm_cleanup_batch3_20260910').rglob('*'))
manifest = {p.relative_to(root).as_posix():sha(p) for p in paths if p.is_file()}
assert not (out/'baseline_hashes.json').exists()
(out/'baseline_hashes.json').write_text(json.dumps(manifest,indent=2))
baseline=json.loads((root/'outputs/algorithm_cleanup_batch3_20260910/revalidation_20260911_01/source_manifest.json').read_text())
check={p:sha(root/p)==v['after_sha256'] for p,v in baseline.items()}
(out/'batch3_baseline_verified.json').write_text(json.dumps(check,indent=2))
assert all(check.values()),check
(out/'preexisting.patch').write_bytes(subprocess.check_output(['git','-C',str(root/'matpower'),'diff','--','lib']))
