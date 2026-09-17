"""Independent rectangular-voltage PF and equipment audit; no MATLAB calls.

Builds its own admittances from raw branch/station inputs, evaluates terminal
powers directly, and uses SciPy finite-difference root finding. A fixed-state
solve validates electrical equations for that state, not its control selection.
"""
from pathlib import Path
import json, re, copy, os
import numpy as np
from scipy.optimize import root
os.environ.setdefault('MPLCONFIGDIR',str(Path(__file__).resolve().parent/'mplconfig'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

OUT=Path(__file__).resolve().parent
TRACE=OUT/'final_04'
DEST=TRACE/'independent_final'
DEST.mkdir(exist_ok=True)
INPUT=json.loads((OUT/'inputs.json').read_text())

def write(name,data):
    def convert(x):
        if isinstance(x,np.ndarray): return x.tolist()
        if isinstance(x,np.generic): return x.item()
        raise TypeError(type(x))
    (DEST/name).write_text(json.dumps(data,indent=2,default=convert),encoding='utf-8')

def matrix(path,name):
    txt=path.read_text(encoding='utf-8',errors='replace')
    txt=re.sub(r'%[^\n]*','',txt)
    body=re.search(r'\b'+name+r'\s*=\s*\[(.*?)\];',txt,re.S)[1]
    return [[float(v) for v in row.split()] for row in body.split(';') if row.strip()]

class Circuit:
    def __init__(self,p,location='internal',loss_directional=False):
        self.p=p;self.b=np.array(p['bus'],float);self.g=np.array(p['gen'],float)
        self.cv=np.array(p['vsc'],float);self.br=np.array(p['branch'],float)
        self.dc=np.array(p['busdc'],float);self.dbr=np.array(p['branchdc'],float)
        self.base=p['baseMVA'];self.n=len(self.b);self.nv=len(self.cv);self.N=self.n+2*self.nv
        self.location=location;self.directional=loss_directional
        self.lookup={int(row[0]):k for k,row in enumerate(self.b)}
        self.dlookup={int(row[0]):k for k,row in enumerate(self.dc)}
        self.ref=np.flatnonzero(self.b[:,1]==3)[0]
        self.nonref=np.array([i for i in range(self.N) if i!=self.ref])
        self.Y=np.zeros((self.N,self.N),complex); self.branch_terms=[]
        for row in self.br:
            i,j=self.lookup[int(row[0])],self.lookup[int(row[1])]
            self.addbranch(i,j,row[2],row[3],row[4],row[8],row[9],row[10])
        for i,row in enumerate(self.b): self.Y[i,i]+=(row[4]+1j*row[5])/self.base
        self.maps=[]
        for k,row in enumerate(self.cv):
            pcc=self.lookup[int(row[0])]; fil=self.n+2*k; intr=fil+1
            it=self.addbranch(pcc,fil,row[14],row[15],row[16],1,row[17],row[2])
            self.Y[fil,fil]+=row[21]+1j*row[22]
            ir=self.addbranch(fil,intr,row[23],row[24],row[25],1,0,row[2])
            self.maps.append((pcc,fil,intr,it,ir))
        self.G=np.zeros((len(self.dc),len(self.dc)))
        for row in self.dbr:
            if row[3]<=0: continue
            i,j=self.dlookup[int(row[0])],self.dlookup[int(row[1])]
            y=1/row[2];self.G[i,i]+=y;self.G[j,j]+=y;self.G[i,j]-=y;self.G[j,i]-=y
        self.dfixed={self.dlookup[int(row[1])]:row[9] for row in self.cv if row[4]==1}
        self.dvar=[k for k in range(len(self.dc)) if k not in self.dfixed]
        self.genbus={self.lookup[int(row[0])]:k for k,row in enumerate(self.g) if row[7]>0}

    def addbranch(self,i,j,r,x,b,tap,shift,status):
        a=(tap or 1)*np.exp(1j*np.deg2rad(shift));y=status/complex(r,x)
        yy=y+1j*b*status/2; ff=yy/abs(a)**2;ft=-y/np.conj(a);tf=-y/a;tt=yy
        self.Y[i,i]+=ff;self.Y[i,j]+=ft;self.Y[j,i]+=tf;self.Y[j,j]+=tt
        self.branch_terms.append((i,j,ff,ft,tf,tt));return len(self.branch_terms)-1

    def powers(self,V):
        return np.array([[V[i]*np.conj(ff*V[i]+ft*V[j])*self.base,
                          V[j]*np.conj(tf*V[i]+tt*V[j])*self.base]
                         for i,j,ff,ft,tf,tt in self.branch_terms])

    def state(self,x):
        V=np.ones(self.N,dtype=complex);nr=len(self.nonref)
        V[self.nonref]=x[:nr]+1j*x[nr:2*nr]
        gr=self.genbus[self.ref];V[self.ref]=self.g[gr,5]*np.exp(1j*np.deg2rad(self.b[self.ref,8]))
        D=np.array(self.dc[:,2]);D[self.dvar]=x[2*nr:]
        for k,val in self.dfixed.items():D[k]=val
        S=V*np.conj(self.Y@V)*self.base; flows=self.powers(V)
        C=np.array([flows[m[4],1] for m in self.maps])
        PCC=np.array([-flows[m[3],0] for m in self.maps])
        U=np.array([abs(V[m[2]]) for m in self.maps]);I=np.abs(C)/self.base/U
        coeff=self.cv[:,13]
        if self.directional:coeff=np.where(C.real>0,np.array(self.p['loss_cr']),np.array(self.p['loss_ci']))
        loss=self.cv[:,11]+self.cv[:,12]*I+coeff*I**2
        Pdc=D*(self.G@D)*self.base
        return V,D,S,flows,C,PCC,loss,Pdc

    def fun(self,x):
        V,D,S,flows,C,PCC,loss,Pdc=self.state(x);eq=[]
        for i,row in enumerate(self.b):
            if i==self.ref:continue
            g=self.genbus.get(i);sg=0 if g is None else complex(self.g[g,1],self.g[g,2])
            mis=(S[i]-sg+complex(row[2],row[3]))/self.base
            eq.append(mis.real)
            if g is not None and row[1]==2:eq.append(abs(V[i])-self.g[g,5])
            else:eq.append(mis.imag)
        for k,(pcc,fil,intr,it,ir) in enumerate(self.maps):
            row=self.cv[k];eq.extend([S[fil].real/self.base,S[fil].imag/self.base])
            control=C[k] if self.location=='internal' else PCC[k]
            d=self.dlookup[int(row[1])]
            if row[3] in (3,4):eq.append((control.real-row[5])/self.base)
            else:eq.append((C[k].real+loss[k]+Pdc[d])/self.base)
            if row[3] in (1,3):eq.append((control.imag-row[6])/self.base)
            else:eq.append(abs(V[pcc])-row[7])
        for d in self.dvar:
            k=np.flatnonzero(self.cv[:,1]==self.dc[d,0])[0]
            eq.append((C[k].real+loss[k]+Pdc[d])/self.base)
        return np.array(eq)

    def xfrom(self,V,D):
        return np.r_[V[self.nonref].real,V[self.nonref].imag,D[self.dvar]]

    def solve(self,point=None):
        if point is None:
            V=np.ones(self.N,dtype=complex)
            V[:self.n]=self.b[:,7]*np.exp(1j*np.deg2rad(self.b[:,8]))
            for pcc,fil,intr,_,_ in self.maps:V[fil]=V[intr]=V[pcc]
            D=self.dc[:,2].copy()
        else:
            V,D=self.point_voltage(point);V[self.nonref]*=(1.0003+0.0002j)
        x0=self.xfrom(V,D)
        sol=root(self.fun,x0,method='hybr',options={'xtol':1e-10})
        state=self.state(sol.x);res=float(np.max(np.abs(self.fun(sol.x))))
        return state,{'solver_success':bool(sol.success),'residual':res,'message':sol.message,'evaluations':sol.nfev}

    def point_voltage(self,point):
        ab=np.array(point['ac_bus']);lu={int(row[0]):row[7]*np.exp(1j*np.deg2rad(row[8])) for row in ab}
        V=np.ones(self.N,complex)
        for i,row in enumerate(self.b):V[i]=lu[int(row[0])]
        cv=np.array(point['vsc'])
        for k,(_,fil,intr,_,_) in enumerate(self.maps):V[fil]=lu[int(cv[k,40])];V[intr]=lu[int(cv[k,41])]
        return V,np.array(point['case']['busdc'])[:,2]

def capability(cir,point):
    V,D=cir.point_voltage(point);_,_,S,flows,C,PCC,loss,Pdc=cir.state(cir.xfrom(V,D))
    gen=np.array(point['case']['gen']); cv=np.array(point['vsc']); result={}
    snom=np.array(INPUT['base']['gen'])[:,6]
    pg=gen[:,1];qg=gen[:,2];p=pg/snom
    # Original generic thermal curve, direct inequalities, including slack.
    # The arc/line exists only for 0 <= p <= .8. Outside that interval,
    # report P infeasibility and evaluate the end-of-domain Q bounds;
    # never extrapolate the capability arc beyond its defined domain.
    curve_p=np.clip(p,0,.8)
    qhi=(np.sqrt(1.7**2-curve_p**2)-0.9)*snom
    qlo=np.where(curve_p<=.15,-.45,-.45+(curve_p-.15)*(.25/.65))*snom
    result['gen_p_reserve']=.8*snom-pg
    result['gen_q_reserve']=qhi-qg
    result['gen_q_lower_reserve']=qg-qlo
    result['gen_curve_violation']=np.maximum.reduce([pg-.8*snom,-pg,qg-qhi,qlo-qg,np.zeros(len(pg))])
    original=np.array(INPUT['base']['gen'])
    result['gen_box_violation']=np.maximum.reduce([pg-original[:,8],original[:,9]-pg,qg-original[:,3],original[:,4]-qg,np.zeros(len(pg))])
    # Exact station current and voltage, plus implemented surrogate geometry.
    vmax=1.15;smax=np.minimum(cir.cv[:,18],cir.cv[:,26]);u=np.array([abs(V[m[2]]) for m in cir.maps]);vp=np.array([abs(V[m[0]]) for m in cir.maps])
    current=np.abs(C)/(cir.base*u);result['converter_current_utilization']=current/(smax/cir.base)
    result['converter_voltage']=u
    result['converter_pcc_power']=np.c_[PCC.real,PCC.imag]
    result['converter_internal_power']=np.c_[C.real,C.imag]
    z=np.abs(cir.cv[:,14]+cir.cv[:,23]+1j*(cir.cv[:,15]+cir.cv[:,24]))
    result['converter_geometry_margin']=np.minimum.reduce([smax-np.abs(C.real),vp*smax-np.abs(C),vp*vmax*cir.base/z-np.hypot(C.real,C.imag+vp**2*cir.base/z)])
    station=np.array([max(abs(flows[m[3],0]),abs(flows[m[3],1]),abs(flows[m[4],0]),abs(flows[m[4],1])) for m in cir.maps])
    result['station_MVA_utilization']=station/smax
    result['ac_branch_MVA_utilization']=np.max(np.abs(flows[:len(cir.br)]),axis=1)/cir.br[:,5]
    result['residual_independent']=float(np.max(np.abs(cir.fun(cir.xfrom(V,D)))))
    result['full_nodal_table_error']=float(np.max(np.abs(np.array(point['ac_gen'])[:len(gen),1:3]-gen[:,1:3])))
    result['reported_converter_error']=float(np.max(np.abs(cv[:,29:32]-np.c_[C.real,C.imag,Pdc])))
    return result

def project():
    allstats={};plotdata={}
    for name in ['unconstrained','capability_step_100','capability_step_050','capability_step_025']:
        data=json.loads((TRACE/(name+'.json')).read_text());aud=[];pf=[]
        for k,pt in enumerate(data['points']):
            cir=Circuit(pt['case']);a=capability(cir,pt);a['lambda']=pt['lambda'];a['point']=k+1;aud.append(a)
            # All points except singular mathematical nose: selected-point
            # requirement is exceeded, but no independent nose locator claimed.
            if name=='unconstrained' and k==len(data['points'])-1:continue
            state,meta=cir.solve(pt);V,D=cir.point_voltage(pt)
            meta.update(point=k+1,lambda_value=pt['lambda'],max_voltage_error=float(np.max(abs(state[0]-V))),max_dc_error=float(np.max(abs(state[1]-D))))
            pf.append(meta)
        write(name+'_independent.json',{'audit':aud,'fixed_state_pf':pf})
        allstats[name]={'max_equation_residual':max(a['residual_independent'] for a in aud),
          'pf_max_voltage_error':max(a['max_voltage_error'] for a in pf),
          'pf_max_residual':max(a['residual'] for a in pf),'pf_solver_failures':sum(not a['solver_success'] for a in pf),
          'all_equipment_feasible_points':sum(np.max(a['gen_curve_violation'])<=1e-8 and np.max(a['gen_box_violation'])<=.01 and min(a['converter_geometry_margin'])>=-1e-8 and max(a['station_MVA_utilization'])<=1+1e-8 for a in aud),
          'max_non_slack_gen_violation':max(a['gen_curve_violation'][1] for a in aud),
          'min_converter_geometry_margin':min(min(a['converter_geometry_margin']) for a in aud),
          'base':aud[0],'end':aud[-1], 'termination':data['summary']['termination']}
        plotdata[name]=(data,aud)
    write('independent_summary.json',allstats)
    fig,axs=plt.subplots(3,2,figsize=(12,12),constrained_layout=True)
    for name,(data,aud) in plotdata.items():
        if name=='capability_step_025':continue
        lab={'unconstrained':'Unconstrained numerical reference','capability_step_100':'Capability options on: step 0.1','capability_step_050':'Capability options on: step 0.05'}[name]
        lam=np.array([p['lambda'] for p in data['points']]);vm=np.array([np.array(p['case']['bus'])[:,7] for p in data['points']]);gen=np.array([np.array(p['case']['gen'])[:,1:3] for p in data['points']]);vsc=np.array([np.array(p['vsc']) for p in data['points']])
        axs[0,0].plot(lam,vm[:,4],label=lab);axs[0,1].plot(lam,[a['gen_q_reserve'][1] for a in aud],label=lab)
        axs[1,0].plot(lam,[a['converter_current_utilization'][1] for a in aud],label=lab)
        axs[1,1].plot(lam,[a['gen_p_reserve'][0] for a in aud],label=lab)
        axs[2,0].step(lam,vm[:,2],where='post',label=lab);axs[2,1].step(lam,vsc[:,1,3],where='post',label=lab)
    labels=['Bus 5 voltage (pu)','Generator 2 upper Q reserve (MVAr)','Converter 2 current / original current bound','Slack P reserve to generic curve (MW)','Bus 3 voltage (pu)','Converter 2 AC mode (2=V, 1=Q)']
    for ax,title in zip(axs.flat,labels):ax.set_title(title);ax.set_xlabel('lambda: P5 = 60 + 240 lambda MW');ax.grid(alpha=.25)
    axs[0,1].axhline(0,color='black',lw=.7);axs[1,0].axhline(1,color='black',lw=.7);axs[1,1].axhline(0,color='black',lw=.7)
    axs[0,0].legend(fontsize=8);fig.suptitle('Beerten project: supported capability enforcement is not all-equipment feasibility',fontsize=13)
    fig.savefig(DEST/'comparison.png',dpi=160);plt.close(fig)
    print(json.dumps({k:{j:v for j,v in s.items() if j not in ('base','end','termination')} for k,s in allstats.items()},indent=2,default=lambda x:x.item()))

def references():
    p=copy.deepcopy(INPUT['paper_input']);cir=Circuit(p);state,meta=cir.solve()
    local={'bus':np.c_[np.abs(state[0][:5]),np.rad2deg(np.angle(state[0][:5]))], 'vsc_internal':np.c_[state[4].real,state[4].imag], 'vsc_pcc':np.c_[state[5].real,state[5].imag], 'converter_voltage':np.array([abs(state[0][m[2]]) for m in cir.maps]),'loss':state[6],'dc_power':state[7],'dc_voltage':state[1],'solve':meta}
    # Exact archived configuration: no ratings are borrowed into project case.
    folder=OUT/'reference/MatACDC1.0/Cases';ac=folder/'PowerflowAC/case5_stagg.m';dc=folder/'PowerflowDC/case5_stagg_MTDCslack.m'
    bus=np.array(matrix(ac,'bus'));gen=np.array(matrix(ac,'gen'));br=np.array(matrix(ac,'branch'));cv=np.array(matrix(dc,'convdc'));bd=np.array(matrix(dc,'busdc'));db=np.array(matrix(dc,'branchdc'))
    br=np.c_[br,np.tile([-360,360],(len(br),1))]
    c=np.zeros((3,29));c[:,0]=bd[:,1];c[:,1]=bd[:,0];c[:,2]=cv[:,15];c[:,3]=[3,2,3];c[:,4]=[2,1,2];c[:,5:7]=cv[:,3:5];c[:,7]=cv[:,5];c[:,9]=1
    ibase=100/(np.sqrt(3)*cv[:,11]);c[:,11]=cv[:,16];c[:,12]=cv[:,17]*ibase;c[:,13]=cv[:,19]*ibase**2;c[:,14:16]=cv[:,6:8];c[:,22]=cv[:,8];c[:,23:25]=cv[:,9:11];c[:,18:21]=100;c[:,26:29]=100
    auth={'baseMVA':100,'bus':bus.tolist(),'gen':gen.tolist(),'branch':br.tolist(),'vsc':c.tolist(),'busdc':np.c_[bd[:,0],np.ones(3),bd[:,4],bd[:,5]].tolist(),'branchdc':np.c_[db[:,0:2],db[:,2]/2,db[:,8]].tolist(),'loss_cr':(cv[:,18]*ibase**2).tolist(),'loss_ci':(cv[:,19]*ibase**2).tolist()}
    cir=Circuit(auth,location='pcc',loss_directional=True);state,meta=cir.solve();oracle=json.loads((OUT/'author_reference.json').read_text())
    av=np.array(oracle['ac']['bus']);dcres=np.array(oracle['dc']['convdc']);dr=np.array(oracle['dc']['busdc'])
    independent={'bus':np.c_[abs(state[0][:5]),np.rad2deg(np.angle(state[0][:5]))],'converter_voltage':np.array([abs(state[0][m[2]]) for m in cir.maps]),'pcc':np.c_[state[5].real,state[5].imag], 'dc_voltage':state[1], 'dc_power':state[7],'loss':state[6],'solve':meta}
    independent['max_author_bus_voltage_error']=float(np.max(abs(state[0][:5]-av[:,7]*np.exp(1j*np.deg2rad(av[:,8])))))
    independent['max_author_pcc_power_error']=float(np.max(abs(independent['pcc']-dcres[:,3:5])))
    independent['max_author_dc_voltage_error']=float(np.max(abs(state[1]-dr[:,4])))
    # Reproduce only the AC part of the 2010 result, with printed bus injections.
    # This deliberately does not infer missing impedances from printed outputs.
    pb=copy.deepcopy(p);B=np.array(pb['bus']);B[1,2:4]-=[-60,-40];B[4,2:4]-=[35,5];B[2,2]-=20.68;B[2,1]=2
    G=np.array(pb['gen']);gnew=G[1].copy();gnew[0]=3;gnew[1]=0;gnew[5]=1;G=np.vstack([G,gnew]);pb.update(bus=B.tolist(),gen=G.tolist(),vsc=[],busdc=[],branchdc=[])
    Y=np.zeros((5,5),complex)
    for row in np.array(p['branch']):
        i,j=int(row[0])-1,int(row[1])-1;y=1/complex(row[2],row[3]);Y[i,i]+=y+1j*row[4]/2;Y[j,j]+=y+1j*row[4]/2;Y[i,j]-=y;Y[j,i]-=y
    def acsolve(with_hvdc):
        b=B.copy() if with_hvdc else np.array(p['bus']);pv=[1,2] if with_hvdc else [1];pq=[k for k in range(1,5) if k not in pv]
        def evaluate(x):
            vm=np.ones(5);vm[0]=1.06;vm[pq]=x[4:];ang=np.r_[0,x[:4]];v=vm*np.exp(1j*ang);S=v*np.conj(Y@v)*100
            pg=np.array([0,40,0,0,0]);mis=(S+b[:,2]+1j*b[:,3]-pg)/100
            return np.r_[mis[1:].real,mis[pq].imag],v,S
        sol=root(lambda x:evaluate(x)[0],np.r_[np.zeros(4),np.ones(len(pq))],options={'xtol':1e-10});F,v,S=evaluate(sol.x)
        return {'bus':np.c_[abs(v),np.rad2deg(np.angle(v))], 'residual':max(abs(F)), 'Q3':S[2].imag+b[2,3], 'slack': [S[0].real,S[0].imag]}
    write('reference_comparison.json',{'local_2010_named_case':local,'matacdc_independent':independent,'paper2010_ac_using_printed_Ps':acsolve(True),'paper2010_ac_only':acsolve(False)})
    write('author_inputs_mapped.json',auth)
    print(json.dumps(independent,default=lambda v:v.tolist() if isinstance(v,np.ndarray) else v,indent=2))

if __name__=='__main__':
    references();project()
