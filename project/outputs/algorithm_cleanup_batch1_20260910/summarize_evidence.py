"""Summarize saved evidence without executing or changing scientific code."""
from pathlib import Path
import json
import re

out = Path(__file__).resolve().parent
log = (out / 'vsc_reproduced.log').read_text(encoding='utf-8')
acceptance = json.loads((out / 'acceptance_final/acceptance.json').read_text())
checks = acceptance['checks']
summary = {
    'scope': 'investigation and focused acceptance; no production solver edits',
    'legacy_vsc': {
        'failed_test_ids': [int(x) for x in re.findall(r'^not ok (\d+) ', log, re.M)],
        'summary': re.search(r'Ran 330 of 330 tests:.*', log).group(0),
        'elapsed_seconds': float(re.search(r'Elapsed time ([\d.]+) seconds', log).group(1)),
        'warning_lines': [x for x in log.splitlines() if re.search(r'\bwarning\b', x, re.I)],
    },
    'physical_gate': {
        'total': len(checks),
        'passed': sum(x['passed'] for x in checks),
        'failed': [x['id'] for x in checks if not x['passed']],
        'accepted': all(x['passed'] for x in checks),
    },
    'legacy_observations': acceptance['legacy'],
    'preservation': json.loads((out / 'preservation.json').read_text(encoding='utf-8-sig')),
}
(out / 'verification.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps({'legacy': summary['legacy_vsc'], 'physical': summary['physical_gate']}, indent=2))
