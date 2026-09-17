"""Tabulate validation evidence, source precision, options, and comparison plots."""
import copy,csv,hashlib,json
import numpy as np
from independent_validation import OUT,TRACE,DEST,INPUT,Circuit,write
import matplotlib.pyplot as plt

def read(p):return json.loads(p.read_text())
summary=read(TRACE/'project_summary.json');ind=read(DEST/'independent_summary.json');controls=read(TRACE/'control_audit_02.json')
rows=[];checks=[]
def check(name,ok,scope='verification'):checks.append({'id':name,'passed':bool(ok),'scope':scope})
for name,s in summary.items():
    d=read(TRACE/(name+'.json'));a=read(DEST/(name+'_independent.json'));pt=d['points'][-1]
    g=np.array(pt['case']['gen']);cv=np.array(pt['vsc']);b=np.array(pt['case']['bus']);end=a['audit'][-1]
    rows.append({'scenario':name,'lambda':s['last_lambda'],'bus5_MW':b[4,2],'total_MW':sum(b[:,2]),'total_MVAr':sum(b[:,3]),'V5':b[4,7], 'V3':b[2,7],'V6':b[5,7],'V7':b[6,7],'G1_P_MW':g[0,1],'G1_Q_MVAr':g[0,2],'G2_Q_MVAr':g[1,2], 'G2_Q_reserve_MVAr':end['gen_q_reserve'][1], 'VSC2_Q_MVAr':cv[1,30],'VSC2_I_ratio':end['converter_current_utilization'][1],'VSC2_geometry_margin_MVA':end['converter_geometry_margin'][1],'tap':np.array(pt['case']['branch'])[-1,8],'shunt_MVAr_at_1pu':b[4,5],'accepted_points':len(d['points']),'cause':s['termination']['cause'],'all_equipment_compliant':False})
    for k,(au,control) in enumerate(zip(d['audits'],controls[name])):
        tag=f'{name}_point{k+1}'
        check(tag+'_full_balances',max(au[x] for x in ['ac','dc','converter','residual'])<1e-8)
        check(tag+'_constant_PQ',au['load_error']<1e-10)
        check(tag+'_effective_controls',not control['changed'] and control['acceptance']['accepted'])
        check(tag+'_legal_eligible_controls',control['legal_tap'] and control['legal_shunt'] and not control['locked'])
        check(tag+'_independent_equations',a['audit'][k]['residual_independent']<1e-8)
        if name!='unconstrained':
            check(tag+'_non_slack_gen_curve',a['audit'][k]['gen_curve_violation'][1]<=1e-8)
            check(tag+'_converter_geometry',min(a['audit'][k]['converter_geometry_margin'])>=-1e-8)
            check(tag+'_actual_converter_station',max(a['audit'][k]['converter_current_utilization'])<=1+1e-8 and max(a['audit'][k]['converter_voltage'])<=1.15+1e-8 and max(a['audit'][k]['station_MVA_utilization'])<=1+1e-8)
    for pf in a['fixed_state_pf']:
        check(f'{name}_PF{pf["point"]}',pf['solver_success'] and pf['residual']<1e-8 and pf['max_voltage_error']<1e-6 and pf['max_dc_error']<1e-6)
    check(name+'_all_equipment_feasible',ind[name]['all_equipment_feasible_points']==len(d['points']),scope='scientific_acceptance')
