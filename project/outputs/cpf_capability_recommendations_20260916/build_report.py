"""Create engineering schematics and a standalone, offline illustrated report."""
from pathlib import Path
import base64, html, re, textwrap, hashlib, json
out=Path(__file__).resolve().parent
root=out.parent.parent

def svg_start(title,height):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 {height}" role="img"><title>{html.escape(title)}</title><defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10Z" fill="#486275"/></marker></defs><rect width="1200" height="{height}" fill="white"/>']
def text(s,x,y,t,size=18,color='#18384d',anchor='start',weight=400):
    s.append(f'<text x="{x}" y="{y}" font-family="Segoe UI,Arial,sans-serif" font-size="{size}" fill="{color}" text-anchor="{anchor}" font-weight="{weight}">{html.escape(t)}</text>')
def box(s,x,y,w,h,title,body,fill='#eef5f9'):
    s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="#a9bdc9"/>')
    text(s,x+w/2,y+29,title,20,anchor='middle',weight=600)
    lines=[]
    for p in body.split('|'): lines+=textwrap.wrap(p,max(17,int(w/9.8)))
    for i,line in enumerate(lines): text(s,x+w/2,y+56+23*i,line,17,anchor='middle')
def arrow(s,x1,y1,x2,y2):
    s.append(f'<path d="M{x1},{y1} L{x2},{y2}" fill="none" stroke="#486275" stroke-width="2" marker-end="url(#arrow)"/>')
def finish(s,name): (out/name).write_text(''.join(s)+'</svg>',encoding='utf-8')

s=svg_start('Current outer projection and proposed coupled equation solve',560)
text(s,30,34,'CURRENT PROCEDURE — measurements are reused as fixed orders',22,weight=600)
for x,title,body in [(30,'Electrical solve','Solve P/Q orders at fixed loading'),(330,'Capability check','Use solved P, Q and PCC voltage'),(630,'Project and reduce Q','Apply the extra 0.1% inward Q adjustment'),(930,'Re-solve network','Voltage changes; capability can change again')]: box(s,x,65,240,145,title,body,'#fff4e7')
for x in [270,570,870]: arrow(s,x,136,x+55,136)
s.append('<path d="M1050,214 L1050,245 L450,245 L450,213" fill="none" stroke="#b06a1a" stroke-width="2" marker-end="url(#arrow)"/>')
text(s,610,274,'Outer iteration may stall or move to a branch with no local solution',17,color='#8c4c0c',anchor='middle')
text(s,30,327,'PROPOSED PROCEDURE — one consistent electrical state',22,weight=600)
box(s,30,355,270,140,'Choose the active mode','Normal control OR the binding physical limit')
box(s,360,355,480,140,'One coupled Newton / CPF system','AC + DC + station + losses + selected limit equation',' #e8f5ef'.strip())
box(s,900,355,270,140,'Audit and accept','Every limit and discrete control checks the same state')
arrow(s,300,425,354,425); arrow(s,840,425,894,425)
text(s,30,541,'Design schematic. Existing solver code is unchanged.',16,color='#536775'); finish(s,'solve_sequences.svg')

s=svg_start('Coordinating all controllers through the full electrical solution',610)
box(s,400,235,400,135,'Shared AC/DC station solution','Voltages, currents, P/Q, losses and loading',' #e8f5ef'.strip())
box(s,30,50,310,125,'Generator capability','PV voltage control OR Q boundary')
box(s,860,50,310,125,'Converter capability','AC request OR current/voltage limit; keep DC duty')
box(s,30,420,310,125,'ULTC discrete position','Finite tap grid; evaluate the controlled bus voltage')
box(s,860,420,310,125,'Switched shunt','Finite B states; output Q changes with voltage')
arrow(s,340,160,432,229); arrow(s,768,229,862,160); arrow(s,860,122,801,251)
arrow(s,401,325,340,452); arrow(s,340,488,399,346)
arrow(s,801,345,860,455); arrow(s,860,489,801,363)
arrow(s,430,229,338,113)
text(s,600,70,'ONE TRIAL → ONE CONSISTENT ACTIVE SET',22,anchor='middle',weight=600)
text(s,600,124,'Locate events → update equations → re-solve',17,anchor='middle')
text(s,600,148,'Recheck all devices before accepting',17,anchor='middle')
text(s,600,460,'Rejected trial: restore the entire snapshot',18,anchor='middle',weight=600)
text(s,600,489,'Accepted trial: store state, modes and event IDs',17,anchor='middle')
text(s,30,589,'Design schematic. Physical saturation is allowed only under the declared study policy.',16,color='#536775'); finish(s,'coordination.svg')

