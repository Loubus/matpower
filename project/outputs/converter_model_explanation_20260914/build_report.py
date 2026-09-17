from pathlib import Path
import json, hashlib, html, io, base64, re, csv
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.mathtext import math_to_image
from matplotlib.font_manager import FontProperties

OUT=Path(__file__).resolve().parent
ROOT=OUT.parent.parent
E=json.loads((OUT/'evidence.json').read_text())
A=json.loads((OUT/'reference_station.json').read_text())
H=json.loads((ROOT/'outputs/beerten_validation_batch6_20260911/final_04/capability_step_100.json').read_text())
ASSET=OUT/'assets';ASSET.mkdir(exist_ok=True)
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'axes.spines.top':False,'axes.spines.right':False,'svg.fonttype':'path','axes.titleweight':'bold'})
BLUE='#176a98';RED='#c45636';GREEN='#267b62';INK='#182f40';PURPLE='#795da6'
SOURCES={}
def cite(path,start,end=None):
    corrections={
      ('studies/beerten/beerten_constant_pq_nonslack_dispatch.m',1):(1,37),
      ('studies/beerten/beerten_constant_pq_nonslack_dispatch.m',20):(20,37),
      ('cases/beerten/variants/case5_vsc_mtdc_beerten.m',44):(42,96),
      ('cases/beerten/variants/case5_vsc_mtdc_beerten.m',105):(90,96),
      ('matpower/lib/apply_vsc_ac_model.m',71):(69,143),
      ('matpower/lib/apply_vsc_ac_model.m',80):(76,143),
      ('matpower/lib/apply_vsc_ac_model.m',88):(80,143),
      ('matpower/lib/calc_vsc_losses.m',29):(29,39),
      ('matpower/lib/makeGdc.m',48):(43,66),
      ('matpower/lib/update_vsc_state.m',85):(78,94),
      ('matpower/lib/vsc_capability_curve.m',115):(108,142),
      ('matpower/lib/vsc_capability_policy.m',44):(40,82),
      ('matpower/lib/vsc_capability_policy.m',64):(60,82),
      ('matpower/lib/check_vsc_capability.m',116):(105,115),
      ('matpower/lib/enforce_vsc_capability_active_set.m',49):(48,65),
      ('matpower/lib/enforce_vsc_capability_active_set.m',72):(68,80),
      ('matpower/lib/enforce_vsc_capability_active_set.m',167):(148,159),
      ('matpower/lib/vsc_capability_geometry.m',172):(148,168)}
    if (path,start) in corrections:start,end=corrections[(path,start)]
    end=end or start
    key=re.sub(r'\W','_',path)
    SOURCES.setdefault(path,[]).append((start,end))
    return f'<a class="cite" href="#src-{key}-{start}" onclick="document.getElementById(\'source-{key}\').open=true">{html.escape(path)}:{start}–{end}</a>'
eqnum=0
def eq(tex):
    global eqnum
    eqnum+=1;b=io.BytesIO()
    tex=tex.replace(r'\frac16',r'\frac{1}{6}')
    tex=re.sub(r'\\underline ([A-Za-z])',r'\\underline{\1}',tex)
    tex=re.sub(r'\\boldsymbol ([A-Za-z])',r'\\boldsymbol{\1}',tex)
    math_to_image('$'+tex+'$',b,format='svg',dpi=180,color=INK,prop=FontProperties(size=17))
    svg=b.getvalue().decode();svg=svg[svg.index('<svg'):]
    # Preserve natural equation proportions, with accessible text alternatives.
    svg=svg.replace('<svg ',f'<svg role="img" aria-label="{html.escape(tex,quote=True)}" ',1)
    (ASSET/f'equation-{eqnum:02}.svg').write_text(svg,encoding='utf-8')
    return f'<div class="equation">{svg}<span class="eqno">({eqnum})</span></div>'
def table(headers,rows):
    return '<div class="tablewrap"><table><thead><tr>'+''.join(f'<th>{x}</th>' for x in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join(f'<td>{x}</td>' for x in row)+'</tr>' for row in rows)+'</tbody></table></div>'
def fig(name,caption):
    p=ASSET/name
    if p.suffix=='.svg':
        s=p.read_text(encoding='utf-8');s=s[s.index('<svg'):]
    else:s='<img src="data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()+'" alt="'+html.escape(caption,quote=True)+'">'
    return f'<figure>{s}<figcaption>{caption}</figcaption></figure>'
def saveplot(fig_,name):
    fig_.savefig(ASSET/(name+'.png'),dpi=180,bbox_inches='tight',facecolor='white')
    fig_.savefig(ASSET/(name+'.svg'),bbox_inches='tight',facecolor='white')
    plt.close(fig_)

# Current boundaries are calculated in MATLAB from the full station model.
theta=np.linspace(0,2*np.pi,700)
for state,ri,title in [('project_base',0,'Fresh seven-bus base'),('project_endpoint',2,'Historical batch-6 endpoint')]:
    fig_,axs=plt.subplots(1,3,figsize=(14.6,4.7),layout='constrained')
    for k,ax in enumerate(axs):
        b=next(b for b in E['boundaries'] if b['name']==state and b['converter']==k+1)
        r=E['rows'][ri]['station'][k];u=b['u']
        ax.plot(150*u*np.cos(theta),150*u*np.sin(theta),'--',color=RED,lw=2,label='Implemented current circle')
        v=np.array(b['current_internal']);ax.plot(v[:,0],v[:,1],color=BLUE,lw=2,label='Exact reactor current boundary')
        ax.axvline(-150,color='#8898a0',ls=':',lw=1);ax.axvline(150,color='#8898a0',ls=':',lw=1)
        ax.scatter(r['Pc'],r['Qc'],s=60,c=INK,zorder=5)
        ax.annotate(f"({r['Pc']:.1f}, {r['Qc']:.1f})",(r['Pc'],r['Qc']),xytext=(8,-20),textcoords='offset points',fontsize=10)
        ax.set(xlim=(-185,185),ylim=(-180,185),xlabel='$P_c$ (MW)',ylabel='$Q_c$ (MVAr)',title=f"C{k+1} · PCC {r['pcc']} · $U_s$={u:.3f}")
        ax.axhline(0,c='#dce3e7',lw=.7);ax.axvline(0,c='#dce3e7',lw=.7);ax.grid(alpha=.18);ax.set_aspect('equal')
    axs[0].legend(loc='lower left',fontsize=9)
    fig_.suptitle(title+' | internal-power coordinates',fontsize=15)
    saveplot(fig_,state+'_capability')

# Voltage circles have a different center when coordinates are internal.
fig_,axs=plt.subplots(1,2,figsize=(12.6,5),layout='constrained')
r=E['rows'][2]['station'][1];u=r['Us'];x=.0393;pc=np.linspace(-150,150,501)/100;umax=1.15
qapprox=-u*u/x+np.sqrt((u*umax/x)**2-pc**2)
qexact=umax*umax/x-np.sqrt((u*umax/x)**2-pc**2)
axs[0].plot(pc*100,qapprox*100,'--',color=RED,label='Implemented upper-voltage arc')
axs[0].plot(pc*100,qexact*100,color=BLUE,label='Exact high-voltage internal arc')
axs[0].scatter(r['Pc'],r['Qc'],c=INK,label='Historical C2 endpoint')
axs[0].set(xlabel='$P_c$ (MW)',ylabel='$Q_c$ (MVAr)',title='C2 at fixed PCC voltage 0.943419 pu',ylim=(80,700));axs[0].legend(fontsize=9);axs[0].grid(alpha=.2)
qc=np.linspace(-120,600,501)/100;p=r['Pc']/100;disc=(u*u+2*x*qc)**2-4*x*x*(p*p+qc*qc)
w=(u*u+2*x*qc+np.sqrt(np.maximum(disc,0)))/2;uc=np.sqrt(w)
uv=np.sqrt((u*u+x*qc)**2+(x*p)**2)/u
axs[1].plot(qc*100,uc,color=BLUE,label='Exact station $U_c$ (high-voltage root)')
axs[1].plot(qc*100,uv,'--',color=RED,label='Voltage inferred by mixed-port circle')
axs[1].axhline(1.15,color=PURPLE,ls=':',label='Assumed $U_{c,max}$=1.15')
axs[1].scatter(r['Qc'],r['Uc'],color=INK)
axs[1].set(xlabel='$Q_c$ (MVAr)',ylabel='Internal voltage (pu)',title=f"C2 slice at $P_c$={r['Pc']:.3f} MW");axs[1].legend(fontsize=9);axs[1].grid(alpha=.2)
saveplot(fig_,'voltage_boundary')

fig_,axs=plt.subplots(1,3,figsize=(14.5,4.5),layout='constrained')
for k,ax in enumerate(axs):
    b=next(b for b in E['boundaries'] if b['name']=='archive_reference' and b['converter']==k+1)
    for field,color,label,ls in [('current_pcc',BLUE,'Exact $I_c$ limit','-'),('voltage_pcc',PURPLE,'Exact $U_{c,max}$','-'),('min_voltage_pcc',PURPLE,'Exact $U_{c,min}$',':')]:
        ar=np.array(b[field]);ax.plot(ar[:,0],ar[:,1],color=color,label=label,ls=ls,lw=1.8)
    ax.plot(b['u']*1.2*100*np.cos(theta),b['u']*1.2*100*np.sin(theta),'--',c='#999',label='Current, filter omitted')
    ax.scatter(A['Ps'][k],A['Qs'][k],c=INK,s=50,zorder=5)
    ax.annotate(f"({A['Ps'][k]:.1f}, {A['Qs'][k]:.1f})",(A['Ps'][k],A['Qs'][k]),xytext=(6,8),textcoords='offset points',fontsize=9)
    ax.set(xlim=(-140,140),ylim=(-145,145),xlabel='$P_s$ (MW)',ylabel='$Q_s$ (MVAr)',title=f'Archive C{k+1} · PCC {[2,3,5][k]}');ax.set_aspect('equal');ax.grid(alpha=.2)
axs[0].legend(loc='lower left',fontsize=8)
saveplot(fig_,'reference_capability')

fig_,axs=plt.subplots(1,2,figsize=(12.8,4.8),layout='constrained')
lam=np.array([p['lambda'] for p in E['trace']]);tr=[p['station'][1] for p in E['trace']]
axs[0].plot(lam,[p['I_surrogate_ratio'] for p in tr],'--',c=RED,label='Implemented utilization')
axs[0].plot(lam,[p['I_ratio'] for p in tr],c=BLUE,label='Full reactor-current utilization')
axs[0].axhline(1,c='#777',lw=1);axs[0].set(xlabel='Historical loading parameter λ',ylabel='Current / 1.5 pu',title='C2 current along accepted batch-6 trace');axs[0].legend(fontsize=9)
axs[1].plot(lam,[p['Qc'] for p in tr],c=BLUE,label='Internal $Q_c$')
axs[1].plot(lam,[p['Qs'] for p in tr],'--',c=GREEN,label='PCC $Q_s$')
axs[1].fill_between(lam,[p['Qs'] for p in tr],[p['Qc'] for p in tr],alpha=.16,color=BLUE,label='Station reactive consumption')
axs[1].set(xlabel='Historical loading parameter λ',ylabel='Reactive power (MVAr)',title='The support delivered to the grid is smaller');axs[1].legend(fontsize=9)
for ax in axs:
    ax.axvline(1.104504838,c=PURPLE,ls=':',lw=1.2);ax.grid(alpha=.2)