with (TRACE/'results_table.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)

# The manual is a rounded numerical reference, not a high-precision oracle.
oracle=read(OUT/'author_reference.json');ac=oracle['ac'];dc=oracle['dc'];ab=np.array(ac['bus']);ag=np.array(ac['gen']);cv=np.array(dc['convdc']);bd=np.array(dc['busdc'])
precision=[]
def printed(name,actual,ref,unit):
    err=float(np.max(np.abs(np.array(actual)-np.array(ref))));precision.append({'quantity':name,'max_abs_error':err,'half_last_printed_digit':unit/2,'within_rounding':err<=unit/2+1e-8})
printed('manual_AC_VM',ab[:,7],[1.06,1,1,.996,.991],.001)
printed('manual_AC_VA',ab[:,8],[0,-2.383,-3.895,-4.262,-4.149],.001)
printed('manual_generators_PQ',ag[:2,1:3],[[133.64,84.32],[40,-32.84]],.01)
printed('manual_VSC_PCC_PQ',cv[:,3:5],[[-60,-40],[20.76,7.14],[35,5]],.01)
printed('manual_converter_VM',cv[:,24],[.890,1.007,.995],.001)
printed('manual_converter_VA',cv[:,25],[-13.017,-.655,1.442],.001)
printed('manual_DC_VM',bd[:,4],[1.008,1,.998],.001)
printed('manual_DC_P_MW',bd[:,3],[-58.627,21.901,36.186],.001)
printed('manual_AC_branch_PQ',np.array(ac['branch'])[:,13:17],[[98.38,71.37,-95.66,-69.59],[35.26,12.96,-34.20,-15.08],[13.25,-6.22,-13.14,2.57],[17.08,-5.18,-16.89,1.74],[25.33,-1.85,-25.07,-.35],[23.09,4.64,-23.04,-6.47],[-.07,-.27,.07,-4.65]],.01)
ref=read(DEST/'reference_comparison.json')
printed('paper2010_AC_only_VM',np.array(ref['paper2010_ac_only']['bus'])[:,0],[1.06,1,.987,.984,.972],.001)
printed('paper2010_AC_only_VA',np.array(ref['paper2010_ac_only']['bus'])[:,1],[0,-2.06,-4.64,-4.96,-5.77],.01)
printed('paper2010_AC_with_printed_Ps_VM',np.array(ref['paper2010_ac_using_printed_Ps']['bus'])[:,0],[1.06,1,1,.996,.991],.001)
printed('paper2010_AC_with_printed_Ps_VA',np.array(ref['paper2010_ac_using_printed_Ps']['bus'])[:,1],[0,-2.39,-3.90,-4.27,-4.15],.01)
for p in precision:check(p['quantity'],p['within_rounding'])
check('independent_MatACDC_VM',ref['matacdc_independent']['max_author_bus_voltage_error']<1e-6)
check('independent_MatACDC_PCC',ref['matacdc_independent']['max_author_pcc_power_error']<1e-6)
write('reference_precision_checks.json',precision)
write('validation_checks.json',checks)
write('validation_counts.json',{'verification_passed':sum(c['passed'] for c in checks if c['scope']=='verification'),'verification_failed':sum(not c['passed'] for c in checks if c['scope']=='verification'),'scientific_acceptance_failed':sum(not c['passed'] for c in checks if c['scope']=='scientific_acceptance')})

# Every original voltage and converter loading stays accessible in the trace.
fig,axs=plt.subplots(1,2,figsize=(12,4.5),constrained_layout=True)
for ax,name,title in zip(axs,['unconstrained','capability_step_100'],['Unconstrained numerical reference','Supported capability options enabled']):
    d=read(TRACE/(name+'.json'));lam=[p['lambda'] for p in d['points']];vm=np.array([np.array(p['case']['bus'])[:,7] for p in d['points']])
    for k in range(vm.shape[1]):ax.plot(lam,vm[:,k],label=f'Bus {k+1}')
    ax.set(xlabel='lambda (total demand = 165 + 240 lambda MW)',ylabel='Voltage (pu)',title=title);ax.grid(alpha=.25);ax.legend(ncol=2,fontsize=8)
fig.savefig(TRACE/'voltage_traces.png',dpi=160);plt.close(fig)
fig,axs=plt.subplots(2,2,figsize=(12,8),constrained_layout=True)
for name,style in [('unconstrained','--'),('capability_step_100','-')]:
    d=read(TRACE/(name+'.json'));lam=np.array([p['lambda'] for p in d['points']]);b=np.array([p['case']['bus'] for p in d['points']]);cv=np.array([p['vsc'] for p in d['points']]);g=np.array([p['case']['gen'] for p in d['points']]);branch=np.array([p['case']['branch'] for p in d['points']]);lab='Unconstrained' if style=='--' else 'Capabilities enabled'
    axs[0,0].step(lam,branch[:,-1,8],where='post',linestyle=style,label=lab)
    axs[0,1].step(lam,b[:,4,5],where='post',linestyle=style,label=lab)
    axs[1,0].plot(lam,g[:,1,2],style,label=lab)
    axs[1,1].plot(lam,cv[:,1,30],style,label=lab)
for ax,title,ylabel in zip(axs.flat,['Load-side transformer','Bus 5 switched shunt','Generator 2 output','Converter 2 output'],['Tap ratio','B at 1 pu (MVAr)','Q (MVAr)','Internal Q (MVAr)']):
    ax.set(xlabel='lambda',ylabel=ylabel,title=title);ax.grid(alpha=.25);ax.legend(fontsize=8)
axs[1,0].axhline(75.2271164,color='black',lw=.7)
fig.savefig(TRACE/'control_traces.png',dpi=160);plt.close(fig)

# Matched-lambda independent PF comparisons: choose the unconstrained trace's
# preceding fixed control state. These rows are explicitly fixed-state PF.
con=read(TRACE/'capability_step_100.json')['points'];unc=read(TRACE/'unconstrained.json')['points'];pairs=[]
for k in sorted(set(min(range(len(con)),key=lambda j:abs(con[j]['lambda']-l)) for l in [0,.8,1.08,1.105,1.13,con[-1]['lambda']])):
    p=con[k];lam=p['lambda'];q=max((q for q in unc if q['lambda']<=lam),key=lambda q:q['lambda']);case=copy.deepcopy(q['case']);bb=np.array(case['bus']);bb[:,2:4]=np.array(INPUT['base']['bus'])[:,2:4]+lam*(np.array(INPUT['target']['bus'])[:,2:4]-np.array(INPUT['base']['bus'])[:,2:4]);case['bus']=bb.tolist();cir=Circuit(case);st,meta=cir.solve(q)
    pairs.append({'lambda':lam,'total_MW':165+240*lam,'constrained_trace_V5':np.array(p['case']['bus'])[4,7],'unconstrained_fixed_state_PF_V5':abs(st[0][4]),'unconstrained_PF_success':meta['solver_success'],'unconstrained_PF_residual':meta['residual'],'constrained_G2_Q':np.array(p['case']['gen'])[1,2],'unconstrained_G2_Q':st[2][5].imag,'constrained_VSC2_Q':np.array(p['vsc'])[1,30],'unconstrained_VSC2_Q':st[4][1].imag})
write('matched_loading_comparison.json',pairs)
print(json.dumps({'precision_failures':[x for x in precision if not x['within_rounding']], 'verification_failures':[x for x in checks if not x['passed'] and x['scope']=='verification']},indent=2))
