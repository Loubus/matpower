from pathlib import Path
import hashlib,json,difflib
out=Path(__file__).resolve().parent;root=out.parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=[];diff=[]
for prev in sorted((out/'before').rglob('*')):
    if not prev.is_file():continue
    rel=prev.relative_to(out/'before');now=root/rel
    a=prev.read_text(encoding='utf-8-sig');b=now.read_text(encoding='utf-8-sig')
    if a==b:continue
    record={'path':rel.as_posix(),'before_sha256':sha(prev),'after_sha256':sha(now)}
    if rel.parts[0]=='cases' or (rel.parts[:2]==('matpower','data')):
        code=lambda s:'\n'.join(x.split('%')[0].strip() for x in s.splitlines() if x.split('%')[0].strip())
        record['executable_case_content_unchanged']=code(a)==code(b)
        assert record['executable_case_content_unchanged']
    files.append(record)
    diff.extend(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='before/'+rel.as_posix(),tofile=rel.as_posix()))
new=['matpower/lib/vsc_station_map.m','matpower/lib/vsc_station_capability.m','tests/t_vsc_pcc_station.m','docs/VSC_PCC_POWER_CONTRACT.md']
for name in new:
    p=root/name;files.append({'path':name,'new':True,'after_sha256':sha(p)})
    diff.extend(difflib.unified_diff([],p.read_text().splitlines(True),fromfile='/dev/null',tofile=name))
old=json.loads((root/'outputs/converter_model_explanation_20260914/source_manifest.json').read_text())
history=[]
for rec in old['files']:
    if rec['path'].startswith('outputs/'):
        p=root/rec['path'];history.append({'path':rec['path'],'unchanged':sha(p)==rec['sha256']})
assert all(x['unchanged'] for x in history)
result={'date':'2026-09-16','files':files,'historical_manifest_files_checked':history,
        'case_numerical_data_changed':False,'scope':'PCC-port migration and full-station capability'}
(out/'change_manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
(out/'changes.diff').write_text(''.join(diff),encoding='utf-8')
print(json.dumps({'changed_files':len(files),'historical_files_verified':len(history),'case_parameters_unchanged':True}))
