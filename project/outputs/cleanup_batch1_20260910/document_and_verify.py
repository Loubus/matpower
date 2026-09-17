"""Record the completed case migration and check preservation against snapshots."""
from pathlib import Path
import hashlib
import json
import difflib
import csv
import os

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

mapping = {
    'upstream/PowerModelsACDC/': 'ieee/upstream/PowerModelsACDC/',
    'upstream/Nordic/': 'nordic/upstream/',
    'upstream/CIGRE_implementation/': 'cigre/upstream/',
    'upstream/MatACDC_cases/': 'beerten/upstream/MatACDC_cases/',
    'upstream/MatACDC1_0.zip': 'beerten/upstream/MatACDC1_0.zip',
}

def relocated(path):
    for old, new in mapping.items():
        if path.startswith(old):
            return new + path[len(old):]
    raise ValueError(f'Unmapped source: {path}')

manifest = read_json(ROOT / 'outputs/thesis_scope_20260910/source_manifest.json')
manifest['path_base'] = 'cases/'
manifest['status'] = ('Upstream inputs collected and hash-verified after relocation; '
                      'not converted or numerically validated. Local case snapshots '
                      'preserve the existing project data.')
for section in ['files', 'literal_matrix_row_counts']:
    for item in manifest[section]:
        item['path'] = relocated(item['path'])
for item in manifest['files']:
    assert digest(ROOT / 'cases' / item['path']) == item['sha256'].lower(), item['path']

migration = read_json(OUT / 'migration.json')
copy_checks = []
manifest['local_case_snapshots'] = []
for item in migration:
    if item['action'] != 'copy':
        continue
    target = ROOT / item['target']
    actual = digest(target)
    assert actual == item['sha256'].lower(), item['target']
    copy_checks.append({'path': item['target'], 'sha256': actual, 'matches': True})
    if item['target'].startswith('cases/') and '/upstream/' not in item['target']:
        manifest['local_case_snapshots'].append({
            'path': item['target'][len('cases/'):],
            'original_project_path': item['source'],
            'sha256': actual,
            'bytes': target.stat().st_size,
            'status': 'Unmodified snapshot of existing local input; source comments retained.',
        })
write_json(ROOT / 'cases/source_manifest.json', manifest)

docs = ROOT / 'docs'
docs.mkdir(exist_ok=True)
for name in ['STUDY_DESIGN.md', 'BENCHMARKS.md']:
    content = (ROOT / 'outputs/thesis_scope_20260910' / name).read_text(encoding='utf-8-sig')
    content = content.replace('(source_manifest.json)', '(../cases/source_manifest.json)')
    content = content.replace('Files in `upstream/`', 'Files in the `cases/*/upstream/` folders')
    content = content.replace('`auditoria_psse_matpower/transpa_reduccion/cpf_psse_runner/`',
                              '`archive/transpa_reduction_v1/studies/cpf_psse_runner/`')
    if name == 'STUDY_DESIGN.md':
        content = content.replace('# Proposed thesis scope:', '# Thesis study design:')
        content = content.replace(
            'This is a design proposal, not an implemented or numerically validated change. Existing solver code and historical outputs were not modified.',
            'The scope is agreed; algorithm changes and corridor scenarios remain to be implemented and validated. The first repository cleanup reorganized files and paths without changing solver equations or historical results.')
    (docs / name).write_text(content, encoding='utf-8')

runner_doc = ROOT / 'studies/beerten/cpf_runner/README.md'
content = runner_doc.read_text(encoding='utf-8-sig')
content = content.replace("addpath('auditoria_psse_matpower/beerten_5bus');\naddpath('auditoria_psse_matpower/beerten_5bus/cpf_runner');", 'iniciar_proyecto;  % from the project root')
content = content.replace('`auditoria_psse_matpower/results/<outdir_name>`', '`outputs/beerten/<outdir_name>`')
content = content.replace('For an AC-only comparison from the same base and target cases:',
    'To remove DC equipment from the same base and target cases (this does not create an equivalent AC corridor):')
runner_doc.write_text(content, encoding='utf-8')

