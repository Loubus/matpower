"""Collect a small, pinned benchmark reference bundle; never execute MATLAB data."""
from pathlib import Path
import hashlib
import json
import re
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
UP = ROOT / 'upstream'
records = []

def record(path, url, revision=None, origin=None):
    raw = path.read_bytes()
    records.append(dict(path=str(path.relative_to(ROOT)).replace('\\', '/'),
                        source_url=url, revision=revision, archive_member=origin,
                        bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))

def fetch(repo, revision, paths, folder):
    for name in paths:
        url = f'https://raw.githubusercontent.com/{repo}/{revision}/{name}'
        dest = UP / folder / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            raise FileExistsError(dest)
        request = urllib.request.Request(url, headers={'User-Agent': 'thesis-benchmark-inventory'})
        with urllib.request.urlopen(request, timeout=45) as response:
            dest.write_bytes(response.read())
        record(dest, url, revision)

fetch('Electa-Git/PowerModelsACDC.jl', 'b6d7cdb07ff6ae864f41c1187ed289aa289a78d3',
      ['LICENSE.md', 'README.md', 'test/data/case5_acdc.m',
       'test/data/case24_3zones_acdc.m', 'test/data/case39_acdc.m'], 'PowerModelsACDC')
fetch('SPS-L/stepss-IEEE-Nordic-Test-system', 'f5152ddba55075c612e438e8473ef7a3b3c5dc3f',
      ['LICENSE', 'README.md', 'lf_A.dat', 'lf_B.dat', 'dyn_A.dat', 'dyn_B.dat'], 'Nordic')
fetch('Electa-Git/PowerModelsTopologicalActions.jl', '83db29405c522311c10fc681935291861c80ff17',
      ['LICENSE', 'test/data_sources/cigre_b4_dc_grid.m'], 'CIGRE_implementation')

archive = UP / 'MatACDC1_0.zip'
archive_url = 'https://www.esat.kuleuven.be/electa/teaching/matacdc/MatACDC1_0'
if not archive.exists():
    with urllib.request.urlopen(archive_url, timeout=45) as response:
        archive.write_bytes(response.read())
record(archive, archive_url, 'MatACDC1.0 official archive')
with zipfile.ZipFile(archive) as package:
    for member in package.infolist():
        if member.filename.startswith('MatACDC1.0/Cases/') and member.filename.endswith('.m'):
            dest = UP / 'MatACDC_cases' / Path(member.filename).name
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists():
                raise FileExistsError(dest)
            dest.write_bytes(package.read(member))
            record(dest, archive_url, 'MatACDC1.0', member.filename)

counts = []
for path in sorted(UP.rglob('*.m')):
    data = path.read_text(encoding='utf-8-sig', errors='replace')
    item = {'path': str(path.relative_to(ROOT)).replace('\\', '/')}
    clean = re.sub(r'%[^\n]*', '', data)
    for field in ['bus', 'gen', 'branch', 'busdc', 'convdc', 'branchdc']:
        match = re.search(r'(?<!\w)(?:(?:mpc|mpcdc)\.)?' + field + r'\s*=\s*\[(.*?)\]\s*;', clean, re.S)
        if match:
            item[field + '_literal_rows'] = sum(bool(row.strip()) for row in match[1].split(';'))
    counts.append(item)
(ROOT / 'source_manifest.json').write_text(json.dumps({
    'review_date': '2026-09-10',
    'status': 'Downloaded and statically inventoried only; not converted, installed, or solved.',
    'files': records, 'literal_matrix_row_counts': counts}, indent=2), encoding='utf-8')
print(json.dumps({'downloaded_or_extracted_files':len(records), 'counts':counts}, indent=2))
