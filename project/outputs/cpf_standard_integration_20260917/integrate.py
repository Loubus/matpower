from pathlib import Path
import re, shutil, hashlib, json, difflib
out=Path(__file__).resolve().parent; root=out.parent.parent
src=root/'outputs/cpf_solution_experiments_20260917/coupled_limit/combined_all_controls'
manifest={}
for name in ['runcpf_vsc_mtdc','runpf_vsc_mtdc_unified']:
    p=root/'matpower/lib'/(name+'.m'); dest=out/'before'/p.relative_to(root)
    assert not dest.exists(), 'Never overwrite the before snapshot'
    dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
    manifest[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
(out/'before_hashes.json').write_text(json.dumps(manifest,indent=2))
for source,target in [('exd_pf','runpf_vsc_mtdc_unified'),('exd_cpf','runcpf_vsc_mtdc')]:
    s=(src/(source+'.m')).read_text()
    for a,b in [('exd_pf','runpf_vsc_mtdc_unified'),('exd_cpf','runcpf_vsc_mtdc'),('exd_current_ilim','vsc_current_limit')]:
        s=s.replace(a,b)
    # Experimental global journals and the hard-coded branch-9 diagnostic
    # are deliberately excluded from the production implementation.
    s=re.sub(r'^[ \t]*exd_log\(.*?;\n','',s,flags=re.M|re.S)
    s=re.sub(r'        rr=struct\(.*?exd_transition_journal\(.*?;\n','',s,flags=re.S)
    s=s.replace('b17_','transition_').replace(' (experimental)','')
    s=s.replace('% AB2: carry','% Carry').replace('% Experiment A: physical','% The physical')
    s=s.replace('% No release heuristic in this bounded first prototype.','% The current constraint remains latched for this continuation path.')
    s=s.replace("'vsc_capability_fixed_lambda_recorrection'","'vsc_capability_transition_recorrection'")
    # PCC active power alone is not a converter-current feasibility test.
    s=s.replace("if r.vsc(ja,c.VAC_INTERNAL)>ap.Vmax+1e-8 || ...\n                            abs(r.vsc(ja,c.PAC))>mpcb.vsc_current_limit(ja)*mpcb.baseMVA+1e-6", "if r.vsc(ja,c.VAC_INTERNAL)>ap.Vmax+1e-8 || ...\n                            r.vsc(ja,c.VAC_INTERNAL)<ap.Vmin-1e-8")
    p=root/'matpower/lib'/(target+'.m'); p.write_text(s)
print('Integrated coupled-current rows and augmented/tangent-transport changes; originals saved.')
