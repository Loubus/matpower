"""Measured diagnostic plots; schematic geometry is explicitly labelled."""
from pathlib import Path
import json
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle

out = Path(__file__).resolve().parent
d = json.loads((out/'evidence.json').read_text())
L=np.array(d['lambda']); PD=np.array(d['demand_MW'])
V=np.array(d['VSC_PCC_pu']); I=np.array(d['VSC_current_ratio'])
P=np.array(d['VSC_P_MW']); Q=np.array(d['VSC_Q_MVAr'])
peak=int(np.argmax(L)); lower=slice(peak,None)
blue='#1764a0'; orange='#e07813'; red='#c52d43'; teal='#078577'; navy='#142d45'
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'axes.spines.top':False,
                     'axes.spines.right':False,'axes.titleweight':'bold','figure.facecolor':'white'})
def save(fig,name):
    fig.savefig(out/(name+'.png'),dpi=155,bbox_inches='tight',facecolor='white')
    fig.savefig(out/(name+'.svg'),bbox_inches='tight',facecolor='white')
    plt.close(fig)
def tidy(ax):
    ax.grid(alpha=.2);ax.set_axisbelow(True)

fig,axs=plt.subplots(1,3,figsize=(16,5.2),layout='constrained')
fig.suptitle('What reaches its limit?  VSC 3 current — not failure of the last accepted point',fontsize=17,color=navy)
ax=axs[0]
ax.plot(PD[:peak+1],V[:peak+1,2],color=blue,label='Increasing demand',lw=2.5)
ax.plot(PD[lower],V[lower,2],color=orange,label='Lower branch',lw=2.5)
ax.scatter(PD[-1],V[-1,2],s=80,marker='x',color=red,zorder=5)
ax.annotate('Last accepted: 309.73 MW\n$V_5=0.235704$ pu\nEquations CONVERGED',
            xy=(PD[-1],V[-1,2]),xytext=(190,.46),arrowprops={'arrowstyle':'->','color':red},fontsize=10)
ax.set(xlabel='Total demand (MW)',ylabel='Bus 5 voltage (pu)',title='Measured PV curve');ax.legend(fontsize=9);tidy(ax)
ax=axs[1]
for j,col in enumerate([blue,teal,orange]):
    ax.plot(PD[lower],I[lower,j],color=col,lw=2.5,label=f'VSC {j+1}')
ax.axhline(1,color=red,ls='--',lw=1.3,label='Rated current')
ax.set(xlim=(PD[peak]+5,PD[-1]-5),ylim=(.3,1.05),xlabel='Demand decreases along lower branch (MW)',
       ylabel=r'$|I_c|/I_{\max}$',title='VSC 2 already limited; VSC 3 arrives')
ax.legend(loc='lower right',fontsize=9);tidy(ax)
ax=axs[2]
ax.plot(PD[lower],150*V[lower,2],color=teal,lw=2.5,label=r'Current-limited PCC capacity: $150V_5$')
ax.plot(PD[lower],np.hypot(P[lower,2],Q[lower,2]),color=orange,lw=2.5,label=r'Fixed request: $\sqrt{35^2+5^2}$')
ax.set(xlim=(PD[peak]+5,PD[-1]-5),xlabel='Demand decreases along lower branch (MW)',
       ylabel='PCC apparent power (MVA)',title='Low voltage shrinks the P–Q circle')
ax.legend(loc='upper right',fontsize=9)
ax.text(.05,.43,'150 MVA is the nominal-voltage rating.\nAt 0.2357 pu, rated current carries\nonly about 35.36 MVA at the PCC.',transform=ax.transAxes,fontsize=10,
        bbox={'facecolor':'#eef5fa','edgecolor':'none','pad':9})
tidy(ax)
save(fig,'01_approach_to_current_limit')

