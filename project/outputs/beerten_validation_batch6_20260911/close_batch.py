"""Package the verified working-file patch and evidence; no numerical reruns."""
from pathlib import Path
import difflib, hashlib, json, subprocess, zipfile, sys
import importlib.metadata

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def write(name, value):
    (OUT/name).write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')

baseline = read(OUT/'baseline_hashes.json')
changed = [p for p, sha in baseline.items() if not (ROOT/p).exists() or digest(ROOT/p) != sha]
expected = ['matpower/lib/runcpf_vsc_mtdc.m', 'matpower/lib/runpf_vsc_mtdc_unified.m']
assert sorted(changed) == sorted(expected), changed
existing = sorted(p.relative_to(OUT/'before').as_posix() for p in (OUT/'before').rglob('*') if p.is_file())
added = ['tests/t_beerten_reporting_batch6.m', 'tests/t_beerten_capability_batch6.m',
         'studies/beerten/beerten_constant_pq_capability_batch6.m']
patch = []
for p in existing + added:
    prior = (OUT/'before'/p).read_bytes() if p in existing else b''
    final = (ROOT/p).read_bytes()
    patch.extend(difflib.unified_diff(prior.decode('utf-8').splitlines(keepends=True),
                 final.decode('utf-8').splitlines(keepends=True),
                 fromfile='a/'+p if p in existing else '/dev/null', tofile='b/'+p))
(OUT/'batch6.patch').write_bytes(''.join(patch).encode('utf-8'))
scratch = OUT/'patch_application_02'
assert not scratch.exists(), 'Use a fresh scratch directory; preserve earlier application evidence.'
scratch.mkdir()
for p in existing:
    dest = scratch/p
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes((OUT/'before'/p).read_bytes())
commands = []
for flags in [['--check'], []]:
    cmd = ['git', '-c', 'core.autocrlf=false', '-c', 'core.eol=lf', 'apply', *flags, '--whitespace=nowarn', str(OUT/'batch6.patch')]
    proc = subprocess.run(cmd, cwd=scratch, text=True, capture_output=True)
    commands.append({'command':cmd, 'exit_code':proc.returncode, 'stdout':proc.stdout, 'stderr':proc.stderr})
    if proc.returncode:
        write('patch_validation.json', {'commands':commands,'passed':False})
        raise RuntimeError(proc.stderr)
hashes = {p:{'applied_sha256':digest(scratch/p),'working_sha256':digest(ROOT/p),
             'byte_identical':(scratch/p).read_bytes()==(ROOT/p).read_bytes()} for p in existing+added}
assert all(x['byte_identical'] for x in hashes.values())
write('patch_validation.json', {'baseline':'before/ working-file snapshots, not Git HEAD',
      'commands':commands,'files':hashes,'passed':True})

case_manifest = read(ROOT/'cases/source_manifest.json')
beerten_sources = []
for item in case_manifest['files']:
    if item['path'].startswith('beerten/'):
        source = ROOT/'cases'/item['path']
        beerten_sources.append({'path':source.relative_to(ROOT).as_posix(),
                                'entry_sha256':item['sha256'],'current_sha256':digest(source),
                                'unchanged':item['sha256']==digest(source)})
assert all(x['unchanged'] for x in beerten_sources)
archive = ROOT/'cases/beerten/upstream/MatACDC1_0.zip'
members = []
with zipfile.ZipFile(archive) as z:
    for member in z.infolist():
        if member.is_dir(): continue
        p = OUT/'reference'/member.filename
        members.append({'member':member.filename,'sha256':digest(p),
                        'byte_identical':p.read_bytes()==z.read(member)})
assert all(x['byte_identical'] for x in members)
write('preservation.json', {'baseline_files_checked':len(baseline),'baseline_changed':changed,
      'baseline_unchanged':len(baseline)-len(changed),'preexisting_snapshots':existing,
      'new_project_files':added,'collected_beerten_sources':beerten_sources,
      'author_archive_members':members,
      'historical_outputs':'Read as immutable inputs; no historical output was written by batch 6. Current input hashes are in source_manifest.json; entry baseline did not hash all historical outputs.'})

