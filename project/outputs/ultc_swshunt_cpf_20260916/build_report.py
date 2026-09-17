"""Build a self-contained HTML companion without external dependencies."""
from pathlib import Path
import base64
import html
import re
import hashlib
import json

out = Path(__file__).resolve().parent
root = out.parent.parent

def inline(s):
    s = html.escape(s)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    return re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)

blocks = []
lines = (out / 'REPORT.md').read_text(encoding='utf-8').splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    if not line:
        i += 1
        continue
    if line.startswith('#'):
        level = len(line) - len(line.lstrip('#'))
        blocks.append(f'<h{level}>{inline(line[level:].strip())}</h{level}>')
    elif line.startswith('!['):
        payload = base64.b64encode((out / 'control_cpf.png').read_bytes()).decode()
        blocks.append(f'<figure><img alt="Six panels showing accepted voltages, tap ratios, shunt support, generator dispatch, reactive powers and converter currents" src="data:image/png;base64,{payload}"><figcaption>Accepted states only. Dashed comparison uses half the continuation step.</figcaption></figure>')
    elif line.startswith('|'):
        rows = []
        while i < len(lines) and lines[i].startswith('|'):
            cells = [c.strip() for c in lines[i].strip('|').split('|')]
            if not all(re.fullmatch(r'[:\- ]+', c) for c in cells):
                tag = 'th' if not rows else 'td'
                rows.append('<tr>' + ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells) + '</tr>')
            i += 1
        blocks.append('<div class="table"><table>' + ''.join(rows) + '</table></div>')
        continue
    elif line.startswith('- '):
        rows = []
        while i < len(lines) and lines[i].startswith('- '):
            rows.append('<li>' + inline(lines[i][2:]) + '</li>')
            i += 1
        blocks.append('<ul>' + ''.join(rows) + '</ul>')
        continue
    else:
        blocks.append('<p>' + inline(line) + '</p>')
    i += 1

css = """
:root{color-scheme:light}body{margin:0;background:#edf2f6;color:#182638;font:17px/1.65 system-ui,Segoe UI,sans-serif}
main{max-width:1130px;margin:auto;padding:50px 48px 80px;background:white}h1{font-size:38px;line-height:1.15;color:#123e58}
h2{font-size:25px;margin:40px 0 12px;border-top:1px solid #d7e1e8;padding-top:24px}p{margin:18px 0}p:first-of-type{background:#fff4d9;border-left:5px solid #c47d09;padding:20px}
figure{margin:28px -18px}img{width:100%;height:auto}figcaption{font-size:14px;color:#536775;text-align:center}
.table{overflow:auto}table{border-collapse:collapse;width:100%;font-size:15px;margin:16px 0}td,th{padding:10px 12px;border-bottom:1px solid #d8e2e8;text-align:left}th{background:#163e56;color:white}tr:nth-child(even){background:#f2f6f9}
code{font:0.88em ui-monospace,Consolas,monospace;background:#eef3f6;padding:2px 4px;overflow-wrap:anywhere}li{margin:6px 0}
@media(max-width:700px){main{padding:24px 18px}h1{font-size:29px}figure{margin:20px 0}}
@media print{body{background:white}main{padding:0;font-size:11pt}h2{break-after:avoid}table,figure{break-inside:avoid}}
"""
(out / 'REPORT.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ULTC and switched-shunt CPF verification</title><style>' + css + '</style><main>' + '\n'.join(blocks) + '</main></html>', encoding='utf-8')
paths = ['studies/beerten/beerten_constant_pq_nonslack_dispatch.m', 'studies/beerten/beerten_constant_pq_capability_batch6.m', 'matpower/lib/runcpf_vsc_mtdc.m', 'matpower/lib/vsc_station_map.m', 'matpower/lib/vsc_station_capability.m', 'matpower/lib/vsc_loss_coefficients.m', 'matpower/lib/gen_capability_curve.m', 'matpower/lib/+mp/psse_xfmr_states.m', 'matpower/lib/+mp/psse_xfmr_tap_decision.m']
hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths}
(out / 'source_sha256.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
print('Built standalone REPORT.html; embedded one inspected figure; recorded source hashes.')
