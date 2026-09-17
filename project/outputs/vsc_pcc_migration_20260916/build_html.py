from pathlib import Path
import re,html,io,base64,json
from matplotlib.mathtext import math_to_image
from matplotlib.font_manager import FontProperties
OUT=Path(__file__).resolve().parent
def equation(tex,inline=False):
    tex=tex.replace(r'\bigl', '').replace(r'\bigr','')
    tex=re.sub(r'\\le(?![a-z])',r'\\leq',tex)
    buf=io.BytesIO()
    math_to_image('$'+tex+'$',buf,format='svg',prop=FontProperties(size=12 if inline else 17),color='#15364b')
    svg=buf.getvalue().decode(); svg=svg[svg.index('<svg'):]
    svg=svg.replace('<svg ',f'<svg aria-label="{html.escape(tex,quote=True)}" role="img" ',1)
    return ('<span class="math">' if inline else '<div class="equation">')+svg+('</span>' if inline else '</div>')
def inline(s):
    chunks=re.split(r'(\\\(.*?\\\))',s)
    out=[]
    for x in chunks:
        if x.startswith(r'\('): out.append(equation(x[2:-2],True));continue
        x=html.escape(x)
        x=re.sub(r'`([^`]+)`',r'<code>\1</code>',x)
        x=re.sub(r'\*\*(.*?)\*\*',r'<strong>\1</strong>',x)
        x=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'<a href="\2">\1</a>',x)
        out.append(x)
    return ''.join(out)
src=(OUT/'REPORT.md').read_text(encoding='utf-8')
src=src.replace('\\]\n\\[','\\]\n\n\\[')
blocks=re.split(r'\n\s*\n',src); body=[]
for b in blocks:
    b=b.strip()
    if b.startswith('# '): body.append('<h1>'+inline(b[2:])+'</h1>')
    elif b.startswith('## '): body.append('<h2>'+inline(b[3:])+'</h2>')
    elif b.startswith(r'\['): body.append(equation(b[2:-2].replace('\n',' ')))
    elif b.startswith('|'):
        rows=b.splitlines(); head=rows[0]; data=rows[2:]
        def row(x,tag): return '<tr>'+''.join('<'+tag+'>'+inline(v.strip())+'</'+tag+'>' for v in x.strip('|').split('|'))+'</tr>'
        body.append('<div class="table"><table><thead>'+row(head,'th')+'</thead><tbody>'+''.join(row(x,'td') for x in data)+'</tbody></table></div>')
    elif b.startswith('!['):
        name=re.search(r'\]\(([^)]+)\)',b).group(1)
        img=base64.b64encode((OUT/name).read_bytes()).decode()
        body.append('<figure><img alt="Full station capability comparison" src="data:image/png;base64,'+img+'"></figure>')
    elif b.startswith('- '):
        items=re.split(r'\n- ',b[2:]); body.append('<ul>'+''.join('<li>'+inline(x.replace('\n',' '))+'</li>' for x in items)+'</ul>')
    else: body.append('<p>'+inline(b.replace('\n',' '))+'</p>')
css='''body{margin:0;background:#edf3f6;color:#183142;font:17px/1.65 system-ui,sans-serif}main{max-width:1100px;margin:auto;background:white;padding:48px 5vw}h1{font-size:38px;line-height:1.15;max-width:850px}h2{margin-top:48px;border-top:2px solid #138c85;padding-top:20px;font-size:25px}p{max-width:950px}code{background:#edf3f6;padding:1px 4px;overflow-wrap:anywhere}a{color:#066985;overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:15px}td,th{padding:12px;text-align:left;border-bottom:1px solid #dbe5ea;min-width:170px}th{background:#123b52;color:white}tr:nth-child(even){background:#f4f8fa}.table{overflow-x:auto}.math{display:inline-block;vertical-align:middle}.math svg{max-width:100%;height:auto}.equation{overflow-x:auto;padding:24px 0}.equation svg{max-width:100%;height:auto}figure{margin:24px 0}img{max-width:100%;height:auto}li{margin-bottom:10px}.stamp{color:#0c746e;font-weight:650;letter-spacing:.06em;font-size:14px}@media(max-width:600px){main{padding:24px 5vw}h1{font-size:29px}body{font-size:16px}}'''
out='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Five-bus Beerten: PCC migration</title><style>'+css+'</style><main><div class="stamp">VERIFIED MODEL CHANGE · 16 SEPTEMBER 2026</div>'+''.join(body)+'</main></html>'
(OUT/'REPORT.html').write_text(out,encoding='utf-8')
print(json.dumps({'html_bytes':len(out),'rendered_equations':out.count('<svg')}))