counts = [read(p) for p in sorted((OUT/'regressions_02').glob('*/counts.json'))]
totals = {k:sum(c[k] for c in counts) for k in ['planned','executed','passed','failed','skipped']}
assert len(counts)==9 and totals['passed']==1953 and totals['failed']==0 and totals['skipped']==97
assert all(not c['exception'] for c in counts)
options = read(OUT/'final_04/options_audit.json')
def flat(value, prefix=''):
    answer={}
    for k,v in value.items():
        key=prefix+'.'+k if prefix else k
        if isinstance(v,dict): answer.update(flat(v,key))
        else: answer[key]=v
    return answer
old=flat(options['original_options']);new=flat(options['capability_options'])
diff={k:{'original':old.get(k),'capability':new.get(k)} for k in sorted(old.keys()|new.keys()) if old.get(k)!=new.get(k)}
assert set(diff)=={'cpf.enforce_q_lims','vsc_mtdc.capability_enforce','vsc_mtdc.capability_gen_enforce'},diff
write('options_diff.json', {'differences':diff,'named_scenario_exact':options['input_checks'],
       'step_sensitivity_overrides':[0.1,0.05,0.025]})
write('verification_summary.json', {'study_date':'2026-09-11','closure_date':'2026-09-14',
      'matlab_regressions':counts,'matlab_totals':totals,
      'static_analysis':read(OUT/'code_analysis.json'),
      'independent_checks':read(OUT/'final_04/independent_final/validation_counts.json'),
      'retained_verification_failure':'2010 AC-only bus-5 angle exceeds strict half-digit rounding gate by 0.000050538 degrees.',
      'equipment_acceptance':'All four traces fail full-equipment feasibility; supported constraints passing does not remove slack/other unavailable limits.',
      'diagnostic_trace_equality':read(OUT/'final_04/diagnostic_trace_equality.json'),
      'patch_applies_byte_exact':True,
      'python':{'executable':sys.executable,'version':sys.version,
                'packages':{p:importlib.metadata.version(p) for p in ['numpy','scipy','matplotlib','pypdf']}}})

sources = [ROOT/'AGENTS.md', ROOT/'.codex/MATLAB_MCP.md',
           ROOT/'docs/CONTROL_ACCEPTANCE.md', ROOT/'docs/CONTROL_SATURATION_CONTRACT.md',
           ROOT/'docs/PQBRAK_MODEL_POLICY.md', ROOT/'cases/source_manifest.json',
           ROOT/'outputs/algorithm_cleanup_batch4_20260911/beerten_probe.mat',
           ROOT/'outputs/algorithm_cleanup_batch5_20260911/pqbrak_off_01/nose_03/nose.mat',
           ROOT/'outputs/algorithm_cleanup_batch5_20260911/pqbrak_off_01/REPORT.md',
           ROOT/'outputs/algorithm_cleanup_batch5_20260911/saturation_followup_01/REPORT.md',
           ROOT/'Referencias/Jef Beerten - A Sequential ACDC Power Flow Algorithm for.pdf']
sources += [ROOT/x for x in existing+added]
sources += [ROOT/x['path'] for x in beerten_sources]
sources += list(OUT.glob('*.py'))+list(OUT.glob('*.m'))+[OUT/'inputs.json']
sources += list((OUT/'reference').rglob('*.m'))
sources += list((OUT/'final_04').glob('*.mat'))+list((OUT/'final_04').glob('*.json'))
sources += list((OUT/'final_04/independent_final').glob('*.json'))
sources += [OUT/'batch6.patch',OUT/'REPORT.md',OUT/'reproduce.md']
records=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted(set(sources))]
write('source_manifest.json', {'study_date':'2026-09-11','closure_date':'2026-09-14',
       'hash_algorithm':'SHA-256','files':records})
print(json.dumps({'patch_files':len(hashes),'patch_byte_identical':True,'baseline_scientific_files':len(baseline),
                  'regressions':totals,'source_records':len(records),'options_changed':list(diff)},indent=2))