checkpoint = read_json(ROOT / 'outputs/repo_cleanup_preflight_20260910/checkpoint_manifest.json')
expected_changes = {
    'iniciar_proyecto.m',
    'matpower/lib/t/t_mpxt_psse.m',
    'auditoria_psse_matpower/beerten_5bus/cpf_runner/beerten_cpf_run.m',
    'auditoria_psse_matpower/beerten_5bus/cpf_runner/README.md',
    # Scope was updated after the checkpoint to reflect the user's explicit
    # instruction to validate algorithms before returning to TRANSPA.
    'outputs/thesis_scope_20260910/STUDY_DESIGN.md',
}
unchanged, changed, missing = [], [], []
for item in checkpoint:
    path = ROOT / item['path']
    if not path.is_file():
        missing.append(item['path'])
    elif digest(path) == item['sha256'].lower():
        unchanged.append(item['path'])
    else:
        changed.append(item['path'])

diffs = []
for name, current in [
    ('iniciar_proyecto.m', 'iniciar_proyecto.m'),
    ('t_mpxt_psse.m', 'matpower/lib/t/t_mpxt_psse.m'),
    ('beerten_cpf_run.m', 'studies/beerten/cpf_runner/beerten_cpf_run.m'),
]:
    before = (OUT / 'before' / name).read_text(encoding='utf-8-sig').splitlines(True)
    after = (ROOT / current).read_text(encoding='utf-8-sig').splitlines(True)
    diffs.extend(difflib.unified_diff(before, after, fromfile='before/' + name, tofile=current))
(OUT / 'path_changes.diff').write_text(''.join(diffs), encoding='utf-8')
report = {
    'upstream_files_hash_verified': len(manifest['files']),
    'local_case_snapshots': len(manifest['local_case_snapshots']),
    'migration_copies_hash_verified': len(copy_checks),
    'copy_checks': copy_checks,
    'checkpoint_files': len(checkpoint),
    'checkpoint_unchanged': len(unchanged),
    'checkpoint_changed': changed,
    'checkpoint_missing': missing,
    'unexpected_checkpoint_changes': sorted(set(changed) - expected_changes),
    'note': 'Checkpoint covers selected source files and inputs, not a full hash inventory of large historical results.',
}
write_json(OUT / 'file_verification.json', report)
print(json.dumps({k: v for k, v in report.items() if k != 'copy_checks'}, indent=2))
assert not missing, missing
assert not report['unexpected_checkpoint_changes'], report['unexpected_checkpoint_changes']

# Verify the previously inventoried result trees through their retained paths.
# This checks file count/total bytes, not cryptographic identity of all results.
with (ROOT / 'outputs/repo_cleanup_preflight_20260910/results_disposition.csv').open(encoding='utf-8-sig') as stream:
    result_rows = list(csv.DictReader(stream))
result_checks = []
for item in result_rows:
    folder = ROOT / item['current_path']
    if os.name == 'nt':
        folder = Path('\\\\?\\' + str(folder))
    files = [Path(directory) / name for directory, _, names in os.walk(folder) for name in names]
    size = sum(file.stat().st_size for file in files)
    # The earlier inventory used ordinary paths and is_file(), which can omit
    # Windows paths longer than MAX_PATH. Reproduce that view separately.
    ordinary_files = [file for file in files if Path(str(file).removeprefix('\\\\?\\')).is_file()]
    ordinary_size = sum(file.stat().st_size for file in ordinary_files)
    result_checks.append({
        'path': item['current_path'], 'files': len(files), 'bytes': size,
        'matches': len(files) == int(item['files']) and size == int(item['bytes']),
        'baseline_files': int(item['files']), 'baseline_bytes': int(item['bytes']),
        'ordinary_path_files': len(ordinary_files), 'ordinary_path_bytes': ordinary_size,
        'ordinary_path_matches_baseline': len(ordinary_files) == int(item['files']) and ordinary_size == int(item['bytes']),
        'long_path_files': [str(file.relative_to(folder)) for file in files if file not in ordinary_files],
    })
write_json(OUT / 'result_tree_verification.json', result_checks)
result_mismatches = [item for item in result_checks if not item['matches']]
print(json.dumps({'result_directories': len(result_checks),
                  'result_files': sum(item['files'] for item in result_checks),
                  'result_bytes': sum(item['bytes'] for item in result_checks),
                  'directories_with_long_paths_omitted_by_baseline': len(result_mismatches),
                  'all_ordinary_path_counts_and_bytes_match_baseline': all(item['ordinary_path_matches_baseline'] for item in result_checks),
                  'additional_long_path_files': sum(len(item['long_path_files']) for item in result_checks)}, indent=2))
assert all(item['matches'] or item['ordinary_path_matches_baseline'] for item in result_checks), result_mismatches
