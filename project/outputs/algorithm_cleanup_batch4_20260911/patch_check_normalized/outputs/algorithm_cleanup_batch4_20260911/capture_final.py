from pathlib import Path
import hashlib, json, difflib
root=Path(__file__).resolve().parents[2]
out=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,obj):(out/name).write_text(json.dumps(obj,indent=2))
baseline=json.loads((out/'baseline_hashes.json').read_text())
changed=[p for p,h in baseline.items() if not (root/p).exists() or sha(root/p)!=h]
allowed=['matpower/lib/+mp/psse_swshunt_control.m','matpower/lib/+mp/psse_unified_control_update.m','tests/README.md']
write('preservation.json',{'changed_existing_files':changed,'unexpected_changes':[p for p in changed if p not in allowed],
    'preserved_file_count':len(baseline)-len(changed),'baseline_files':len(baseline)})
assert all(p in allowed for p in changed),changed
files=allowed+['matpower/lib/+mp/psse_swshunt_group_action.m','matpower/lib/+mp/psse_swshunt_discrete_next.m',
    'tests/t_swshunt_acceptance_batch4.m','tests/t_swshunt_beerten_batch4.m','docs/SWSHUNT_DECISION_CONTRACT.md']
files += ['outputs/algorithm_cleanup_batch4_20260911/'+name for name in
    ['REPORT.md','run_batch4_suite.m','verify_numerical_evidence.m','verify_code_analysis.m','verify_patch.py','capture_final.py'] if (out/name).exists()]
manifest={}
patch=[]; repair=[]; extraction=[]
def diff(before,after,p):return list(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/'+p,tofile='b/'+p))
for p in files:
    final=root/p
    if p.startswith('matpower/') and final.name in ['psse_swshunt_control.m','psse_unified_control_update.m']:
        before=out/'before'/final.name; pre=out/'preextraction'/final.name
        text=before.read_text()
        repair+=diff(text,pre.read_text(),p)
        extraction+=diff(pre.read_text(),final.read_text(),p)
    elif p=='tests/README.md':
        before=out/'before/tests_README.md'; text=before.read_text()
    else:
        before=None; text=''
        if p.startswith('matpower/'):extraction+=diff('',final.read_text(),p)
    manifest[p]={'before_sha256':sha(before) if before else None,'after_sha256':sha(final),
        'before_lines':len(text.splitlines()),'after_lines':len(final.read_text().splitlines())}
    patch+=diff(text,final.read_text(),p)
write('source_manifest.json',manifest)
(out/'batch4.patch').write_bytes(''.join(patch).encode('utf-8'))
(out/'lock_eligibility_repair.patch').write_bytes(''.join(repair).encode('utf-8'))
(out/'bounded_consolidation.patch').write_bytes(''.join(extraction).encode('utf-8'))
# Verify all saved production code outside the exact removed selectors and
# changed call sites is byte-equivalent after normalizing line endings.
ac0=(out/'preextraction/psse_swshunt_control.m').read_text()
ac1=(root/'matpower/lib/+mp/psse_swshunt_control.m').read_text()
un0=(out/'preextraction/psse_unified_control_update.m').read_text()
un1=(root/'matpower/lib/+mp/psse_unified_control_update.m').read_text()
def section(s,start,end=None):return s[s.index(start):s.index(end,s.index(start)) if end else None]
structural={
 'ac_continuous_sensitivity_screening_cycle_signature_unchanged':section(ac0,'function b = continuous_next_b')==section(ac1,'function b = continuous_next_b'),
 'ac_classification_unchanged':section(ac0,'function state = classify_state','function [new_b, new_direction]')==section(ac1,'function state = classify_state','function [new_b, new_direction]'),
 'unified_tap_and_existing_repairs_unchanged':un0[:un0.index('function [mpc, state] = direct_swshunt_control')]==un1[:un1.index('function [mpc, state] = direct_swshunt_control')],
 'unified_continuous_reports_lock_application_unchanged':section(un0,'function b = continuous_next_b')==section(un1,'function b = continuous_next_b'),
 'unified_shunt_classification_unchanged':section(un0,'function state = classify_swshunt_state','function new_b = next_swshunt_b_state')==section(un1,'function state = classify_swshunt_state','function new_b = next_swshunt_b_state'),
 'unified_shunt_blocked_reporting_unchanged':section(un0,'function state = mark_swshunt_blocked_controls','function b = discrete_next_b')==section(un1,'function state = mark_swshunt_blocked_controls','function b = continuous_next_b')}
write('structural_preservation.json',structural); assert all(structural.values())
summary=[]
for dirname in ['acceptance_final','beerten_final','controls_final','vsc_final','handoff_final','physical_final']:
    p=out/dirname/'counts.json'
    if p.exists():
        counts=json.loads(p.read_text()); counts['directory']=dirname
        counts['warning_lines']=[s for s in (p.parent/'run.log').read_text().splitlines() if s.startswith('Warning:')]
        summary.append(counts)
write('verification_summary.json',summary)
