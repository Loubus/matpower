"""Update the repository's deliberate project snapshot for this scoped commit."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
snapshot = root / 'matpower/project'
manifest_path = snapshot / 'SNAPSHOT_MANIFEST.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
paths = [
    'studies/beerten/beerten_constant_pq_nonslack_dispatch.m',
    'studies/beerten/cpf_runner/beerten_cpf_default_opts.m',
    'studies/beerten/cpf_runner/beerten_cpf_preset.m',
    'studies/beerten/cpf_runner/README.md',
    'docs/CPF_LIMIT_CONTINUATION.md',
    'docs/CPF_STUDY_SCOPE_20260918.md',
    'tests/README.md',
    'tests/t_cpf_event_release.m',
    'tests/t_cpf_local_release.m',
    'outputs/study_limits_explanation_20260914/branch_preserving_correction_20260918.md',
]
for folder in ['cpf_branch_preserving_release_20260918', 'cpf_endpoint_diagnosis_20260918', 'cpf_nose_closure_20260918']:
    paths.extend(p.relative_to(root).as_posix() for p in (root/'outputs'/folder).rglob('*') if p.is_file())
entries = {e['source_path']: e for e in manifest['files']}
copied=[]
for rel in sorted(set(paths)):
    source=root/rel; dest=snapshot/rel
    assert snapshot.resolve() in dest.resolve().parents
    assert not dest.is_symlink()
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source,dest)
    raw=source.read_bytes()
    assert raw==dest.read_bytes()
    assert len(raw)<100*1024*1024
    entries[rel]={'source_path':rel,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
    copied.append(rel)
manifest['snapshot_date']='2026-09-18'
manifest['description']='Byte-verified project snapshot; updated capability contacts, local release diagnostics and NOSE study closure. Originals remain in the parent workspace.'
previous=json.loads(subprocess.check_output(['git','-C',str(root/'matpower'),'show',
    'HEAD:project/SNAPSHOT_MANIFEST.json']).decode('utf-8-sig'))
order=[e['source_path'] for e in previous['files']]
manifest['files']=[entries[p] for p in order]+[entries[p] for p in sorted(set(entries)-set(order))]
manifest_path.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(f'Copied and byte-verified {len(copied)} scoped project files; historical entries preserved.')
