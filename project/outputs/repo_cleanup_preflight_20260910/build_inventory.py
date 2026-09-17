"""Read project files and write a cleanup inventory/checkpoint in this folder only."""
from pathlib import Path
from collections import defaultdict
import csv
import hashlib
import json
import subprocess
import zipfile

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
assert not (OUT / 'checkpoint.zip').exists(), 'Refusing to overwrite a checkpoint'

def command(args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, capture_output=True, check=False)

def write(name, data):
    (OUT / name).write_bytes(data)

inventory = command(['rg', '--files', '--hidden', '--no-ignore',
                     '-g', '!.git/**', '-g', '!**/.git/**', '-g', '!.venv/**',
                     '-g', '!outputs/repo_cleanup_preflight_20260910/**'])
if inventory.returncode not in (0, 1):
    raise RuntimeError(inventory.stderr.decode(errors='replace'))
files = [ROOT / x for x in inventory.stdout.decode('utf-8').splitlines()]
groups = defaultdict(lambda: [0, 0])
for file in files:
    rel = file.relative_to(ROOT)
    group = '/'.join(rel.parts[:2]) if len(rel.parts) > 2 else rel.parts[0]
    if file.is_file():
        groups[group][0] += 1
        groups[group][1] += file.stat().st_size
with (OUT / 'directory_inventory.csv').open('w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(['path_group', 'files', 'bytes'])
    writer.writerows((key, *values) for key, values in sorted(groups.items()))

snapshot = set()
git_summary = {}
for repo in ['matpower', 'matpower-extras']:
    path = ROOT / repo
    probe = command(['git', 'rev-parse', 'HEAD'], path)
    if probe.returncode:
        raise RuntimeError(probe.stderr.decode(errors='replace'))
    status = command(['git', 'status', '--porcelain=v1', '-z', '--untracked-files=all'], path)
    write(repo + '_status_before.bin', status.stdout)
    write(repo + '_head.txt', probe.stdout)
    for kind, args in [('working', ['diff', '--binary']),
                       ('staged', ['diff', '--cached', '--binary']),
                       ('net_from_head', ['diff', 'HEAD', '--binary'])]:
        result = command(['git', *args], path)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        write(repo + '_' + kind + '.patch', result.stdout)
    diff = command(['git', 'diff', '--name-only', '-z', 'HEAD'], path)
    untracked = command(['git', 'ls-files', '--others', '--exclude-standard', '-z'], path)
    changed = [x for x in (diff.stdout + untracked.stdout).decode('utf-8').split('\0') if x]
    for name in changed:
        file = path / name
        if file.is_file():
            snapshot.add(file)
    git_summary[repo] = {'head': probe.stdout.decode().strip(),
                         'changed_or_untracked_paths':len(changed),
                         'changed_lib_or_data':[x for x in changed if x.startswith(('lib/', 'data/'))]}

root_git = command(['git', 'rev-parse', '--show-toplevel'])
write('root_git_probe.txt', root_git.stdout + root_git.stderr)

# Preserve project-owned scripts/docs, excluding historical outputs, vendor trees,
# environment/session folders and all configuration that might contain secrets.
for file in files:
    rel = file.relative_to(ROOT)
    if len(rel.parts) == 1 and file.suffix.lower() in {'.m', '.md'}:
        snapshot.add(file)
    elif rel.parts[0] == 'auditoria_psse_matpower' and 'results' not in rel.parts:
        if file.suffix.lower() in {'.m', '.py', '.ps1', '.md', '.txt', '.raw'}:
            snapshot.add(file)
    elif rel.parts[0] == 'PSSE' and len(rel.parts) == 2:
        if file.suffix.lower() in {'.ps1', '.py', '.md'} or file.name == 'V26p_Trs_2532.raw':
            snapshot.add(file)

live = ROOT / 'auditoria_psse_matpower/results/transpa_reduccion_v1'
for name in ['case_transpa_reduced_v1_explicit.m', 'case_transpa_reduced_v1.m',
             'case_transpa_reduced_v1_psse.mat', 'transpa_reduction_v1.mat']:
    file = live / name
    assert file.is_file(), file
    snapshot.add(file)
for file in (ROOT / 'outputs/thesis_scope_20260910').glob('*.md'):
    snapshot.add(file)

manifest = []
with zipfile.ZipFile(OUT / 'checkpoint.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(snapshot):
        rel = file.relative_to(ROOT).as_posix()
        data = file.read_bytes()
        archive.writestr(rel, data)
        manifest.append({'path':rel, 'bytes':len(data),
                         'sha256':hashlib.sha256(data).hexdigest()})
with zipfile.ZipFile(OUT / 'checkpoint.zip') as archive:
    for item in manifest:
        assert hashlib.sha256(archive.read(item['path'])).hexdigest() == item['sha256']

patterns = 'transpa_reduccion_v1|case_transpa_reduced_v1_psse|transpa_reduction_v1\\.mat'
refs = command(['rg', '-n', patterns, 'iniciar_proyecto.m',
                'auditoria_psse_matpower/transpa_reduccion',
                'auditoria_psse_matpower/beerten_5bus',
                'auditoria_psse_matpower/tools', 'matpower/lib', 'matpower/data',
                '-g', '*.m', '-g', '*.py', '-g', '*.ps1', '-g', '*.md'])
assert refs.returncode in (0, 1)
write('live_transpa_references.txt', refs.stdout)
for repo in git_summary:
    after = command(['git', 'status', '--porcelain=v1', '-z', '--untracked-files=all'], ROOT/repo)
    assert after.stdout == (OUT/(repo+'_status_before.bin')).read_bytes(), repo
for item in manifest:
    assert hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest() == item['sha256'], item['path']

(OUT/'checkpoint_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
summary = {'root_git_operational':root_git.returncode == 0, 'repositories':git_summary,
           'inventory_files':len(files), 'inventory_excludes':['.git', '.venv', str(OUT.relative_to(ROOT))],
           'checkpoint_files':len(manifest), 'checkpoint_bytes':(OUT/'checkpoint.zip').stat().st_size,
           'archive_members_verified':True, 'source_files_unchanged':True,
           'git_status_unchanged':True, 'numerical_runs':0,
           'scope':'Code/input checkpoint only, not a complete backup of historical results, dependencies, configuration, or Git objects.'}
(OUT/'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps(summary, indent=2))