fig=plt.figure(figsize=(15,8.4),layout='constrained')
gs=fig.add_gridspec(2,2,height_ratios=[.8,1.5])
ax=fig.add_subplot(gs[0,:]);ax.set(xlim=(0,15),ylim=(0,3.1));ax.axis('off')
fig.suptitle('Why 35 MW can exhaust a 150 MVA converter at very low voltage',fontsize=18,color=navy)
def box(ax,x,y,w,h,text,fc='#edf4f9',fs=11):
    ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle='round,pad=.08',fc=fc,ec='#89a0b5',lw=1.2))
    ax.text(x+w/2,y+h/2,text,ha='center',va='center',fontsize=fs,color=navy)
def arrow(ax,a,b,label=None):
    ax.annotate('',xy=b,xytext=a,arrowprops={'arrowstyle':'->','lw':1.8,'color':navy})
    if label:ax.text((a[0]+b[0])/2,(a[1]+b[1])/2+.22,label,ha='center',fontsize=10)
box(ax,.15,1,2.5,1,'AC bus 5 / PCC\n$V_5=0.235704$ pu')
box(ax,3.6,1,2.6,1,'Transformer + filter\nSeries path; shunt = 0')
box(ax,7.2,1,2.1,1,'Reactor\n$R+jX$')
box(ax,10.25,1,2.2,1,'VSC 3 bridge\n$V_c=0.2524$ pu')
box(ax,13.35,1,1.35,1,'DC bus 5\n'+r'$V_{dc}\approx0.998$',fs=10)
arrow(ax,(3.5,1.5),(2.75,1.5),'35 + j5')
arrow(ax,(7.05,1.5),(6.35,1.5))
arrow(ax,(10.1,1.5),(9.45,1.5))
arrow(ax,(13.2,1.5),(12.6,1.5))
ax.text(7.4,.32,'Illustrative station layout; annotations are measured. All component nominal ratings remain 150 MVA.',ha='center',fontsize=11)
ax.text(7.4,2.62,r'No station shunt current here: $|I_c|/I_{\max}=\sqrt{P^2+Q^2}/(150V_{PCC})$',ha='center',fontsize=15)
ax=fig.add_subplot(gs[1,0]);theta=np.linspace(0,2*np.pi,500)
for vv,col in [(1,blue),(.5,teal),(d['last']['V5'],orange)]:
    rr=150*vv;ax.plot(rr*np.cos(theta),rr*np.sin(theta),color=col,lw=2,label=f'$V={vv:.4g}$ pu; radius {rr:.2f} MVA')
ax.plot([0,35],[0,5],':',color='gray');ax.scatter([35],[5],c=red,s=50,zorder=6)
ax.annotate('Fixed request\n(35 MW, 5 MVAr)',xy=(35,5),xytext=(60,50),arrowprops={'arrowstyle':'->'},fontsize=10)
ax.set(aspect='equal',xlabel='P injection (MW)',ylabel='Q injection (MVAr)',title='Current boundary in the PCC P–Q plane')
ax.legend(loc='lower left',fontsize=9);tidy(ax)
ax=fig.add_subplot(gs[1,1]);ax.axis('off')
ax.text(.02,.97,'Worked example at the last accepted point',va='top',fontsize=14,weight='bold',color=navy)
items=[r'$S_{PCC}=\sqrt{35^2+5^2}=35.3553\ \mathrm{MVA}$',
       r'$S_{I\max}(V)=150V=35.3555\ \mathrm{MVA}$',
       rf'$\frac{{|I_c|}}{{I_{{\max}}}}={d["last"]["current_ratios"][2]:.8f}$',
       r'$V_{contact}=\frac{\sqrt{35^2+5^2}}{150}=0.23570226\ \mathrm{pu}$']
for y,txt in zip([.80,.64,.47,.30],items):ax.text(.02,y,txt,fontsize=16)
ax.text(.02,.06,'Circles show the CURRENT constraint only.\nThe internal-voltage ceiling is separate (1.15 pu)\nand is far from binding here.',fontsize=11,color='#526575')
save(fig,'02_station_and_capability')