s=svg_start('Separate electrical convergence, control acceptance, and completion',560)
steps=[(25,'Electrical equations','Residuals and voltages finite?'),(325,'Controls and limits','Active equalities, other limits and discrete state pass?'),(625,'Record curve events','Crossings, tangent sign change, trial versus accepted'),(925,'Endpoint decision','FULL complete, NOSE stop, or continue?')]
for x,t,b in steps: box(s,x,80,250,150,t,b)
for x in [275,575,875]: arrow(s,x,157,x+43,157)
for x in [150,450]: arrow(s,x,230,x,312)
box(s,25,320,250,142,'Numerical failure','Record inner residual, iterations, step and attempted order','#fff4e7')
box(s,325,320,250,142,'Control failure / bound','Distinguish physical exhaustion, unresolved controls and cycles','#fff4e7')
box(s,625,320,550,142,'An event is not necessarily a stop','Record a turn in both modes.|NOSE may stop; FULL can continue.','#e8f5ef')
arrow(s,750,230,750,313); arrow(s,1050,230,1050,313)
text(s,30,35,'PROPOSED REPORTING: KEEP THESE QUESTIONS SEPARATE',23,weight=600)
text(s,30,511,'Preserve the last accepted state even when the next candidate fails.',19,weight=600)
text(s,30,543,'A solver success flag alone is not evidence of a validated physical maximum.',17,color='#536775'); finish(s,'termination.svg')

def inline(t):
    t=html.escape(t)
    t=re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)',r'<a href="\2">\1</a>',t)
    t=re.sub(r'`([^`]+)`',r'<code>\1</code>',t)
    return re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',t)
lines=(out/'REPORT.md').read_text(encoding='utf-8').splitlines(); blocks=[]; i=0; count=0
while i<len(lines):
    line=lines[i]
    if not line: i+=1; continue
    if line.startswith('#'):
        level=len(line)-len(line.lstrip('#')); title=line[level:].strip(); anchor=''
        if level==2 and re.match(r'[1-5]\.',title): anchor=f' id="proposal-{title[0]}"'
        blocks.append(f'<h{level}{anchor}>{inline(title)}</h{level}>')
    elif line.startswith('!['):
        alt,name=re.fullmatch(r'!\[(.*?)\]\((.*?)\)',line).groups(); data=base64.b64encode((out/name).read_bytes()).decode(); mime='image/svg+xml' if name.endswith('.svg') else 'image/png'; count+=1
        cls='equation' if name.startswith('eq_') else 'figure'
        blocks.append(f'<figure class="{cls}"><img alt="{html.escape(alt)}" src="data:{mime};base64,{data}"><figcaption>{html.escape(alt)}</figcaption></figure>')
    elif line.startswith('|'):
        rows=[]
        while i<len(lines) and lines[i].startswith('|'):
            cells=[c.strip() for c in lines[i].strip('|').split('|')]
            if not all(re.fullmatch(r'[:\- ]+',c) for c in cells):
                tag='th' if not rows else 'td'; rows.append('<tr>'+''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells)+'</tr>')
            i+=1
        blocks.append('<div class="table-scroll"><table>'+''.join(rows)+'</table></div>'); continue
    elif line.startswith('- ') or re.match(r'\d+\. ',line):
        ordered=not line.startswith('- '); tag='ol' if ordered else 'ul'; rows=[]
        while i<len(lines) and (re.match(r'\d+\. ',lines[i]) if ordered else lines[i].startswith('- ')):
            value=re.sub(r'^\d+\. ','',lines[i]) if ordered else lines[i][2:]; rows.append('<li>'+inline(value)+'</li>'); i+=1
        blocks.append(f'<{tag}>'+''.join(rows)+f'</{tag}>'); continue
    else: blocks.append('<p>'+inline(line)+'</p>')
    if line.startswith('![Quantitative reserve comparison]'):
        blocks.append('<div class="interactive"><h3>Explore the distinction at a fixed voltage</h3>'+(out/'current-reserve.html').read_text()+'</div>')
    i+=1
