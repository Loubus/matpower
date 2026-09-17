from pathlib import Path
import difflib,hashlib,json,re,subprocess
root=Path(__file__).resolve().parents[2]
out=Path(__file__).resolve().parent
rels=['matpower/lib/runcpf_vsc_mtdc.m','tests/README.md','tests/t_beerten_termination_batch5.m','docs/CPF_TERMINATION_CONTRACT.md']
patch=[]
for rel in rels:
 before=out/'before'/rel
 a=before.read_text(encoding='utf-8').splitlines(keepends=True) if before.exists() else []
 b=(root/rel).read_text(encoding='utf-8').splitlines(keepends=True)
 patch.extend(difflib.unified_diff(a,b,fromfile='a/'+rel if before.exists() else '/dev/null',tofile='b/'+rel))
(out/'batch5.patch').write_text(''.join(patch),encoding='utf-8',newline='\n')
dest=out/'patch_check_final';dest.mkdir()
for rel in rels:
 before=out/'before'/rel
 if before.exists():
  p=dest/rel;p.parent.mkdir(parents=True,exist_ok=True)
  p.write_text(before.read_text(encoding='utf-8'),encoding='utf-8',newline='\n')
result=subprocess.run(['git','apply',str(out/'batch5.patch')],cwd=dest,capture_output=True,text=True)
matches={rel:(dest/rel).is_file() and (dest/rel).read_text(encoding='utf-8')==(root/rel).read_text(encoding='utf-8') for rel in rels}
verification={'exit_code':result.returncode,'output':result.stdout+result.stderr,'files':matches,'all_match':all(matches.values()),'comparison':'UTF-8 and newline normalization in scratch only'}
(out/'patch_application_final.json').write_text(json.dumps(verification,indent=2))
assert verification['all_match'] and result.returncode==0
manifest=json.loads((out/'baseline_hashes.json').read_text())
changes=[Path(p).as_posix() for p,h in manifest.items() if not (root/p).is_file() or hashlib.sha256((root/p).read_bytes()).hexdigest()!=h]
preserve={'baseline_files':len(manifest),'unchanged':len(manifest)-len(changes),'changed':changes,'allowed_existing_changes':rels[:2],'unexpected_changes':[p for p in changes if p not in rels[:2]]}
(out/'preservation.json').write_text(json.dumps(preserve,indent=2))
assert not preserve['unexpected_changes'], preserve
(out/'source_manifest.json').write_text(json.dumps({p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in rels},indent=2))
counts=[]
for p in [out/'focused_final/counts.json',*[p for p in sorted((out/'verification_01').glob('*/counts.json')) if p.parent.name!='t_vsc_mtdc'],out/'verification_02/t_vsc_mtdc/counts.json']:
 a=json.loads(p.read_text());a['path']=str(p.relative_to(out));
 log=p.parent/'run.log';a['warning_lines']=[x for x in log.read_text(encoding='utf-8').splitlines() if re.search(r'(^|\s)Warning:',x)]
 counts.append(a)
summary={'suites':counts,'passed':sum(a['passed'] for a in counts),'failed':sum(a['failed'] for a in counts),'skipped':sum(a['skipped'] for a in counts),'exceptions':[a for a in counts if a['exception']]}
(out/'verification_summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps({'passed':summary['passed'],'failed':summary['failed'],'skipped':summary['skipped'],'exceptions':len(summary['exceptions']),'preservation':preserve,'patch_matches':verification['all_match']},indent=2))
