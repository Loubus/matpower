from pathlib import Path
import hashlib,json,shutil,subprocess
root=Path.cwd()
out=root/'outputs/algorithm_cleanup_batch5_20260911/saturation_followup_01'
files=['matpower/lib/mpoption.m','matpower/lib/runpf_vsc_mtdc_unified.m','matpower/lib/runcpf_vsc_mtdc.m','matpower/lib/t/t_vsc_mtdc.m','docs/CONTROL_ACCEPTANCE.md','docs/CPF_TERMINATION_CONTRACT.md','tests/README.md']
for rel in files:
    p=out/'before'/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/rel,p)
manifest={}
for folder in ['matpower/lib','matpower/data','tests','docs','outputs/algorithm_cleanup_batch4_20260911']:
    for p in (root/folder).rglob('*'):
        if p.is_file():manifest[p.relative_to(root).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in (root/'outputs/algorithm_cleanup_batch5_20260911').rglob('*'):
    if p.is_file() and out not in p.parents:manifest[p.relative_to(root).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
(out/'baseline_hashes.json').write_text(json.dumps(manifest,indent=2))
(out/'existing_files.json').write_text(json.dumps(files))
for args,name in [(['status','--short'],'status_before.txt'),(['diff','--binary'],'preexisting.patch')]:
    r=subprocess.run(['git','-C',str(root/'matpower'),*args],capture_output=True)
    (out/name).write_bytes(r.stdout)
shutil.copy2(root/'outputs/algorithm_cleanup_batch5_20260911/run_batch5_suite.m',out/'run_batch5_suite.m')
