from pathlib import Path
import re,json,base64,html
out=Path(__file__).resolve().parent
entries=[('Baseline','baseline_main'),('A: coupled current','A_100'),('B: continuation + all-control direction','B2_100'),('A+B: combined + all-control direction','AB2_100'),('Baseline','baseline_half'),('A: coupled current','A_050'),('B: continuation + all-control direction','B2_050'),('A+B: combined + all-control direction','AB2_050')]
table=['| Variant | Step | Accepted points | Maximum sampled lambda | Final lambda | Final V5 | Stop |','|---|---:|---:|---:|---:|---:|---|']
metrics=[]
for i,(label,stem) in enumerate(entries):
    a=json.loads((out/(stem+'_audit.json')).read_text()); end=a['endpoint']; step=.1 if i<4 else .05
    table.append(f'| {label} | {step:.2f} | {a["points"]} | {a["sampled_max_lambda"]:.9f} | {end["lambda"]:.9f} | {end["V5"]:.6f} | {a["termination"]["cause"]} |')
    metrics.append({'variant':label,'step':step,'points':a['points'],'max_sample_lambda':a['sampled_max_lambda'],'final_lambda':end['lambda'],'final_V5':end['V5'],'FULL_complete':a['termination']['requested_endpoint_reached'],'stop':a['termination']['cause']})
md=(out/'REPORT.md').read_text(encoding='utf-8'); md=md.replace('<!-- RESULTS_TABLE -->','\n'.join(table)); (out/'REPORT.md').write_text(md,encoding='utf-8')
(out/'comparison_metrics.json').write_text(json.dumps(metrics,indent=2))
def inline(s):
    s=html.escape(s)
    s=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'<a href="\2">\1</a>',s)
    s=re.sub(r'`([^`]+)`',r'<code>\1</code>',s)
    return re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',s)
lines=md.splitlines(); blocks=[]; i=0
while i<len(lines):
    line=lines[i]
    if not line: i+=1; continue
    if line.startswith('#'):
        n=len(line)-len(line.lstrip('#')); blocks.append(f'<h{n}>{inline(line[n:].strip())}</h{n}>')
    elif line.startswith('!['):
        alt,path=re.fullmatch(r'!\[(.*?)\]\((.*?)\)',line).groups(); data=base64.b64encode((out/path).read_bytes()).decode()
        blocks.append(f'<figure><img alt="{html.escape(alt)}" src="data:image/png;base64,{data}"><figcaption>{html.escape(alt)}</figcaption></figure>')
    elif line.startswith('|'):
        rows=[]
        while i<len(lines) and lines[i].startswith('|'):
            cells=[c.strip() for c in lines[i].strip('|').split('|')]
            if not all(re.fullmatch(r'[:\- ]+',c) for c in cells):
                tag='th' if not rows else 'td'; rows.append('<tr>'+''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells)+'</tr>')
            i+=1
        blocks.append('<div class="table"><table>'+''.join(rows)+'</table></div>'); continue
    elif re.match(r'^\d+\. ',line):
        lis=[]
        while i<len(lines) and re.match(r'^\d+\. ',lines[i]):
            lis.append('<li>'+inline(re.sub(r'^\d+\. ','',lines[i]))+'</li>'); i+=1
        blocks.append('<ol>'+''.join(lis)+'</ol>'); continue
    else: blocks.append('<p>'+inline(line)+'</p>')
    i+=1
css='''body{margin:0;background:#eef2f5;color:#23384a;font:17px/1.65 system-ui,Segoe UI,sans-serif}main{max-width:1190px;margin:auto;padding:42px 50px 70px;background:white;box-sizing:border-box}h1{font-size:37px;line-height:1.2;color:#173e55}h2{font-size:26px;margin-top:43px;border-top:2px solid #dce7ee;padding-top:22px}a{color:#006292}code{font:14px ui-monospace,Consolas,monospace;background:#eef3f6;padding:2px 4px;overflow-wrap:anywhere}figure{margin:30px -22px}img{width:100%;height:auto}figcaption{font-size:14px;color:#546b7b;text-align:center}.table{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}th{background:#214d64;color:white}th,td{padding:9px 10px;text-align:left;border-bottom:1px solid #d8e3ea}tr:nth-child(even){background:#f3f7fa}li{margin:12px 0}strong{color:#183e55}@media(max-width:700px){main{padding:20px}h1{font-size:28px}figure{margin:20px 0}}@media print{body{background:white}main{padding:0}figure,table{break-inside:avoid}}'''
(out/'REPORT.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CPF solution experiments</title><style>'+css+'</style><main>'+'\n'.join(blocks)+'</main></html>',encoding='utf-8')
print('Built report with 3 embedded comparison figures and measured result tables.')