fig=plt.figure(figsize=(15,9.2),layout='constrained');gs=fig.add_gridspec(3,2,height_ratios=[1.2,1.3,1])
fig.suptitle('The failure is inside the VSC 3 saturation iteration',fontsize=18,color=navy)
ax=fig.add_subplot(gs[0,:]);ax.set(xlim=(0,15),ylim=(0,3));ax.axis('off')
for x,txt,fc in [(0.15,'Next CPF point solves\nCurrent just over limit','#e8f4ee'),
                 (3.9,'Reduce P and Q together\n(radial projection)','#eef4fa'),
                 (7.65,'Re-correct network\nwith new fixed P and Q','#eef4fa'),
                 (11.4,'Voltage falls further\nCurrent violation grows','#fbeaec')]:
    box(ax,x,1.0,3.25,1.1,txt,fc,10)
for x in [3.45,7.2,10.95]:arrow(ax,(x,1.55),(x+.38,1.55))
ax.plot([13,13,5.5],[.94,.50,.50],color=red,lw=1.6)
ax.annotate('',xy=(5.5,.94),xytext=(5.5,.50),arrowprops={'arrowstyle':'->','lw':1.6,'color':red})
ax.text(9.2,.10,'Repeat: this trial sequence amplifies the error',color=red,ha='center',fontsize=11)
ax.text(7.5,2.6,'Algorithm diagram — the numbers below are measured rejected-trial states, not accepted PV points.',ha='center',fontsize=11)
cas=d['last_attempt_cascade'];xx=np.arange(3)
ax=fig.add_subplot(gs[1,0]); vv=[a['V5'] for a in cas];pp=[a['P3'] for a in cas]
ax.plot(xx,vv,'o-',color=blue,lw=2.5);ax.set(xticks=xx,xticklabels=['Initial trial','After projection 1','After projection 2'],
    ylabel='Bus 5 voltage (pu)',ylim=(.16,.25),title='Voltage falls faster than the P/Q request')
for x,y,p in zip(xx,vv,pp):ax.annotate(f'P = {p:.4f} MW',(x,y),xytext=(0,10),textcoords='offset points',ha='center',fontsize=10)
tidy(ax)
ax=fig.add_subplot(gs[1,1]); ii=[a['I3_ratio'] for a in cas]
ax.bar(xx,100*(np.array(ii)-1),color=[orange,orange,red],width=.55)
ax.set(xticks=xx,xticklabels=['Initial trial','After projection 1','After projection 2'],ylabel='Current above rating (%)',ylim=(0,35),title='A tiny violation becomes a large one')
for x,y in zip(xx,ii):ax.text(x,100*(y-1)+.8,f'{100*(y-1):.4f}%',ha='center',fontsize=11)
tidy(ax)
ax=fig.add_subplot(gs[2,:]);ax.axis('off')
rows=[['Last accepted',f'{d["last"]["lambda"]:.9f}',f'{d["last"]["V5"]:.7f}',f'{d["last"]["current_ratios"][2]:.7f}','YES'],
      *[[label,f'{a["lambda"]:.9f}',f'{a["V5"]:.7f}',f'{a["I3_ratio"]:.7f}','NO: capability violation']
        for label,a in zip(['Next trial','Correction 1','Correction 2'],cas)],
      ['Correction 3','-1.024089939','Invalid iterate','Not a solved point','NO: corrector failed']]
tab=ax.table(cellText=rows,colLabels=['Stage','Lambda','V5 (pu)','Current / rating','Accepted?'],loc='center',cellLoc='center',colWidths=[.17,.17,.17,.17,.30])
tab.auto_set_font_size(False);tab.set_fontsize(10);tab.scale(1,1.7)
for (row,col),cell in tab.get_celld().items():
    cell.set_edgecolor('#d4dfe7')
    if row==0:cell.set_facecolor(navy);cell.get_text().set_color('white')
    elif row==1:cell.set_facecolor('#e8f4ee')
    else:cell.set_facecolor('#f8f1f1')
save(fig,'03_failed_transition')
print('Wrote three measured diagnostic figures, with illustrative station/algorithm diagrams.')