saveplot(fig_,'history_trace')

# Original engineering diagrams, with symbols and routes chosen for legibility.
class Diagram:
    def __init__(self,w,h,title):self.w=w;self.h=h;self.parts=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" role="img" aria-label="{html.escape(title)}"><title>{html.escape(title)}</title><defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10z" fill="{INK}"/></marker></defs><rect width="100%" height="100%" fill="white"/>']
    def path(self,d,color=INK,width=2,dash='',arrow=False):self.parts.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-dasharray="{dash}"'+(' marker-end="url(#arrow)"' if arrow else '')+'/>')
    def text(self,x,y,t,size=17,anchor='middle',color=INK,weight='normal'):
        for i,line in enumerate(t.split('\n')):self.parts.append(f'<text x="{x}" y="{y+i*(size+7)}" text-anchor="{anchor}" fill="{color}" font-family="Arial,sans-serif" font-size="{size}" font-weight="{weight}">{html.escape(line)}</text>')
    def rect(self,x,y,w,h,fill='#edf4f8',stroke=INK,dash=''):self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="1.5" stroke-dasharray="{dash}"/>')
    def circle(self,x,y,r,fill='white',color=INK):self.parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{color}" stroke-width="2"/>')
    def bus(self,x,y,n):self.path(f'M{x-28} {y}H{x+28}',width=7);self.text(x,y-17,n,18,weight='bold')
    def write(self,name): (ASSET/name).write_text(''.join(self.parts)+'</svg>',encoding='utf-8')

def singleline(extension=True):
    d=Diagram(1140,960,'Seven-bus project AC/DC single-line' if extension else 'Five-bus Beerten and MatACDC reference single-line')
    d.text(38,34,'AC grid · all original electrical connections shown',22,'start',weight='bold')
    pos={1:(160,150),2:(160,405),3:(445,150),4:(720,150),5:(720,405)}
    for a,b in [(1,2),(1,3),(2,3),(2,4),(2,5),(3,4),(4,5)]:
        x,y=pos[a];xx,yy=pos[b];d.path(f'M{x} {y}L{xx} {yy}',color='#607581')
    for n,(x,y) in pos.items():d.bus(x,y,str(n))
    d.circle(85,150,23);d.text(85,157,'~',26);d.path('M108 150H132');d.text(30,86,'G1 · AC slack\n1.06 pu, θ=0°',16,'start');d.text(30,198,'P and Q solved',15,'start')
    d.text(445,92,'Load 45 + j15',16);d.text(720,92,'Load 0' if extension else 'Load 40 + j5',16)
    d.text(160,450,'Load 20 + j10',16);d.text(720,450,'Load 60 + j10',16)
    if extension:
        d.path('M160 405H50V570H160',color=PURPLE);d.bus(160,570,'6');d.circle(220,570,23);d.text(220,577,'~',26);d.path('M188 570H197');d.text(500,530,'G2 · PV · 13.8 kV',17,'start',weight='bold');d.text(500,558,'VG=1.0 pu; P=40+240λ MW',16,'start');d.text(500,585,'6–2: 0.005+j0.05 pu; tap=1',15,'start')
        d.path('M720 150H915',color=PURPLE);d.circle(813,150,14);d.circle(833,150,14);d.bus(945,150,'7');d.path('M945 150V195',arrow=True);d.text(945,225,'Load 40 + j5',16);d.text(875,280,'4–7 ULTC · 10 positions\ntap 0.9…1.1; V7 band 0.95…1.03',15);d.text(875,332,'Base solved tap 1.011111',15)
        d.path('M748 405H945V437');d.path('M925 437H965M925 446H965M945 446V468M929 468H961M934 475H956');d.text(945,507,'Bus-5 shunt\n0 / 5 / 10 / 15 MVAr at 1 pu',15)
    else:
        d.circle(85,405,23);d.text(85,412,'~',26);d.path('M108 405H132');d.text(30,510,'G2 at bus 2\nPV: P=40 MW; VG=1.0 pu',16,'start')
        d.text(770,365,'No buses 6 or 7\nNo automatic ULTC/shunt',16,'start')
    # Station links run below the AC grid; labels separate the two networks.
    for x,n,k in [(160,2,1),(445,3,2),(720,5,3)]:
        sy=pos[n][1]
        if n==3:d.path(f'M{x} {sy}V630',color=BLUE,dash='5 4')
        else:d.path(f'M{x} {sy}V485H{x+110}V630',color=BLUE,dash='5 4')
        cx=x if n==3 else x+110
        d.rect(cx-38,630,76,43,fill='#e8f3ef');d.text(cx,657,f'C{k}',19,weight='bold')
        if k==2:
            d.path(f'M{cx} 673V700 M{cx} 720V775',color=GREEN)
            d.path(f'M{cx} 700Q{cx+14} 710 {cx} 720',color=GREEN)
            d.bus(cx,775,'DC '+(str(n) if extension else str(k)))
        else:d.path(f'M{cx} 673V710',color=GREEN);d.bus(cx,710,'DC '+(str(n) if extension else str(k)))
    d.path('M270 710L445 775L830 710M270 710H830',color=GREEN,width=3)
    d.text(300,782,'2–3: .02633' if extension else '1–2: .052/pole',14)
    d.text(685,784,'3–5: .02337' if extension else '2–3: .052/pole',14)
    d.text(560,699,'2–5: .03601 pu' if extension else '1–3: .073 pu/pole',14)
    d.text(1000,662,'DC network',20,weight='bold');d.text(1000,700,'300 kV base\nNo explicit pole count' if extension else '345 kV base\nMatACDC pol=2',15)
    d.text(215,852,'C1: P/Q control\n−60 MW / −40 MVAr',16)
    d.text(545,878,'C2: Vdc=1 pu + PCC Vac=1 pu\nActive and reactive power solved',16)
    d.text(880,852,'C3: P/Q control\n+35 MW / +5 MVAr',16)
    d.text(570,938,'P/Q schedules are internal in the project; PCC schedules in the reference. Crossings without dots are not connected.',14)
    d.write('singleline-project.svg' if extension else 'singleline-reference.svg')
singleline();singleline(False)

d=Diagram(1140,600,'Converter station with physical components, model terminals and directed powers')
d.text(35,36,'One station, three AC terminals, two different power-control ports',23,'start',weight='bold')
d.bus(80,220,'PCC s');d.text(80,268,'Uₛ ∠δₛ',20)
d.path('M108 220H260');d.circle(210,220,25);d.circle(235,220,25);d.text(225,160,'Transformer Zₜ',17)
d.path('M260 220H410');d.circle(410,220,5,INK);d.text(410,175,'Filter terminal f',18);d.text(410,268,'U𝒇 ∠δ𝒇',20)
d.path('M410 220H605');d.rect(520,207,75,26,fill='white');d.text(558,160,'Phase reactor Zᵣ',17)
d.path('M595 220H730');d.circle(730,220,5,INK);d.text(730,175,'Internal terminal c',18);d.text(730,268,'U𝒄 ∠δ𝒄',20)
d.rect(820,175,130,100,fill='#e8f3ef');d.path('M820 275L950 175');d.text(849,208,'~',25);d.text(922,253,'=',25);d.path('M730 220H820M950 220H1060',color=GREEN);d.bus(1060,220,'DC d');d.text(1060,268,'V𝒅𝒄',20)
d.text(883,315,'Averaged VSC bridge\ncontrolled AC voltage\n+ scalar active loss',16)
d.path('M410 220V320M386 320H434M386 332H434M410 332V365M390 365H430M396 373H424M402 381H418');d.text(470,350,'Y𝒇 = G𝒇+jB𝒇\nB𝒇=0 in this project',16,'start')
d.path('M170 115H105',arrow=True);d.text(120,92,'Iₛ, Sₛ=Pₛ+jQₛ',17)
d.path('M685 115H610',arrow=True);d.text(648,92,'I𝒄, S𝒄=P𝒄+jQ𝒄',17)
d.path('M974 115H1050',arrow=True);d.text(1008,92,'I𝒅𝒄, P𝒅𝒄',17)
d.rect(30,430,325,128,fill='#f2f6fa',stroke=BLUE,dash='6 4');d.text(48,459,'PCC control port in Beerten',18,'start',weight='bold');d.text(48,489,'Pₛ* and Qₛ*: delivered to AC grid\nVAC_SET also measures this voltage\nPCC power = − transformer PF/QF',15,'start')
d.rect(385,430,335,128,fill='#f2f6fa',stroke=BLUE,dash='6 4');d.text(403,459,'Auxiliary computational buses',18,'start',weight='bold');d.text(403,489,'C1: 8 / 9; C2: 10 / 11; C3: 12 / 13\nThey expose physical terminal voltages.\nThey are not extra substations.',15,'start')
d.rect(750,430,360,128,fill='#f2f6fa',stroke=BLUE,dash='6 4');d.text(768,459,'Implemented power-control port',18,'start',weight='bold');d.text(768,489,'PAC_SET = P𝒄*; QAC_SET = Q𝒄*\nP𝒄 + P𝒅𝒄 + P_loss = 0\nProxy generator ≠ synchronous machine',15,'start')
d.write('station.svg')

d=Diagram(1110,300,'Steady-state voltage control to reactive-power limiting transition')
for x,title,body in [(20,'Solve full AC/DC equations','V/PV: enforce PCC voltage\nInternal Q is an unknown'),(385,'Check capability at solved point','Select a P/Q projection\nChange AC control mode if binding'),(750,'Re-solve and settle controls','Recheck converter and generator limits\nRecheck taps / shunts at full voltage')]:
    d.rect(x,65,335,126);d.text(x+167,94,title,17,weight='bold');d.text(x+167,132,body,15)
d.path('M355 128H383',arrow=True);d.path('M720 128H748',arrow=True);d.path('M917 192V226H185V194',arrow=True)
d.text(560,269,'Accept only a converged, settled point. Binding is a mode change; a failed re-correction is a separate outcome.',16)
d.write('control-cycle.svg')

# CSV containing the terminal-level numbers quoted in the report.
with (OUT/'station_results.csv').open('w',newline='',encoding='utf-8') as f:
    cols=['scenario']+list(E['rows'][0]['station'][0]);w=csv.DictWriter(f,fieldnames=cols);w.writeheader()
    for group in E['rows']:
        for row in group['station']:w.writerow({'scenario':group['name'],**row})

parts=[]
def add(s):parts.append(s)
def section(n,title):add(f'<section id="s{n}"><div class="eyebrow">{n:02d} / Engineering model</div><h2>{title}</h2>')
def end():add('</section>')
def p(s):add('<p>'+s+'</p>')
def note(kind,s):add(f'<aside class="{kind.lower()}"><strong>{kind}.</strong> {s}</aside>')

