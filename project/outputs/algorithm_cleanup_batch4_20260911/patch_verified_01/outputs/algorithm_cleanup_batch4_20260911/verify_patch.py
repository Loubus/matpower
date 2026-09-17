from pathlib import Path
import json, subprocess
out=Path(__file__).resolve().parent
root=out.parents[1]
sequence=1
scratch=out/f'patch_verified_{sequence:02d}'
while scratch.exists():
    sequence+=1
    scratch=out/f'patch_verified_{sequence:02d}'
scratch.mkdir()
manifest=json.loads((out/'source_manifest.json').read_text(encoding='utf-8'))
for name,data in manifest.items():
    if data['before_sha256']:
        source=out/'before'/('tests_README.md' if name=='tests/README.md' else Path(name).name)
        dest=scratch/name;dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(source.read_text(encoding='utf-8').encode('utf-8'))
result=subprocess.run(['git','apply','--whitespace=nowarn',str(out/'batch4.patch')],cwd=scratch,capture_output=True,text=True)
checks={name:(scratch/name).exists() and (scratch/name).read_text(encoding='utf-8')==(root/name).read_text(encoding='utf-8') for name in manifest}
(out/'patch_application_verified.json').write_text(json.dumps({'scratch':str(scratch),'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'files_match_normalized':checks},indent=2))
assert result.returncode==0 and all(checks.values()),(result.stderr,checks)
