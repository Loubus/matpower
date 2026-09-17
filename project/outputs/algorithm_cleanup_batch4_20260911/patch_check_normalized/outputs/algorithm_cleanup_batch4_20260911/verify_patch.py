from pathlib import Path
import json, subprocess
out=Path(__file__).resolve().parent
root=out.parents[1]
scratch=out/'patch_check_normalized'
assert not scratch.exists(),'Use a fresh scratch destination'
scratch.mkdir()
manifest=json.loads((out/'source_manifest.json').read_text())
for name,data in manifest.items():
    if data['before_sha256']:
        source=out/'before'/('tests_README.md' if name=='tests/README.md' else Path(name).name)
        dest=scratch/name;dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(source.read_text().encode('utf-8'))
result=subprocess.run(['git','apply','--whitespace=nowarn',str(out/'batch4.patch')],cwd=scratch,capture_output=True,text=True)
checks={name:(scratch/name).exists() and (scratch/name).read_text()==(root/name).read_text() for name in manifest}
(out/'patch_application_verified.json').write_text(json.dumps({'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'files_match_normalized':checks},indent=2))
assert result.returncode==0 and all(checks.values()),(result.stderr,checks)