css='''
:root{color-scheme:light;--foreground:#20384c;--viz-series-1:#216caa;--viz-series-2:#b06313}*{box-sizing:border-box}body{margin:0;background:#eef3f6;color:#203447;font:17px/1.68 system-ui,Segoe UI,sans-serif}main{max-width:1190px;margin:auto;background:white;padding:48px 52px 80px}h1{font-size:41px;line-height:1.16;color:#163e55;margin-top:0}h2{font-size:29px;line-height:1.28;margin:52px 0 20px;padding-top:22px;border-top:3px solid #dbe7ee}h3{font-size:21px;margin:27px 0 8px}p{margin:17px 0}a{color:#096491}code{font:0.88em ui-monospace,Consolas,monospace;background:#f0f4f6;overflow-wrap:anywhere;padding:2px 4px}nav{display:flex;gap:8px 24px;flex-wrap:wrap;padding:16px 0;border-bottom:1px solid #dbe7ee;margin-bottom:27px}nav a{text-decoration:none;font-weight:600}figure{margin:28px -20px}figure img{width:100%;height:auto}figcaption{font-size:14px;text-align:center;color:#546e80}.equation{margin:24px 0}.equation img{width:100%;max-height:350px;object-fit:contain}.equation figcaption{font-size:13px}.table-scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:15px;margin:18px 0}td,th{padding:11px 14px;text-align:left;border-bottom:1px solid #d5e1e8;vertical-align:top}th{background:#19485f;color:white}tr:nth-child(even){background:#f1f6f9}li{margin:10px 0}.interactive{padding:22px;background:#f4f8fa;border-left:4px solid #42708d;margin:25px 0}.viz-controls{display:flex;gap:24px;flex-wrap:wrap}.form-label{display:block;flex:1;min-width:250px}.form-range{width:100%}.viz-row{display:flex;gap:20px;justify-content:space-between;margin:15px 0 5px}.progress{height:12px;background:#e0e8ee}.progress-bar{height:100%}.text-small{font-size:14px}.text-muted{color:#4f6879}.text-end{text-align:right}.tabular-nums{font-variant-numeric:tabular-nums}.table-responsive{overflow:auto}#cpf-current-reserve h3{margin-top:4px}strong{color:#173e55}footer{margin-top:50px;font-size:14px;color:#586f7e}@media(max-width:700px){main{padding:26px 20px}h1{font-size:30px}h2{font-size:25px}figure{margin:20px 0}.equation{overflow:auto}.equation img{min-width:620px}.form-label{min-width:220px}}@media print{body{background:white}main{padding:0}nav,.interactive{display:none}figure,table{break-inside:avoid}h2,h3{break-after:avoid}}
'''
nav='<nav aria-label="Recommendations">'+''.join(f'<a href="#proposal-{k}">{k}. {t}</a>' for k,t in enumerate(['Coupled limits','Continuation','Reserve','Coordination','Reporting'],1))+'</nav>'
(out/'REPORT.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Five changes for capability-limited CPF</title><style>'+css+'</style><main>'+nav+'\n'.join(blocks)+'<footer>Engineering explanation · 16 September 2026 · Proposed solver changes are not implemented.</footer></main></html>',encoding='utf-8')
paths=['matpower/lib/runcpf_vsc_mtdc.m','matpower/lib/runpf_vsc_mtdc_unified.m','matpower/lib/vsc_station_map.m','matpower/lib/vsc_station_capability.m','studies/beerten/beerten_constant_pq_nonslack_dispatch.m']
(out/'source_sha256.json').write_text(json.dumps({p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths},indent=2))
print(f'Built standalone REPORT.html: {count} embedded diagrams, plots and rendered equations; no external image or script dependencies.')