add('''<header><div class="eyebrow">Project model review · 14 September 2026</div><h1>What the VSC controls,<br>what the grid receives</h1><p class="lead">A terminal-by-terminal explanation of the Beerten AC/DC station, its implemented equations and the capability boundaries used by this project.</p><p>Scope: understanding and evaluation only. Production code, case matrices and historical outputs are preserved. Fresh MATLAB MCP power flows are distinguished from historical CPF evidence and from analytical capability constructions.</p><nav><a href="#s1">Network</a><a href="#s2">Station & ports</a><a href="#s3">Equations</a><a href="#s4">Numbers</a><a href="#s5">Capability</a><a href="#s6">Interactive trace</a><a href="#s7">Controls</a><a href="#s8">Assessment</a><a href="#s9">Evidence & sources</a></nav></header>''')
note('Finding','The full electrical model distinguishes the PCC, filter and internal converter terminal. Its <code>PAC_SET/QAC_SET</code> schedules and <code>PAC/QAC</code> results refer to the <b>internal</b> terminal. The capability layer combines those powers with <b>PCC voltage</b>. This is not the same current or voltage constraint as the full station model, nor the same control-port definition as Beerten’s PCC schedules.')

section(1,'Start with the actual network')
p('Three related configurations must be kept separate. “Beerten” is a family label here, not proof of identical numerical inputs. The fresh seven-bus base is electrically identical to the batch-6 base; the newer scenario changes the generator dispatch direction and G1 MBASE. '+cite('studies/beerten/beerten_constant_pq_nonslack_dispatch.m',1,39)+'.')
add(fig('singleline-project.svg','Figure 1. Complete project topology: seven original AC buses, nine original AC branches, two synchronous generators, three VSC stations and the three-branch DC triangle. The dashed station links are schematic; they are expanded in Figure 3. DC bus IDs are 2, 3 and 5. Loads are MW + j MVAr; displayed loads are at λ=0.'))
add(table(['Device','Control / schedule','What is solved'],[
['G1, AC bus 1','|V₁|=1.06 pu, angle reference 0°. New scenario MBASE=1000 MVA; original PMAX=500 MW.','P and Q balance the AC grid. It is not a VSC or a DC-voltage controller.'],
['G2, AC bus 6','PV, |V₆|=1.0 pu; P₂=40+240λ MW. MBASE=100 MVA.','Q₂ until capability binding; older batch 6 held P₂=40 MW.'],
['C1, PCC 2 → DC 2','AC_MODE=3 (PQ); DC_MODE=2. P𝒄*=−60 MW, Q𝒄*=−40 MVAr.','Vdc and Pdc follow station/DC balance. Stored PDC_SET=58.59 MW is not a second active schedule.'],
['C2, PCC 3 → DC 3','AC_MODE=2 (V); DC_MODE=1 (Vdc). |V₃|=1.0 pu and Vdc,3=1.0 pu.','P𝒄 and Q𝒄 are unknown. PAC_SET=20.68 and QAC_SET=7.17 are not enforced P/Q orders in this mode.'],
['C3, PCC 5 → DC 5','AC_MODE=3 (PQ); DC_MODE=2. P𝒄*=35 MW, Q𝒄*=5 MVAr.','Vdc and Pdc follow station/DC balance; stored PDC_SET=−36.21 MW is inactive as an order.'],
['ULTC 4–7 / shunt at 5','V7 and V5 regulation bands [0.95,1.03] pu. Shunt 0/5/10/15 MVAr at 1 pu.','Discrete state selected by existing control rules; physical saturation can leave unmet voltage regulation.']]))
p('The project’s seven original AC branches are 1–2, 1–3, 2–3, 2–4, 2–5, 3–4 and 4–5. It adds 6–2 and 4–7. Bus 4’s 40+j5 load is moved to bus 7, and G2 moves from bus 2 to bus 6. The station expansion adds six more AC buses and six station branches: 13 AC buses and 15 branches in the expanded solve. '+cite('cases/beerten/variants/case5_vsc_mtdc_beerten.m',44,113)+'; '+cite('matpower/lib/apply_vsc_ac_model.m',71,162)+'.')
add(eq(r'P_{L,5}=60+240\lambda,\quad Q_{L,5}=10+40\lambda'))
add(eq(r'P_{L,\Sigma}=165+240\lambda,\quad Q_{L,\Sigma}=40+40\lambda'))
add(fig('singleline-reference.svg','Figure 2. Reference topology: five AC buses and the same seven core AC connections, with G2 on bus 2 and the 40+j5 load on bus 4. The DC IDs 1/2/3 and resistances shown are the archived MatACDC 1.0 case; they map to PCCs 2/3/5. The 2010 paper uses the same PCC arrangement but does not give a complete reproducible impedance table.'))
add(table(['Quantity','2010 paper / archived MatACDC 1.0','Current project'],[
['Control-port definition','PCC Pₛ/Qₛ. Paper: C1 (−60,−40), C3 (35,5); C2 Vdc/Vac.','Internal P𝒄/Q𝒄 schedules with same nominal numbers.'],
['Station','2010: filter omitted, lumped series impedance. Archive: Zt=.0015+j.1121; Zr=.0001+j.16428; Bf=.0887 pu.','Zt=j.0001; Bf=0. Zr by row: .0009615+j.0399, j.0392, .000785+j.0399 pu.'],
['AC / DC bases','Archive 100 MVA, 345 kV AC and DC, pol=2.','100 MVA, 230 kV AC (G2 bus 13.8 kV), 300 kV DC; no pole-count parameter.'],
['DC resistances','Archive .052/.052/.073 pu per pole. A matched single-conductance model would use R/2 on the same power base.','2–3=.02633; 3–5=.02337; 2–5=.03601 pu. These are not an exact archive mapping.'],
['Limits','Archive Imax=1.2 pu, Uc∈[.9,1.1]; default enforcement OFF.','Fallback 150 MVA → 1.5 pu current, Uc,max=1.15, no lower-voltage field. These are project assumptions.']]))
p('Primary reference anchors: Beerten 2010, Fig. 9 and Table III; MatACDC manual §§4.1 and 6.1, pp. 14–20 and 29–32; the archive case and batch-6 report. The 2010 numerical provenance remains incomplete. This report does not tune the project to the printed paper values. <a href="#references">[R1–R4]</a> '+cite('outputs/beerten_validation_batch6_20260911/REPORT.md',31,98)+'.')
end()

section(2,'A physical station and its computational terminals')
p('At fundamental frequency the bridge is a controllable AC voltage source connected to a DC power port. A transformer adapts voltage and isolation; a phase reactor limits/smooths current and provides the series reactance through which the voltage source exchanges P and Q. A filter shunt represents fundamental-frequency admittance, not its harmonic spectrum. The model is balanced, positive-sequence and steady state: it does not simulate switching, PLL/current-loop dynamics, DC capacitor transients or MMC arm energy.')
add(fig('station.svg','Figure 3. Arrows define positive current and power directions: from converter toward the AC grid for I𝒄/Iₛ and S𝒄/Sₛ; from converter into the DC grid for Pdc. The physical equipment remains distinct from bus-number bookkeeping and proxy generators. The project has zero filter admittance, so its filter node is retained for topology rather than for an installed nonzero shunt.'))
p('The “transformer” in this particular fixture is a near-zero impedance placeholder: j0.0001 pu, unity ratio and zero phase shift, with almost all impedance assigned to the reactor. That is a modeling decomposition; its existence as a branch does not establish the real transformer’s leakage, loss or tap design. The added 6–2 transformer and automatic 4–7 ULTC are separate original-network devices. The VSC schema has TR_SHIFT but no adjustable station tap-ratio column. '+cite('matpower/lib/apply_vsc_ac_model.m',80,162)+'.')
add(table(['Symbol / field','Terminal and sign','Unit / base'],[
['U̲ₛ=Uₛeʲδₛ; VAC_PCC','PCC phasor; magnitude in result column 34. VAC_SET targets this terminal in V/PV modes.','Magnitude pu on the local AC voltage base; δ in degrees in bus results, radians in solver equations.'],
['U̲𝒇; VAC_FILTER','Transformer/reactor junction, with shunt Yf. Generated FILTER_BUS.','Pu; same voltage base copied from PCC in this implementation.'],
['U̲𝒄; VAC_INTERNAL','Controlled bridge-side AC voltage, after reactor. Generated INTERNAL_BUS.','Pu; not a DC voltage and not VAC_SET in V mode.'],
['I̲ₛ','Transformer series current directed f→s; for zero charging and unit tap it is the grid injection current.','AC pu; multiply by Sbase/(√3 Vbase,LL) to obtain kA.'],
['I̲𝒄; iac','Current directed c→f. calc_vsc_losses uses |S𝒄|/(Sbase U𝒄).','AC pu on 100 MVA system base. With nonzero reactor charging, bridge-terminal current and series current differ.'],
['I̲𝒇=Yf U̲𝒇','Shunt current f→ground (consumption convention).','Pu. Capacitive Bf&gt;0 consumes negative Q and supplies positive reactive power.'],
['Sₛ=Pₛ+jQₛ','Net station injection into AC grid at PCC, positive toward grid.','MW + j MVAr; sₛ=Sₛ/Sbase in equations. Not net bus injection after local load/G2.'],
['Sₛ𝒇=U̲𝒇 I̲ₛ* Sbase','Transformer input at filter side, directed toward grid.','MW + j MVAr; differs from Sₛ by transformer series loss/consumption.'],
['S𝒄𝒇=U̲𝒇 I̲𝒄* Sbase','Reactor output arriving at the filter node.','MW + j MVAr; S𝒄𝒇=Sₛ𝒇+Sfilter.'],
['S𝒄=P𝒄+jQ𝒄; PAC/QAC','Injection from bridge into its internal AC bus. Positive Q supplies vars to the station/grid.','MW / MVAr, result columns 30/31; fixed by PAC_SET/QAC_SET in PQ.'],
['Sfilter=Pfilter+jQfilter','Consumed shunt power: (Gf−jBf)|U𝒇|² Sbase.','MW + j MVAr. FILTER_G/FILTER_B themselves are pu.'],
['P_loss; PLOSS','Positive scalar bridge/interface active loss. Does not consume reactive power.','MW. Coefficients A [MW], B [MW/pu-current], C [MW/pu-current²].'],
['Vdc / VDC_SET','DC terminal voltage magnitude and reference, relative to the implicit return.','Pu on local 300 kV DC base. Pole/return interpretation is not specified by a separate parameter.'],
['Pdc / PDC_SET; Idc','Positive from converter into DC grid. Idc=Pdc/(Sbase Vdc).','MW; DC current pu on Sbase/Vdc,base. Not the same current base as AC.'],
['PF/QF, PT/QT','MATPOWER branch powers entering the branch at its from/to end. Station transformer is s→f and reactor f→c.','MW/MVAr. Thus Sₛ=−(PF+jQF) of transformer; S𝒄=PT+jQT of reactor.'],
['PFDC/PTDC; IFDC/ITDC','Powers/currents entering each DC line from its labeled end.','MW / DC pu; line loss PFDC+PTDC≥0.'],
['Snom; TR_RATE_A; REACTOR_RATE_A','Nameplate metadata if supplied; otherwise smallest positive station RATE_A supplies capability Snom.','MVA; a thermal MVA bound and a fixed current bound are different constraints.']]))
p('Definitions are grounded in '+cite('matpower/lib/idx_vsc.m',13,100)+', '+cite('matpower/lib/idx_branchdc.m',18,30)+' and '+cite('matpower/lib/calc_vsc_losses.m',29,41)+'. The generic phrase “injection into AC network” in idx_vsc is underspecified: the executable equations locate PAC/QAC at the internal bus. It must not be read as “PCC injection.”')
p('The 2010 converter table uses the opposite DC-power sign: its Pdc is positive from the DC network toward the converter/AC side. Therefore Pdc,project=−Pdc,paper. The same sign conversion is required for the archived MatACDC DC bus power column. AC Pₛ/Qₛ retain the injection-toward-grid convention; reversing only the DC sign preserves the bridge balance.')
add(eq(r'I_{b,ac}=\frac{S_b}{\sqrt{3}V_{b,LL}},\quad Z_{b,ac}=\frac{V_{b,LL}^2}{S_b},\quad I_{b,dc}=\frac{S_b}{V_{b,dc}}'))
p('For the project’s station base, Ibase,AC=0.251022 kA and Zbase,AC=529 Ω; DC Ibase=0.333333 kA and Zbase,DC=900 Ω. The implied 1.5 pu AC current rating is 0.376533 kA on the 230 kV side. At bus 6, the AC current base is 4.18370 kA and Zbase=1.9044 Ω. These are referred-base calculations, not a claim that a real bridge operates at 230 kV line-to-line. The archive AC base gives 0.167349 kA at 345 kV.')
note('Derivation','With a three-phase MVA base and line-to-line RMS voltage base, the √3 factor cancels in pu power: s=u i*. Do not introduce another √3 into calc_vsc_losses. The primary paper’s printed current equation retains a √3 under its stated convention; dimensional/base conversion must be made explicitly. The archived code’s kA conversion and the project’s pu-current polynomial must not be mixed.')
end()

