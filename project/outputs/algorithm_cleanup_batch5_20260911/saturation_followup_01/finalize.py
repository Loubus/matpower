from pathlib import Path
import difflib,hashlib,json,re,subprocess,tempfile
root=Path.cwd();out=Path(__file__).resolve().parent
existing=json.loads((out/'existing_files.json').read_text(encoding="utf-8"))
new=['matpower/lib/+mp/psse_unified_control_acceptance.m','tests/t_control_saturation_batch5.m','docs/CONTROL_SATURATION_CONTRACT.md']
files=existing+new
patch=[]
for rel in files:
    p=out/'before'/rel
    old=p.read_text(encoding="utf-8").splitlines(True) if p.exists() else []
    patch.extend(difflib.unified_diff(old,(root/rel).read_text(encoding="utf-8").splitlines(True),fromfile='a/'+rel if p.exists() else '/dev/null',tofile='b/'+rel))
(out/'saturation.patch').write_text(''.join(patch),encoding='utf-8',newline='\n')
manifest=json.loads((out/'baseline_hashes.json').read_text(encoding="utf-8"))
changed=[p for p,h in manifest.items() if not (root/p).is_file() or hashlib.sha256((root/p).read_bytes()).hexdigest()!=h]
preservation={'baseline_files':len(manifest),'changed':changed,'unexpected':[p for p in changed if p not in existing]}
(out/'preservation.json').write_text(json.dumps(preservation,indent=2));assert not preservation['unexpected']
checks=Path(tempfile.mkdtemp(prefix='patch_check_',dir=out))
for rel in existing:
    p=checks/rel;p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text((out/'before'/rel).read_text(encoding="utf-8"),encoding='utf-8',newline='\n')
r=subprocess.run(['git','apply',str(out/'saturation.patch')],cwd=checks,capture_output=True,text=True)
matches={p:(checks/p).is_file() and (checks/p).read_text(encoding="utf-8")==(root/p).read_text(encoding="utf-8") for p in files}
validation={'directory':checks.name,'exit_code':r.returncode,'output':r.stdout+r.stderr,'matches':matches}
(out/'patch_validation.json').write_text(json.dumps(validation,indent=2));assert r.returncode==0 and all(matches.values())
(out/'source_manifest.json').write_text(json.dumps({p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in files},indent=2))
structural={}
targets={'matpower/lib/runcpf_vsc_mtdc.m':['unified_cpf_corrector','unified_cpf_tangent','unified_eval_at_lambda','unified_residual_norm','solve_unified_pf_at_lambda','locate_unified_nose','vsc_cpf_current_mpc','apply_psse_active_set_update','settle_unified_vsc_capability_controls','settle_unified_gen_capability_controls'],
         'matpower/lib/runpf_vsc_mtdc_unified.m':['solve_unified_pf','unified_mismatch','unified_build_results','unified_setup','apply_psse_active_set_update']}
def body(text,name):
    chunks=re.split(r'(?m)^[ \t]*function\b',text)[1:]
    exact=[]
    for x in chunks:
        header=''
        for line in x.splitlines():
            header+=line
            if not line.rstrip().endswith('...'):break
        if re.search(r'\b'+name+r'\s*\(',header):exact.append(x)
    assert len(exact)==1,(name,len(exact))
    return exact[0]
for rel,names in targets.items():
    old=(out/'before'/rel).read_text(encoding="utf-8");newtext=(root/rel).read_text(encoding="utf-8")
    for name in names:structural[rel+':'+name]=body(old,name)==body(newtext,name)
(out/'structural_preservation.json').write_text(json.dumps(structural,indent=2));assert all(structural.values())
selected={}
for p in sorted(out.glob('verification_*/*/counts.json')):
    item=json.loads(p.read_text(encoding="utf-8"));item['path']=p.relative_to(out).as_posix()
    item['warnings']=[l for l in (p.parent/'run.log').read_text(encoding="utf-8").splitlines() if re.search(r'(^|\s)Warning:',l)]
    selected[item['name']]=item
summary={'suites':list(selected.values()),'passed':sum(x['passed'] for x in selected.values()),'failed':sum(x['failed'] for x in selected.values()),'skipped':sum(x['skipped'] for x in selected.values()),'exceptions':[x for x in selected.values() if x['exception']]}
(out/'verification_summary.json').write_text(json.dumps(summary,indent=2))
scenario=json.loads((out/'summary.json').read_text(encoding='utf-8'))
def differences(a,b,path=''):
    if isinstance(a,dict) and isinstance(b,dict):
        return [d for k in sorted(set(a)|set(b)) for d in differences(a.get(k),b.get(k),path+'.'+k if path else k)]
    return [] if a==b else [{'path':path,'before':a,'after':b}]
changes=differences(scenario['original_options'],scenario['options'])
(out/'option_diff.json').write_text(json.dumps(changes,indent=2))
assert changes==[{'path':'vsc_mtdc.psse_control_limit','before':'stop','after':'saturate'}],changes
print(json.dumps(summary,indent=2))
