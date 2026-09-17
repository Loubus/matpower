from pathlib import Path
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter
out=Path(__file__).resolve().parent
s=json.loads((out/'analysis_final_02/summary.json').read_text())
fig,ax=plt.subplots(1,2,figsize=(12,4.6),layout='constrained')
colors=['#a4b0be','#70889c','#41758c','#076b66']
for B,color in zip([0,5,10,15],colors):
 data=sorted([a for a in s['fixed_states'] if a['B']==B],key=lambda a:a['lambda'])
 ax[0].plot([a['lambda'] for a in data],[a['vm5'] for a in data],'o-',color=color,label=f'B = {B} MVAr',markersize=4)
ax[0].axhline(.94999,color='#b6513b',ls='--',lw=1.5,label='Lower band edge with tolerance')
ax[0].set(xlabel='Loading parameter lambda',ylabel='Bus 5 voltage (pu)',title='Full-equation PF at explicit shunt states')
ax[0].legend(loc='lower left',fontsize=8,frameon=False)
ax[0].set_ylim(.928,.952)
lo=s['last_lambda']; hi=s['candidate_lambda']; v0=s['last_vm5']; v1=s['candidate_vm5']
ax[1].plot([lo,hi],[v0,v1],color=colors[-1],lw=1.5)
ax[1].scatter([lo],[v0],s=60,color=colors[-1],label='Last accepted CPF point',zorder=3)
ax[1].scatter([hi],[v1],s=65,color='#b6513b',marker='x',label='Electrically solved, control-rejected candidate',zorder=3)
ax[1].axhline(.94999,color='#b6513b',ls='--',lw=1.5)
ax[1].set(xlabel='Loading parameter lambda',ylabel='Bus 5 voltage (pu)',title='Automatic control: B already at 15 MVAr')
ax[1].set_xlim(lo-.000025,hi+.000025)
ax[1].set_ylim(.94998,.950016)
ax[1].legend(loc='upper right',fontsize=8,frameon=False)
for a in ax:
 a.grid(alpha=.15)
 a.ticklabel_format(useOffset=False,style='plain',axis='both')
 for side in ['top','right']:a.spines[side].set_visible(False)
 a.tick_params(labelsize=8)
fig.suptitle('Beerten control-band termination: no failed electrical solve at the event',fontsize=13)
fig.savefig(out/'event_diagnostic.png',dpi=190)