section(3,'From circuit laws to the implemented residual')
p('Lowercase s and p below mean pu on Sbase=100 MVA. Under the case’s unit taps, zero branch charging and zero phase shifts, orient both series currents toward the AC grid. Let zt=Rt+jXt, zr=Rr+jXr, yf=Gf+jBf. Kirchhoff’s laws give:')
add(eq(r'\underline i_s=\frac{\underline u_f-\underline u_s}{z_t},\quad \underline i_c=\frac{\underline u_c-\underline u_f}{z_r},\quad \underline i_c=\underline i_s+y_f\underline u_f'))
add(eq(r's_s=\underline u_s\underline i_s^*,\quad s_{sf}=\underline u_f\underline i_s^*,\quad s_{cf}=\underline u_f\underline i_c^*,\quad s_c=\underline u_c\underline i_c^*'))
add(eq(r's_c-s_s=z_t|\underline i_s|^2+z_r|\underline i_c|^2+y_f^*|\underline u_f|^2'))
add(eq(r'P_c-P_s=S_b\left(R_t|i_s|^2+R_r|i_c|^2+G_fU_f^2\right)'))
add(eq(r'Q_c-Q_s=S_b\left(X_t|i_s|^2+X_r|i_c|^2-B_fU_f^2\right)'))
p('The last equation explains why Q𝒄 is generally not the reactive support seen by the grid. Inductors consume vars; a capacitive filter supplies vars. In the project Bf=0, so Iₛ=I𝒄 and Q𝒄−Qₛ=(Xt+Xr)I² Sbase. Transformer/reactor resistance accounts for their real loss in the AC network; the scalar converter-loss polynomial is a separate contribution. <a href="#references">[R1, Eqs. (1)–(6); R2, Eqs. (1)–(10); R3, Eqs. (1)–(11)]</a>')
p('For comparison with the traditional polar equations, omit the filter and combine z=zt+zr, y=1/z=g+jb, Δ=δ𝒄−δₛ. Here g and b are <b>admittance</b> components, despite occasional ambiguous impedance notation in source prose. Expanding u i* gives:')
add(eq(r'p_s=g(U_sU_c\cos\Delta-U_s^2)-bU_sU_c\sin\Delta'))
add(eq(r'q_s=bU_s^2-U_sU_c(g\sin\Delta+b\cos\Delta)'))
add(eq(r'p_c=gU_c^2-U_sU_c(g\cos\Delta+b\sin\Delta)'))
add(eq(r'q_c=-bU_c^2-U_sU_c(g\sin\Delta-b\cos\Delta)'))
p('With R=0, b=−1/X, pₛ=p𝒄=(UₛU𝒄/X)sinΔ, qₛ=(UₛU𝒄 cosΔ−Uₛ²)/X, and q𝒄=(U𝒄²−UₛU𝒄 cosΔ)/X. Both terminal powers are needed; treating q𝒄 as qₛ removes the reactor’s reactive consumption.')
add('<h3>The broader implemented branch model</h3>')
p('The actual Ybus construction supports π charging and complex taps. For a branch from a to b, y=1/z, total charging bc and tap τ=t exp(jφ), the terminal currents are:')
add(eq(r'i_a=\frac{y+jb_c/2}{|\tau|^2}u_a-\frac{y}{\tau^*}u_b,\quad i_b=-\frac{y}{\tau}u_a+(y+jb_c/2)u_b'))
add(eq(r'S_{ab}=S_bu_ai_a^*,\quad S_{ba}=S_bu_bi_b^*'))
p('These terminal equations, not the simplified series-current equations, are authoritative if TR_B, REACTOR_B or TR_SHIFT become nonzero. Positive reactor charging would make the bridge current include its local charging current. Filter G/B enters Ybus separately. '+cite('matpower/lib/makeYbus.m',50,79)+'; '+cite('matpower/lib/apply_vsc_ac_model.m',88,134)+'.')
add('<h3>Bridge loss and DC balance</h3>')
add(eq(r'I_c=\frac{\sqrt{P_c^2+Q_c^2}}{S_bU_c},\quad P_\ell=a+bI_c+cI_c^2,\quad P_c+P_{dc}+P_\ell=0'))
p('The repeated letter c in the coefficient is not the terminal index. All three local stations use a=1.1033 MW and b=0.1999949 MW/pu-current; quadratic coefficients are [0.1466667,0.2222333,0.2222333] MW/pu-current². A fixed LOSS_C is stored per row. The implementation does not switch between rectifier and inverter C coefficients when a row reverses flow, whereas the archive provides both. '+cite('matpower/lib/calc_vsc_losses.m',29,41)+'; '+cite('cases/beerten/variants/case5_vsc_mtdc_beerten.m',105,113)+'.')
add(eq(r'i_{mn}=\frac{v_m-v_n}{r_{mn}},\quad P_{mn}=S_bv_mi_{mn},\quad P_{mn}+P_{nm}=S_b\frac{(v_m-v_n)^2}{r_{mn}}'))
add(eq(r'\boldsymbol i_{dc}=G_{dc}\boldsymbol v_{dc},\quad P_{dc,m}=S_bv_m(G_{dc}\boldsymbol v_{dc})_m'))
add(eq(r'\sum_k P_{dc,k}=\sum_{(m,n)}P_{\ell,dc,mn},\quad \sum_k P_{c,k}=-\sum_kP_{\ell,k}-\sum_{(m,n)}P_{\ell,dc,mn}'))
p('DC has no reactive-power variable. The local representation is a single conductance matrix; the archive’s pole factor must be included when mapping its resistances. Kirchhoff consistency alone does not establish the physical pole/return interpretation. '+cite('matpower/lib/makeGdc.m',48,73)+'; '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',908,943)+'.')
add(eq(r'\sum P_G=\sum P_L+P_{\ell,AC}+\sum P_{\ell,station}+\sum P_\ell+P_{\ell,DC}'))
p('This total-system expression counts each resistance and shunt conductance once. The station term includes transformer/reactor/filter real consumption; it is not added again to the bridge balance P𝒄+Pdc+Pℓ=0. The grid is supplied by conventional generators; the three VSCs redistribute power and collectively consume real losses.')
add('<h3>Unified Newton equations and control ports</h3>')
p('The configured method is unified. After adding station buses, the solver removes temporary converter proxy generators from the equation-building case. It solves AC voltage angles/magnitudes, unknown converter active powers and non-reference DC voltages together, using an analytic Jacobian. A later reporting step can reintroduce proxy injections; those rows are not physical synchronous generators. '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',698,714)+'; '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',732,785)+'.')
add(eq(r's_i^{calc}=u_i(Y_{bus}\boldsymbol u)_i^*,\quad s_i^{spec}=s_i^{base}+\sum_{k:c(k)=i}(p_{c,k}+jq_{c,k})'))
p('Real nodal balance is imposed at non-reference AC buses; reactive balance is imposed where Q is specified. In V/PV converter mode, the internal reactive balance is replaced by the PCC-voltage equation, and Q𝒄 is recovered from the internal nodal power. Fixed-PAC modes are PQ and PV. Q/V modes instead solve P𝒄 from the DC-side requirement. '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',809,868)+'.')
add(eq(r'F_{V,k}=U_{s,k}-V_{AC,k}^*=0,\quad F_{bal,k}=\frac{P_{c,k}+P_{dc,k}+P_{\ell,k}}{S_b}=0'))
add(table(['AC mode','Active equation','Reactive / voltage equation'],[
['Q (1)','P𝒄 solved from Pdc/Vdc/droop and losses','Q𝒄=QAC_SET'],['V (2)','P𝒄 solved from Pdc/Vdc/droop and losses','Uₛ=VAC_SET; Q𝒄 solved'],['PQ (3)','P𝒄=PAC_SET','Q𝒄=QAC_SET'],['PV (4)','P𝒄=PAC_SET','Uₛ=VAC_SET; Q𝒄 solved']]))
p('For a fixed-PAC row, Pdc=−P𝒄−Pℓ takes precedence over PDC_SET. Otherwise DC_MODE=PDC fixes Pdc, DROOP gives Pdc=PDC_SET+KDROOP(Vdc−VDC_SET), and VDC fixes Vdc and obtains Pdc from DC nodal balance. KDROOP has units MW/pu, with the sign exactly as written; no droop deadband is represented by this local formula. The archive’s droop parameters should not be copied without checking definition and sign. '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',889,934)+'.')
p('The alternative sequential path adjusts an internal voltage target by the PCC voltage error. That outer-iteration heuristic is not the voltage equation used by this configured unified solve. '+cite('matpower/lib/update_vsc_state.m',85,101)+'.')
end()

section(4,'Actual numerical transfers between the terminals')
note('Verified','Fresh MCP power flows: seven-bus new-dispatch base success=1, maximum residual 2.61405×10⁻¹² pu; local five-bus case success=1, residual 3.71262×10⁻¹¹ pu. The maximum station power identity discrepancy across the quoted base/five-bus/historical-endpoint examples is 2.015×10⁻⁹ MVA. These checks validate electrical consistency, not every operational limit.')
add(table(['Fresh seven-bus base','P𝒄 / Q𝒄','Pₛ / Qₛ','Pdc','Bridge loss','Uₛ / U𝒄'],[[f"C{r['converter']} at PCC {r['pcc']}",f"{r['Pc']:.6f} / {r['Qc']:.6f}",f"{r['Ps']:.6f} / {r['Qs']:.6f}",f"{r['Pdc']:.6f}",f"{r['Ploss']:.6f}",f"{r['Us']:.6f} / {r['Uc']:.6f}"] for r in E['rows'][0]['station']]))
p('P values are MW, Q values MVAr and voltages pu. Notice that C2’s internal Q is only 1.519388 MVAr in the extended base, versus 7.461631 MVAr in the local five-bus solve. Moving G2, adding its transformer, moving the bus-4 load and enabling discrete controls changes the AC reactive balance; identical converter-mode labels do not imply identical Q outputs.')
add(table(['Fresh DC line','Sending-end power (MW)','Receiving-end power into line (MW)','Line loss (MW)'],[[f'{int(b[0])} → {int(b[1])}',f'{b[4]:.6f}',f'{b[5]:.6f}',f'{b[4]+b[5]:.6f}'] for b in E['fresh']['branchdc']]))
p('The three DC injections sum to +0.538513 MW, exactly the total resistive DC line loss to the reported precision. C1 supplies the DC grid; C2 and C3 draw from it. The internal AC injections sum to −4.222640 MW: 3.684127 MW of bridge loss plus 0.538513 MW of DC loss. Station series losses further reduce the total power seen at the PCCs. This is why the DC-voltage converter’s active injection is solved rather than scheduled independently.')
add('<h3>C1 rectifier: the grid supplies more than the internal schedule</h3>')
add(eq(r'P_s=-60.000000-0.051190=-60.051190\ \mathrm{MW}'))
add(eq(r'Q_s=-40.000000-0.005324-2.124261=-42.129585\ \mathrm{MVAr}'))
add(eq(r'P_{dc}=60.000000-1.327312=58.672688\ \mathrm{MW}'))
p('Thus 60.051190 MW is withdrawn at the PCC, 0.051190 MW is dissipated in the reactor, 1.327312 MW is lost in the bridge polynomial and 58.672688 MW enters the DC network. “−60 MW scheduled” means 60 MW absorbed at the internal terminal, not at the point of interconnection. Its 0.729655 pu actual current exceeds the mixed-port estimate 0.717275 pu by 1.70% of actual current because U𝒄&lt;Uₛ.')
add('<h3>C3 inverter: less P and Q arrive at the grid</h3>')
add(eq(r'36.202239=1.202239+0.009883+34.990117\ \mathrm{MW}'))
add(eq(r'Q_s=5.000000-(0.001259+0.502317)=4.496424\ \mathrm{MVAr}'))
p('The DC network supplies 36.202239 MW; the bridge injects 35 MW internally and 34.990117 MW reaches PCC 5. A hypothetical <em>PCC</em> order of +35 MW/+5 MVAr would require a different internal order determined with the station equations, not simply the existing PAC_SET/QAC_SET values. A one-time constant offset is insufficient because I², voltage and controls change with loading.')
add('<h3>The filter makes terminal distinctions larger in the author’s case</h3>')
add(table(['Archived MatACDC point','Pₛ / Qₛ','P𝒄 / Q𝒄','Iₛ / I𝒄 (pu)','U𝒄 (pu)'],[[f'C{k+1}',f"{A['Ps'][k]:.6f} / {A['Qs'][k]:.6f}",f"{A['Pc'][k]:.6f} / {A['Qc'][k]:.6f}",f"{A['Is'][k]:.6f} / {A['Ic'][k]:.6f}",f"{A['Uc'][k]:.6f}"] for k in range(3)]))
p(f"Archive C1: Q𝒄−Qₛ = {A['Qc'][0]-A['Qs'][0]:.6f} MVAr = transformer {A['Qtr'][0]:.6f} + reactor {A['Qr'][0]:.6f} + filter consumption {A['Qfilter_consumed'][0]:.6f}. Its filter supplies vars, so the bridge absorbs only 32.630664 MVAr even though the PCC absorbs 40 MVAr. Archive C3 supplies +5 MVAr at the PCC while the bridge Q𝒄 is −0.368935 MVAr. These signs are compatible with Kirchhoff’s laws.")
p('The archive values are from the saved unmodified author-solver result, whose reference agreement was checked in batch 6; this task reconstructs terminal quantities with MATLAB but does not rerun the author solver. Its C1 U𝒄=0.889865 pu is below the archived Uc,min=0.9 while author limits are disabled. Source: <a href="#references">[R2, §6.1]</a> and '+cite('outputs/beerten_validation_batch6_20260911/REPORT.md',84,119)+'.')
note('Inconsistency','In the current unified result builder, PTR_LOSS and PREACTOR_LOSS are initialized to zero and never populated. For fresh C1, PREACTOR_LOSS=0 in the result matrix although branch terminal powers and R I² give 0.051190 MW. The electrical equations include this loss; the reporting column does not. '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',1262,1322)+'.')
end()

section(5,'Capability: what is exact, and what is approximated')
p('A capability plot must name its coordinate terminal, voltage held fixed and hardware assumptions. The physical limits are on bridge/reactor current, synthesizable internal voltage, and equipment ratings. A circle in one terminal’s P/Q plane cannot be applied to a different terminal without transformation.')
add('<h3>Derive the filter-aware PCC boundaries</h3>')
p('Rotate the reference so uₛ=Uₛ is real; all power quantities remain unchanged. Define the three complex coefficients below. They are algebraic combinations, not extra equipment:')
add(eq(r'A=1+y_fz_t,\quad D=1+z_ry_f,\quad E=z_t+z_rA'))
add(eq(r'\underline i_c=A\frac{s_s^*}{U_s}+y_fU_s,\quad \underline u_c=DU_s+E\frac{s_s^*}{U_s}'))
p('The first relation follows by substituting u𝒇=uₛ+zt iₛ into i𝒄=iₛ+yf u𝒇. Substitution into u𝒄=u𝒇+zr i𝒄 gives the second. Taking magnitudes yields exact circles in <b>PCC-power coordinates</b> for a fixed PCC voltage and the stated no-charging/unit-tap circuit:')
add(eq(r'\left|s_s+\left(\frac{y_f}{A}\right)^*U_s^2\right|\leq\frac{U_sI_{c,max}}{|A|}'))
add(eq(r'\left|s_s+\left(\frac{D}{E}\right)^*U_s^2\right|\leq\frac{U_sU_{c,max}}{|E|}'))
add(eq(r'\left|s_s+\left(\frac{D}{E}\right)^*U_s^2\right|\geq\frac{U_sU_{c,min}}{|E|}\quad\mathrm{if\ a\ lower\ limit\ applies}'))
p('This is the same circuit result as Beerten’s π-equivalent derivation: E=Z₂ and D/E=Y₁+Y₂, so the voltage-circle center is −Uₛ²(Y₁+Y₂)* and radius UₛUc,lim|Y₂|. The current-circle center and radius match Eq. (15). This report re-derives the formulas and uses MATLAB to construct the plotted boundaries. <a href="#references">[R3, §II-B, Eqs. (12)–(24), Figs. 3–4]</a>.')
add(fig('reference_capability.svg','Figure 4. Archived MatACDC stations in PCC Pₛ/Qₛ coordinates, with their actual Imax=1.2 and Uc limits 0.9/1.1. Operating points come from the saved author solution. Current feasibility is inside the blue circle, maximum-voltage feasibility inside the upper-limit circle, and minimum-voltage feasibility outside the lower-limit circle. Filter omission changes current-circle center and radius. C1 violates the lower-voltage bound; the historical author PF had limits disabled.'))
add('<h3>Filter-free internal coordinates are different</h3>')
p('With yf=0, z=zt+zr=R+jX and Iₛ=I𝒄=I, s𝒄=sₛ+zI². On the current boundary I=Imax, this maps the PCC circle to an <b>internal</b> circle shifted by zImax²:')
add(eq(r'\left(p_c-RI_{max}^2\right)^2+\left(q_c-XI_{max}^2\right)^2=(U_sI_{max})^2'))
p('The implemented circle omits that shift. For C2, X=0.0393 and Imax=1.5, its exact internal current-boundary center is Q𝒄=8.8425 MVAr, not zero. This is reactive consumption at the boundary. At fixed PCC voltage, the disk traced by |I|≤Imax can be evaluated by mapping the current disk; the plotted curve is its boundary. For the present small station impedances and operating branch, the relevant region is the familiar interior bounded by this circle.')
add(eq(r'\left|s_c-U_{c,lim}^2y^*\right|=U_sU_{c,lim}|y|,\quad y=1/z'))
p('The internal-voltage boundary in internal P/Q coordinates has a positive-Q center for inductive z, unlike the negative-Q center of the PCC voltage circle. Its full circle also contains a remote electrical branch; select the normal high-voltage solution, rather than assuming an arbitrary circle interior corresponds to the wanted branch. For a purely inductive station, the near-axis upper-Q boundary is:')
add(eq(r'q_{c,Umax}=\frac{U_{c,max}^2}{X}-\sqrt{\left(\frac{U_sU_{c,max}}{X}\right)^2-p_c^2}'))
p('For a nonzero filter, reconstruct the full station for each candidate PCC power and map s𝒄=u𝒄 i𝒄*. A naive internal P/Q circle is no longer the general answer. Nonzero charging or complex station taps require the full two-port admittance equations derived above.')
add('<h3>The geometry actually enforced by this project</h3>')
p('The wrapper sets Snom from explicit metadata/options or the minimum positive transformer/reactor RATE_A. It converts powers to the <b>element</b> base Snom=150 MVA and sets xeq,element=|zt+zr| Snom/Sbase. Let p̂=P𝒄/Snom, q̂=Q𝒄/Snom and U=Uₛ. It enforces three inequalities:')
add(eq(r'|\hat p|\leq1,\quad \hat p^2+\hat q^2\leq U_s^2'))
add(eq(r'\hat p^2+\left(\hat q+\frac{U_s^2}{x_{eq,e}}\right)^2\leq\left(\frac{U_sU_{c,max}}{x_{eq,e}}\right)^2'))
p('In MW/MVAr this is |P𝒄|≤150 and √(P𝒄²+Q𝒄²)≤150Uₛ, plus a circle centered at Q=−Sbase Uₛ²/|zt+zr| with radius Sbase UₛUc,max/|zt+zr|. The quantity named <code>info.iMax</code> after scaling is a P/Q-circle radius in MVA, not an ampere or pu-current rating. The |P|≤Snom wall remains present even when Uₛ&gt;1 and the current circle is larger. '+cite('matpower/lib/vsc_capability_curve.m',54,67)+'; '+cite('matpower/lib/vsc_capability_curve.m',115,137)+'; '+cite('matpower/lib/vsc_capability_geometry.m',172,193)+'.')
add(table(['Exact mixing location','Power passed to geometry','Voltage passed to geometry'],[
['Audit: '+cite('matpower/lib/check_vsc_capability.m',45,54)+' and '+cite('matpower/lib/check_vsc_capability.m',116,127),'PAC/QAC, falling back to their SET columns','VAC_PCC preferred, then VAC_INTERNAL, then VAC_SET'],
['PF active set: '+cite('matpower/lib/enforce_vsc_capability_active_set.m',49,65)+' and '+cite('matpower/lib/enforce_vsc_capability_active_set.m',167,180),'Solved PAC/QAC','Same PCC-first fallback'],
['CPF active set: '+cite('matpower/lib/runcpf_vsc_mtdc.m',1425,1455)+' and '+cite('matpower/lib/runcpf_vsc_mtdc.m',1794,1805),'Solved PAC/QAC','VAC_PCC preferred'],
['Loss calculation: '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',838,852),'Internal PAC/QAC','VAC_INTERNAL: here the current is calculated at a consistent terminal']]))
p('There are therefore two different currents in play: the loss model uses I𝒄=|S𝒄|/(Sbase U𝒄), but the capability circle tests Ĩ=|S𝒄|/(Sbase Uₛ). Their ratio is exact for these field definitions:')
add(eq(r'\frac{\widetilde I}{I_c}=\frac{U_c}{U_s}'))
note('Approximation','The upper-voltage circle is the lossless, filter-free <em>PCC-power</em> equation with X replaced by |R+jX|, but the caller supplies <em>internal powers</em>. The scaling between 100 and 150 MVA is consistent; the control-port mixture is the main semantic inconsistency. Replacing X by |Z| also discards the resistance-dependent horizontal shift and rotation. It is not the exact resistive voltage circle.')
add(fig('project_base_capability.svg','Figure 5. Fresh base operating points in internal P𝒄/Q𝒄 coordinates. Dashed orange: implemented current surrogate; blue: full-station reactor-current boundary. Dotted vertical walls: implemented |P𝒄|≤150 MW. All three base points are well inside. Upper-voltage boundaries lie above this plotting window; their omission from this panel does not mean the check is absent.'))
add(fig('project_endpoint_capability.svg','Figure 6. Same comparison at the historical batch-6 endpoint, λ=1.138532043940. Each station uses its own solved PCC voltage. C2 nearly touches the surrogate while retaining real current headroom. C3’s small radius reflects its low PCC voltage. This is a historical fixed-G2 scenario, not the newer dispatch direction.'))
add(fig('voltage_boundary.svg','Figure 7. Isolated voltage-limit comparison for C2 at the historical endpoint’s fixed PCC voltage. Left: upper-voltage arc expressed in internal P/Q coordinates. Right: exact high-voltage station solution versus voltage inferred by the mixed-port circle at P𝒄=19.996 MW. Most of this extension beyond the operating point is already current-infeasible; it isolates the voltage-geometry error, not additional usable capacity.'))
p('The exact filter-free internal-voltage reconstruction in the right panel follows by writing uₛ=u𝒄−z s𝒄*/u𝒄*. If w=U𝒄², then:')
add(eq(r'w^2-\left[U_s^2+2(Rp_c+Xq_c)\right]w+|z|^2(p_c^2+q_c^2)=0'))
p('The larger positive root is used here, continuously connected to the normal base branch. A negative discriminant means the proposed internal schedule has no solution in this fixed-PCC series-station model; it is not a reason to clip the square root and declare feasibility. Plot evaluation stays on the valid discriminant range.')
add(table(['Historical C2 endpoint','Value','Interpretation'],[
['P𝒄 / Q𝒄','19.996071 MW / 140.092692 MVAr','Internal operating point'],['Pₛ / Qₛ','19.996071 MW / 132.199268 MVAr','Delivered PCC support'],['Uₛ / U𝒄','0.943419157 / 0.998524134 pu','PCC and internal voltages differ'],['Actual I𝒄','1.417217239 pu = 0.355753 kA','94.481149% of implied 1.5 pu rating'],['Surrogate Ĩ','1.499996694 pu','99.999780% of implied rating'],['Reactive consumption','7.893423482 MVAr','0.020085 transformer + 7.873338 reactor'],['Voltage inferred by surrogate','1.001812182 pu','Actual U𝒄 is 0.998524134 pu; both below 1.15'],['Current headroom','5.518851% of implied rating','A terminal-definition difference, not a validated extra system margin']]))
p('Approximation errors matter most near a binding surface, at depressed PCC voltage, during large reactive exchange, with appreciable series impedance, or when a nonzero filter separates bridge current from transformer current. C1 demonstrates that the surrogate can underestimate current; C2 demonstrates that it can overestimate it. It is not uniformly conservative. Far inside all limits, a small geometric difference may not change the active set. Close to a transition, it can change Q support, tap/shunt states, CPF trajectory and apparent limiting loading. No new system margin has been calculated from the corrected boundaries.')
end()

section(6,'Explore the accepted historical operating points')
p('Select a station and move through the saved batch-6 samples. Each sample updates the internal-power current boundaries using that sample’s actual PCC voltage. Both the power coordinates and current ratios are shown. This is an inspection of accepted historical states; it does not interpolate a new power-flow solution or alter any case.')
add('''<div class="explorer"><div class="controls"><label>Converter <select id="conv"><option value="0">C1 · PCC 2</option><option value="1" selected>C2 · PCC 3 · DC voltage control</option><option value="2">C3 · PCC 5</option></select></label><label>Accepted sample <input id="sample" type="range" min="0" max="25" value="25" step="1"><output id="sample-label"></output></label></div><canvas id="capcanvas" role="img" aria-label="Internal-power current capability comparison for selected historical sample"></canvas><p id="sample-values" aria-live="polite"></p><p class="small">Blue solid: exact reactor-current boundary. Orange dashed: implemented current circle. Black point: solved internal P/Q. Gray dotted: |P|≤150 MW. Capability region here concerns current and active-power walls only; voltage limits are analyzed in Figure 7.</p></div>''')
add(fig('history_trace.svg','Figure 8. C2 along the historical accepted trace. The dotted vertical line marks the accepted V→Q conversion sample (λ≈1.104505), not an exactly localized continuous crossing. The port difference grows with current. The curve is historical evidence and has not been rerun in this task.'))
end()

section(7,'Control priorities, limit transitions and the two slacks')
p('Independent P and Q control means two local control degrees of freedom before a limit binds. It does not mean unlimited simultaneous active transfer and reactive support. With inductive coupling, changing the converter angle primarily changes P, while changing its voltage magnitude primarily changes Q; resistance, large angles and grid interactions couple them.')
add(eq(r'p_s=\frac{U_sU_c}{X}\sin\Delta,\quad q_s=\frac{U_sU_c\cos\Delta-U_s^2}{X}'))
add(eq(r'\frac{\partial p_s}{\partial\Delta}=\frac{U_sU_c}{X}\cos\Delta,\quad \frac{\partial q_s}{\partial U_c}=\frac{U_s}{X}\cos\Delta'))
p('These sensitivities are circuit derivations, not the implemented dynamics of a controller. Voltage-source magnitude and angle are algebraic unknowns in this project. A plausible steady-state priority policy must still specify what is sacrificed when the current or voltage envelope is reached.')
add(table(['Policy','What it preserves','Actual project use and consequence'],[
['Active-power priority: preservar_p','P remains unchanged if any feasible Q interval exists; clip Q to the intersection of the two circles. If no interval exists, reduce |P| to the feasible maximum.','Default for DC-voltage and droop rows. It is a local projection, not a guarantee that the subsequent network solution keeps the same P.'],
['Radial projection','Scales P and Q by the same α; preserves internal power factor.','Default for fixed-PDC rows, including C1/C3’s metadata. It sacrifices active transfer and vars together, not “Q priority.”'],
['Reactive-support priority','Would preserve Q or the AC voltage objective while curtailing P to create current room.','No general Q-preserving projection mode is implemented. Requires an explicit new study policy and DC/AC balancing design.'],
['MatACDC reference policy','Prioritizes PCC active power over reactive power for controlled non-DC-slack stations.','Author manual excludes DC-slack converters from iterative limit enforcement and checks them at the end. Project C2 is included in its VSC capability loop.']]))
p(cite('matpower/lib/vsc_capability_policy.m',44,86)+'; '+cite('matpower/lib/vsc_capability_geometry.m',225,275)+'; <a href="#references">[R2, §4.1.4, pp. 19–20]</a>.')
p('For the implemented preserve-P projection, let rI=U Snom, a=Sbase U²/xeq,system and rV=Sbase U Umax/xeq,system. At a feasible fixed P, the remaining reactive interval is:')
add(eq(r'Q_{min}=\max\left[-\sqrt{r_I^2-P^2},-a-\sqrt{r_V^2-P^2}\right]'))
add(eq(r'Q_{max}=\min\left[\sqrt{r_I^2-P^2},-a+\sqrt{r_V^2-P^2}\right]'))
p('This interval only applies when the square roots are real and Qmin≤Qmax. Radial projection instead selects the largest feasible α∈[0,1] on (P,Q)=α(P₀,Q₀), also respecting |P|≤Snom. A setpoint projection is followed by a fresh electrical solve because voltage and current capacity change with the operating point.')
add(fig('control-cycle.svg','Figure 9. Solve, project, change the algebraic active set, and fully re-correct. Capability changes must be followed by any newly required tap/shunt settlement; electrical convergence and settled control state are separate acceptance requirements.'))
add(table(['Transition','Equations before → after','Meaning'],[
['Converter PV→PQ','P𝒄 fixed and Uₛ fixed → P𝒄 fixed and Q𝒄 fixed','The PCC voltage is released and becomes a result.'],
['Converter V→Q','DC balance determines P𝒄 and Uₛ fixed → DC balance determines P𝒄 and Q𝒄 fixed','C2 retains its DC-voltage role. Stored PAC_SET can be updated but is not an enforced order in Q mode.'],
['Projection changes P','Active-set target becomes PQ in the generic policy','For a sole DC-voltage controller this can conflict with retaining Vdc as a reference: an extra P𝒄 constraint may be infeasible. This branch is not validated by the historical C2 Q-only binding.'],
['Generator PV→PQ','P and voltage specified, Q solved → P and limited Q specified, voltage solved','Applies to G2’s AC machine. It is separate from a converter AC-mode code.']]))
p('The policy chooses Q/PQ based on whether P changed. Both PF and CPF write AC_MODE/PAC_SET/QAC_SET and re-solve; they do not simply cap a plotted result. There is no general automatic capability release from Q/PQ back to V/PV certified in the saved study. '+cite('matpower/lib/enforce_vsc_capability_active_set.m',72,87)+'; '+cite('matpower/lib/vsc_capability_policy.m',64,76)+'; '+cite('matpower/lib/runcpf_vsc_mtdc.m',1466,1490)+'.')
p('The public PF validator explicitly rejects VSC_DC_VDC combined with fixed-PAC modes PQ/PV: '+cite('matpower/lib/runpf_vsc_mtdc.m',239,254)+'. Thus a projection that must change P on the sole DC reference cannot be treated as an ordinary supported PQ transition. Preserve the DC reference and handle infeasible active balance explicitly. The lower-level unified residual assumes valid mode combinations; active-set handoffs should preserve that invariant. This is a code-based edge-case recommendation, not a newly executed failure test.')
add('<h3>DC reference C2 is not AC slack G1</h3>')
p('C2 fixes the DC voltage at bus 3 and absorbs the residual DC power imbalance after C1, C3, DC losses and converter losses are accounted for. Its P𝒄 is therefore an unknown even when its AC reactive support is saturated. G1 fixes AC angle and magnitude and balances the overall AC active/reactive mismatch. Vdc control is a DC power-balancing role, not an AC angle reference. Multiple VSC DC reference rows at one DC bus would split the residual equally in the current code; that is a computational rule, not a validated sharing controller. '+cite('matpower/lib/runpf_vsc_mtdc_unified.m',918,934)+'.')
p('In historical batch 6, G2 changed PV→PQ at the accepted sample λ=1.079419752. C2 changed V→Q at λ=1.104504838, and continuation proceeded after both. The subsequent stop at λ=1.138532043940 was a converter-capability <em>electrical re-correction failure</em>. The reported success=true has scope configured_stop_policy; requested NOSE was not reached and nose_detected=false. An independent historical augmented-equation fold at λ≈1.138532854472 belongs to the binding-surrogate model and fixed final controls, not a manufacturer-qualified station margin. '+cite('outputs/beerten_validation_batch6_20260911/REPORT.md',211,286)+'.')
p('Historical equipment feasibility is a separate failure: with the old G1 MBASE=100 MVA, applying the same generic 80 MW curve ceiling to G1 would already reject its base output 133.592923 MW. The implementation exempts G1. At the old endpoint, G1 also reaches 505.506338 MW, exceeding its explicit 500 MW PMAX, and original branches 1–2 and 2–5 exceed their 250 MVA ratings. The new G1 MBASE=1000 scenario changes that fallback-base interpretation but retains the exemption and explicit PMAX. Neither scenario thereby gains an all-equipment feasibility certificate. '+cite('outputs/beerten_validation_batch6_20260911/REPORT.md',173,202)+'.')
add('<h3>Physical tap/shunt saturation has a different contract</h3>')
p('Under <code>psse_control_limit="saturate"</code>, an electrically converged point can be accepted outside its regulation band only when a fresh control pass shows each remaining eligible violation requests outward motion at a physical bound. An available legal move requires another full electrical correction. Cycling, unresolved requests and failed corrections are not physical saturation. The next point re-evaluates the original control rule, so a reverse request can move the controller away from the bound. This reversibility is distinct from the converter capability mode-release policy. '+cite('docs/CONTROL_SATURATION_CONTRACT.md',1,28)+'; '+cite('docs/CONTROL_SATURATION_CONTRACT.md',37,69)+'.')
add('<h3>Implications of the newer non-slack dispatch</h3>')
add(eq(r'P_{G2}=40+240\lambda,\quad P_{G2,curve,max}=0.8(100)=80\ \mathrm{MW},\quad \lambda_P=\frac{80-40}{240}=\frac16'))
p('The schedule reaches the generic thermal curve’s active ceiling at λ=0.166667; Q capability may become relevant before that. The original PMAX=300 MW corresponds to λ=1.083333, but the generic 80 MW assumption is much more restrictive. MBASE=1000 for G1 neither raises its explicit PMAX=500 MW nor removes the generic slack exemption. MBASE itself is a per-unit base, not evidence of a manufacturer capability rating. '+cite('matpower/lib/gen_capability_curve.m',224,231)+'; '+cite('studies/beerten/beerten_constant_pq_nonslack_dispatch.m',20,39)+'.')
p('A relevant code caveat: CPF’s generic generator limiter can write projected PG to <em>both base and target</em>, and can set QG/QMAX/QMIN to the clamped Q. Thus beyond a generator active limit, the solver’s implemented projection may alter the declared dispatch direction and leave AC slack to balance the difference. The scenario constructor itself does not supply a dispatch-at-limit policy. The existing λ=0.05 smoke test (G2=52 MW) does not validate this later behavior. A bounded follow-up should check schedule preservation and terminal reason around the first limit before any new margin claim. '+cite('matpower/lib/runcpf_vsc_mtdc.m',2193,2240)+'.')
end()

section(8,'Engineering assessment and bounded recommendations')
add(table(['Classification','Assessment','Bounded next change to review'],[
['Acceptable simplification','Balanced, fundamental-frequency steady-state VSC voltage source plus explicit station impedance is appropriate for PF/CPF equilibrium studies.','Keep dynamic/harmonic/energy claims outside scope; no need to build switching models for this task.'],
['Acceptable with declared scope','Filter-free series approximation can represent an intentionally simplified or suitable MMC-style station. Tiny transformer reactance keeps topology nonsingular.','Document that j0.0001 is a computational split; validate real transformer/reactor values before claiming hardware agreement.'],
['Acceptable with calibrated data','Quadratic current loss is a standard aggregate PF model.','Specify bridge-versus-station scope and current base. Confirm coefficients and decide whether direction-dependent C is needed. Avoid double counting station copper losses.'],
['Definition inconsistency','PAC/QAC mean internal injection in code, but comments and nominal reference schedules can be read as PCC powers.','First add explicit output aliases Pc/Qc and Ps/Qs, document existing semantics, and add a declared control_port option only in a separately approved change. Preserve the legacy default for replay.'],
['Constraint inconsistency','Internal powers are tested with PCC voltage against a PCC-form circle.','Add a read-only full-station audit from branch terminal currents and Uc first. Then implement a separate opt-in, consistently referenced capability model using exact station equations or PCC circles with the full mapping.'],
['Reporting defect','Unified PTR_LOSS/PREACTOR_LOSS are zero placeholders despite nonzero branch dissipation.','Populate them from both-end branch powers; add a targeted terminal-balance/reporting check. Do not alter solved equations.'],
['Approximation needing metadata','150 MVA station RATE_A is converted into a nominal current limit; Uc,max=1.15 is a fallback. No modulation/Vdc coupling or lower-voltage field.','Separate Imax, station terminal MVA ratings, converter Snom, and Uc limits. If technology requires modulation bounds, express them with Vdc and the chosen topology/base. Do not borrow archive limits as project ratings.'],
['Control policy decision','Radial PF preservation differs from active priority; no general Q-priority or restore-to-V rule.','Expose and test a small set of documented priority/release policies. For the sole DC reference, release AC support first; if active balance becomes infeasible, stop explicitly or use a predeclared redistribution plan.'],
['Scope gap','Generic converter checks do not certify transformer/reactor both-end MVA, AC line ratings, all generator P/Q boxes, DC ratings or global voltage bounds.','Audit each equipment class separately before expanding enforcement. Report configured success, electrical convergence and equipment feasibility as distinct outcomes.'],
['Scenario limitation','New P₂ schedule soon reaches a generic curve built from MBASE; generic G1 exemption persists.','Obtain or declare actual generator ratings/curves. Test λ around 1/6 with dispatch-accounting assertions; do not silently clip or transfer the schedule and call it unchanged.']]))
note('Recommendation','A low-risk sequence is: (1) clarify terminal names and repair loss reporting; (2) add exact read-only equipment audits alongside the legacy geometry; (3) introduce an opt-in control-port and capability formulation with regression comparisons; (4) decide priority, DC-reference infeasibility and release rules; (5) recompute study results only after those choices are explicit. No item in this sequence has been implemented here.')
p('The correct conclusion from the current evidence is narrower than “the converter model is wrong.” The solved station circuit and bridge/DC power balance are consistent. The mismatch lies in how powers are named/compared with PCC schedules and how capability geometry is attached to those powers. That is enough to change limiting-mode behavior and makes the historical CPF endpoint unsuitable as a general physical capability margin.')
end()

section(9,'Evidence, reproducibility and primary sources')
p('Fresh numerical work used MATLAB MCP after iniciar_proyecto, with the configured solver options, no restoredefaultpath, no CLI fallback and no solver-tolerance change. New scripts and artifacts live only under this output directory. The historical trace was read from final_04/capability_step_100.json; its 26 accepted samples were re-evaluated for station currents and capability-port comparisons without rerunning continuation. The stored author result was used for the separate archive example.')
p('The first two exporter attempts produced “Subscripted assignment between dissimilar structures” in this task’s new station_rows packaging helper. The final exporter completed and its PF and station-balance assertions passed. That error was a task-script failure, not a MATLAB MCP startup or electrical solver failure. PDF rendering emitted missing display-font warnings for the primary papers; the relevant rendered source pages were visually inspected. The final report’s own equations use embedded vector glyphs and require no web fonts or external equation renderer.')
add(table(['File','Purpose'],[
['<a href="evidence.mat">evidence.mat</a> / <a href="evidence.json">evidence.json</a>','Fresh results, exact station calculations, boundary samples, historical extracted trace, base/target/options.'],
['<a href="station_results.csv">station_results.csv</a>','Terminal quantities for every quoted local base/five-bus/endpoint example.'],
['<a href="reference_station.json">reference_station.json</a>','Archive station reconstruction using stored author-solver voltages/powers.'],
['<a href="calculate_evidence.m">calculate_evidence.m</a>','MATLAB station checks and capability-boundary construction. Initialize from project root; all writes stay here.'],
['<a href="build_report.py">build_report.py</a>','Plots, original diagrams, rendered equations and standalone report builder; run with project .venv.'],
['<a href="verification/verification.json">verification/verification.json</a>','Numerical, browser-render and preservation check results.'],
['<a href="source_manifest.json">source_manifest.json</a>','SHA-256 hashes of cited project files and numerical evidence used in this report.']]))
add('<h3 id="references">Primary references</h3><ol class="refs">')
add('<li><b>R1.</b> J. Beerten, S. Cole and R. Belmans, <i>A Sequential AC/DC Power Flow Algorithm for Networks Containing Multi-terminal VSC HVDC Systems</i>, IEEE PES GM, 2010. <a href="https://doi.org/10.1109/PES.2010.5589968">DOI</a>. Local supplied PDF in Referencias. Inspected Eqs. (1)–(6), DC balance and slack iteration, Figs. 1–2 and 9, Table III. Filter-free model; controlled P/Q at system bus. The reported 2010 outputs are not a full numerical input specification.</li>')
add('<li><b>R2.</b> Jef Beerten, <i>MatACDC 1.0 User’s Manual</i>, July 4, 2012. <a href="https://www.esat.kuleuven.be/electa/teaching/matacdc/MatACDCManual">Author manual link</a>; archived copy at outputs/beerten_validation_batch6_20260911/reference/MatACDC1.0/MatACDC_UserManual.pdf. §§4.1.1–4.1.4, pp. 14–20; §6.1, pp. 29–32. Provides explicit station, controls, limits and archived example.</li>')
add('<li><b>R3.</b> J. Beerten, S. Cole and R. Belmans, <i>Generalized Steady-State VSC MTDC Model for Sequential AC/DC Power Flow Algorithms</i>, IEEE Transactions on Power Systems 27(2), 821–829, May 2012. <a href="https://doi.org/10.1109/TPWRS.2011.2177867">DOI</a>; <a href="https://lirias.kuleuven.be/retrieve/246525">author-hosted accepted manuscript</a>; <a href="references/beerten_2012.pdf">local retrieved copy</a>. §II-B, Eqs. (12)–(24), Figs. 3–4: exact filter-aware capability derivation. §II-C, Eqs. (25)–(30): DC pole-factor conventions. The manuscript’s printed pages 3–4 are PDF pages 4–5.</li>')
add('<li><b>R4.</b> <a href="https://www.esat.kuleuven.be/electa/teaching/matacdc">Author’s MatACDC distribution</a>, archived unmodified MatACDC 1.0 source: case5_stagg, case5_stagg_MTDCslack and convlim.m. In convlim.m, lines 73–139 define the π-equivalent and PCC capability-circle parameters. Stored author output: outputs/beerten_validation_batch6_20260911/author_reference.json. The author code is inspected locally and is not redistributed with this explanation.</li></ol>')
p('The first 2012 manuscript URL returned HTTP 404; the author repository’s retrieve/246525 link succeeded. No secondary source is used to establish the electrical equations. New figures are original schematics and calculated plots, not reproductions of copyrighted paper figures. Reference limits and reference numerical examples are kept distinct from the local project.')
add('<h3>Exact project code locations</h3><p>Each citation below preserves a line-numbered excerpt of the current implementation for offline review. These are evidence excerpts, not modified production files.</p>')
# Add details for each cited interval; do not copy complete author code.
for path,ranges in SOURCES.items():
    key=re.sub(r'\W','_',path);lines=(ROOT/path).read_text(encoding='utf-8-sig').splitlines()
    add(f'<details id="source-{key}"><summary>{html.escape(path)}</summary>')
    for start,stop in sorted(set(ranges)):
        add(f'<div id="src-{key}-{start}" class="source"><p>Lines {start}–{stop}</p><pre>')
        add('\n'.join(f'{i:4d}  {html.escape(lines[i-1])}' for i in range(start,min(stop,len(lines))+1)))
        add('</pre></div>')
    add('</details>')
end()
add('<footer>Prepared for model understanding and evaluation. No production implementation or case parameter changes. Report version: 2026-09-14.</footer>')

script=r'''
const trace=TRACE;
const sel=document.getElementById('conv'), slider=document.getElementById('sample'), canvas=document.getElementById('capcanvas');
function draw(){
 const k=+sel.value,n=+slider.value,p=trace[n],r=p.station[k],u=r.Us;
 const w=canvas.clientWidth,h=Math.min(490,Math.max(300,w*.55));canvas.style.height=h+'px';
 const dpr=window.devicePixelRatio||1;canvas.width=w*dpr;canvas.height=h*dpr;const c=canvas.getContext('2d');c.scale(dpr,dpr);
 const left=58,right=20,top=30,bottom=48,scale=Math.min((w-left-right)/380,(h-top-bottom)/380),cw=scale*380,cx=left+(w-left-right)/2,cy=top+(h-top-bottom)/2;
 const x=v=>cx+v*scale,y=v=>cy-v*scale;
 c.fillStyle='#fff';c.fillRect(0,0,w,h);c.font='13px Arial';c.textAlign='center';c.fillStyle='#182f40';
 for(let t=-150;t<=150;t+=50){c.strokeStyle='#e3e9ed';c.setLineDash([]);c.lineWidth=1;c.beginPath();c.moveTo(x(t),y(-180));c.lineTo(x(t),y(180));c.moveTo(x(-180),y(t));c.lineTo(x(180),y(t));c.stroke();c.fillText(t,x(t),y(-180)+19);c.textAlign='right';c.fillText(t,x(-180)-8,y(t)+4);c.textAlign='center';}
 function curve(color,dash,centerP,centerQ,radius){c.strokeStyle=color;c.setLineDash(dash);c.lineWidth=2.3;c.beginPath();for(let a=0;a<=2*Math.PI+.02;a+=.015){let xx=x(centerP+radius*Math.cos(a)),yy=y(centerQ+radius*Math.sin(a));a===0?c.moveTo(xx,yy):c.lineTo(xx,yy);}c.stroke();}
 const R=[.0009615,0,.000785][k],X=[.04,.0393,.04][k];
 curve('#176a98',[],100*R*2.25,100*X*2.25,150*u);curve('#c45636',[7,5],0,0,150*u);
 c.strokeStyle='#89969d';c.setLineDash([2,4]);for(const t of [-150,150]){c.beginPath();c.moveTo(x(t),y(-180));c.lineTo(x(t),y(180));c.stroke();}
 c.setLineDash([]);c.fillStyle='#182f40';c.beginPath();c.arc(x(r.Pc),y(r.Qc),5,0,2*Math.PI);c.fill();
 c.fillText('Pc (MW)',cx,h-4);c.save();c.translate(15,cy);c.rotate(-Math.PI/2);c.fillText('Qc (MVAr)',0,0);c.restore();
 c.fillText(`C${k+1} · Us=${u.toFixed(6)} pu · ${r.mode===2?'AC V mode':'AC Q/PQ mode'}`,cx,18);
 document.getElementById('sample-label').textContent=`${n+1} of ${trace.length} · λ=${p.lambda.toFixed(9)}`;
 document.getElementById('sample-values').innerHTML=`<b>Internal:</b> ${r.Pc.toFixed(3)} MW / ${r.Qc.toFixed(3)} MVAr. <b>PCC:</b> ${r.Ps.toFixed(3)} MW / ${r.Qs.toFixed(3)} MVAr.<br><b>Actual current:</b> ${r.Ic.toFixed(6)} pu (${(100*r.I_ratio).toFixed(3)}%). <b>Surrogate:</b> ${r.I_surrogate.toFixed(6)} pu (${(100*r.I_surrogate_ratio).toFixed(3)}%). <b>Internal voltage:</b> ${r.Uc.toFixed(6)} pu.`;
}
sel.addEventListener('change',draw);slider.addEventListener('input',draw);new ResizeObserver(draw).observe(canvas);draw();
'''.replace('TRACE',json.dumps(E['trace'],separators=(',',':')))
css='''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#fff;color:#182f40;font-family:Segoe UI,Arial,sans-serif;font-size:17px;line-height:1.67}main{max-width:1160px;margin:auto;padding:54px 44px}header{padding-bottom:32px;border-bottom:3px solid #176a98}.eyebrow{text-transform:uppercase;letter-spacing:.15em;color:#526c7c;font-size:12px;font-weight:700}h1{font-size:58px;line-height:1.09;letter-spacing:-.035em;margin:20px 0 26px}h2{font-size:34px;line-height:1.2;margin:10px 0 24px;letter-spacing:-.025em}h3{font-size:23px;margin:32px 0 12px}p{margin:15px 0}.lead{font-size:24px;line-height:1.45;max-width:960px}a{color:#11628c;text-decoration-thickness:1px;text-underline-offset:3px}nav{display:flex;flex-wrap:wrap;gap:10px 22px;margin-top:25px}section{padding:48px 0 25px;border-bottom:1px solid #d6e0e6}aside{margin:25px 0;padding:20px 24px;background:#edf5f7;border-left:4px solid #176a98}aside.inconsistency{border-color:#c45636;background:#fff4ef}aside.recommendation{border-color:#267b62;background:#edf7f2}figure{margin:30px 0 24px}figure>svg,figure>img{width:100%;height:auto;display:block}figcaption{font-size:14px;line-height:1.5;color:#496270;margin-top:12px}table{border-collapse:collapse;width:100%;font-size:15px;line-height:1.55}th{text-align:left;background:#edf3f6;color:#153448}td,th{padding:12px 14px;border-bottom:1px solid #d8e1e6;vertical-align:top}tr:nth-child(even) td{background:#f8fafb}.tablewrap{overflow-x:auto;margin:24px 0}code{background:#edf1f4;padding:1px 4px;font-size:.92em}.cite{font-size:13px;overflow-wrap:anywhere}.equation{display:flex;align-items:center;justify-content:center;gap:16px;padding:15px 14px;margin:18px 0;background:#f8fafb;overflow-x:auto}.equation svg{max-width:calc(100% - 44px);height:auto;flex-shrink:1;min-width:0}.eqno{margin-left:auto;font-size:13px;color:#657a88}details{margin:14px 0;border-bottom:1px solid #d8e1e6;padding:8px 0}summary{font-size:14px;font-weight:600;cursor:pointer;overflow-wrap:anywhere}pre{font:12px/1.5 Consolas,monospace;white-space:pre;overflow:auto;background:#f7f9fa;padding:14px}.source{scroll-margin-top:20px}.source p{font-size:13px}.refs li{margin:18px 0}footer{font-size:13px;color:#617581;padding:30px 0}.controls{display:flex;gap:30px;flex-wrap:wrap;align-items:center;margin-bottom:18px}.controls label{display:flex;flex-direction:column;gap:8px;font-size:14px;flex:1;min-width:220px}select{font:16px Segoe UI;padding:9px;border:1px solid #9bafb9;background:white;color:#182f40}input{width:100%}output{font-variant-numeric:tabular-nums}canvas{width:100%;display:block}.small{font-size:14px}.explorer{border-top:2px solid #176a98;padding-top:22px}@media(max-width:700px){main{padding:25px 16px}h1{font-size:40px}h2{font-size:28px}.lead{font-size:20px}body{font-size:16px}td,th{padding:8px;min-width:110px}figure{overflow-x:auto}figure>svg{min-width:690px}.equation{padding:12px 4px}.equation svg{min-width:400px;max-width:none}.controls{gap:12px}}@media print{main{padding:0;max-width:none}body{font-size:11pt}h1{font-size:32pt}h2{font-size:22pt}nav,.explorer,details{display:none}figure,table,.equation{break-inside:avoid}section{break-before:page}a{color:inherit}figure>svg{min-width:0!important}}'''
css+='body{overflow-wrap:anywhere}'
doc='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>VSC station, control ports and capability — project explanation</title><style>'+css+'</style></head><body><main>'+''.join(parts)+'</main><script>'+script+'</script></body></html>'
(OUT/'REPORT.html').write_text(doc,encoding='utf-8')
source_paths=list(SOURCES)+['AGENTS.md','.codex/MATLAB_MCP.md','outputs/beerten_validation_batch6_20260911/final_04/capability_step_100.json','outputs/beerten_validation_batch6_20260911/author_reference.json','outputs/algorithm_cleanup_batch4_20260911/beerten_probe.mat','outputs/beerten_nonslack_dispatch_20260914/smoke.mat']
manifest={'date':'2026-09-14','files':[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest(),'bytes':(ROOT/p).stat().st_size} for p in source_paths],'equation_count':eqnum,'artifact':'REPORT.html'}
(OUT/'source_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(OUT/'REPORT.md').write_text('''# VSC model explanation — 2026-09-14

Open [the standalone illustrated report](REPORT.html). It includes nine engineering sections, complete project/reference single-lines, the detailed station, 43 vector-rendered equations, actual terminal-power examples, capability comparisons, an interactive historical trace, code excerpts and primary references. It works offline.

The full station equations are electrically consistent, but PAC_SET/QAC_SET and PAC/QAC refer to the internal converter terminal while the capability geometry uses PCC voltage. At the historical C2 endpoint the surrogate indicates 99.9998% current utilization versus 94.4811% from the full reactor current. The unified result's station-loss columns also remain zero placeholders despite nonzero reactor losses.

Fresh MATLAB MCP PF checks passed. Historical CPF points remain labeled as the older fixed-G2 dispatch; the new non-slack dispatch is a separate scenario. No new physical stability margin is claimed and no production code or case parameters were changed.

See [station_results.csv](station_results.csv), [evidence.json](evidence.json), [MATLAB evidence](evidence.mat), and [verification](verification/verification.json).
''',encoding='utf-8')
print(json.dumps({'report':str(OUT/'REPORT.html'),'equations':eqnum,'figures':len(list(ASSET.glob('*.png')))+4,'bytes':len(doc.encode())}))
