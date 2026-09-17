"""Bounded independent fixed-state and binding-boundary diagnostics.
No automatic control choice or solver policy replacement is performed.
"""
import copy,json
import numpy as np
from scipy.optimize import root,brentq
from independent_validation import Circuit,OUT,TRACE,write,INPUT

data=json.loads((TRACE/'capability_step_100.json').read_text());points=data['points']
base=np.array(INPUT['base']['bus']);delta=np.array(INPUT['target']['bus'])[:,2:4]-base[:,2:4]

def at_lambda(pt,lam):
    p=copy.deepcopy(pt['case']);b=np.array(p['bus']);b[:,2:4]=base[:,2:4]+lam*delta;p['bus']=b.tolist();return p

events=[]
for k in range(1,len(points)):
    old,new=points[k-1],points[k]
    genchanged=np.array(old['case']['bus'])[5,1]!=np.array(new['case']['bus'])[5,1]
    vscchanged=np.array(old['vsc'])[1,3]!=np.array(new['vsc'])[1,3]
    if not(genchanged or vscchanged):continue
    mode='generator2' if genchanged else 'converter2'
    def margin(lam):
        cir=Circuit(at_lambda(old,lam));st,meta=cir.solve(old)
        assert meta['residual']<1e-8
        if genchanged:return 100*(np.sqrt(1.7**2-.4**2)-.9)-st[2][5].imag
        return 150*abs(st[0][cir.maps[1][0]])-abs(st[4][1])
    a,b=old['lambda'],new['lambda'];margins=[margin(a),margin(b)]
    crossing=brentq(margin,a,b,xtol=1e-12) if margins[0]*margins[1]<=0 else None
    samples=[]
    if crossing is not None:
        for offset in [-1e-4,0,1e-4]:
            lam=crossing+offset
            for label,pt in [('before_state',old),('after_state',new)]:
                cir=Circuit(at_lambda(pt,lam));st,meta=cir.solve(pt)
                meta.update(lambda_value=lam,state=label,V5=abs(st[0][4]),V3=abs(st[0][2]),Qgen2=st[2][5].imag,converter2_Q=st[4][1].imag)
                samples.append(meta)
    events.append({'device':mode,'bracket':[a,b],'margins':margins,'crossing_fixed_previous_controls':crossing,'samples':samples})

# Direct solve with the same implemented converter circle as an equality.
# This tests whether a root exists just beyond the stop; it does not certify
# the slack or define a replacement automatic capability policy.
last=points[-1];boundary=[]
for lam in [last['lambda'],1.13853,1.13854,1.1386,1.139,1.14]:
    cir=Circuit(at_lambda(last,lam));v,d=cir.point_voltage(last);x0=cir.xfrom(v,d)
    row=2*(cir.n-1)+4*1+3  # converter 2's Q control equation
    def fun(x):
        f=cir.fun(x);st=cir.state(x);vp=abs(st[0][cir.maps[1][0]])
        f[row]=(abs(st[4][1])-150*vp)/cir.base
        return f
    sol=root(fun,x0,options={'xtol':1e-10});f=fun(sol.x);st=cir.state(sol.x)
    # Central-difference singular value, to distinguish flat/ill-conditioned roots.
    eye=np.eye(len(sol.x))*1e-6
    J=np.column_stack([(fun(sol.x+e)-fun(sol.x-e))/(2e-6) for e in eye])
    boundary.append({'lambda':lam,'success':bool(sol.success),'residual':max(abs(f)), 'V5':abs(st[0][4]),'V3':abs(st[0][2]),'Q2':st[4][1].imag,'sigma_min':np.linalg.svd(J,compute_uv=False)[-1]})
write('transition_diagnostics.json',{'crossings':events,'binding_circle_diagnostic':boundary})
print(json.dumps({'crossings':[(e['device'],e['crossing_fixed_previous_controls']) for e in events],'boundary':boundary},indent=2))

# Augmented fold equations F(x,lambda)=0, J*v=0, v'*v=1 for
# the converter-circle diagnostic only. No use of project CPF equations.
cir=Circuit(at_lambda(last,1.138532));v,d=cir.point_voltage(last);x0=cir.xfrom(v,d)
def ff(x,lam):
    cir.b[:,2:4]=base[:,2:4]+lam*delta
    f=cir.fun(x);st=cir.state(x);f[row]=(abs(st[4][1])-150*abs(st[0][cir.maps[1][0]]))/100
    return f
def jac(x,lam):
    eye=np.eye(len(x))*1e-5
    return np.column_stack([(ff(x+e,lam)-ff(x-e,lam))/(2e-5) for e in eye])
_,_,vh=np.linalg.svd(jac(x0,1.138532));n=len(x0)
def augmented(y):
    x=y[:n];lam=y[n];z=y[n+1:]
    return np.r_[ff(x,lam),jac(x,lam)@z,z@z-1]
sol=root(augmented,np.r_[x0,1.138532,vh[-1]],options={'xtol':1e-9})
y=sol.x;ff(y[:n],y[n]);st=cir.state(y[:n]);J=jac(y[:n],y[n]);sv=np.linalg.svd(J,compute_uv=False)
fold={'solver_success':bool(sol.success),'message':sol.message,'lambda':y[n],'equation_residual':max(abs(ff(y[:n],y[n]))),'augmented_residual':max(abs(augmented(y))), 'sigma_min':sv[-1], 'V5':abs(st[0][4]), 'V3':abs(st[0][2]), 'Qconverter2':st[4][1].imag, 'slack_P':st[2][0].real,'scope':'Independent fold of fixed taps/shunts, fixed generator Q and implemented converter circle; all-equipment infeasible.'}
write('binding_circle_fold.json',fold);print(json.dumps(fold,indent=2))

# Five-point derivatives reduce roundoff amplification from small station X.
# Keep the same 1e-8 residual acceptance gate; retain the first estimate above.
refinements=[]
for h in [1e-3,5e-4]:
    def jac(x,lam):
        eye=np.eye(len(x))*h
        return np.column_stack([(-ff(x+2*e,lam)+8*ff(x+e,lam)-8*ff(x-e,lam)+ff(x-2*e,lam))/(12*h) for e in eye])
    sr=root(augmented,y,options={'xtol':1e-9});y=sr.x;F=ff(y[:n],y[n]);J=jac(y[:n],y[n]);st=cir.state(y[:n]);U,sv,Vh=np.linalg.svd(J)
    z=y[n+1:];h2=1e-3;fl=(ff(y[:n],y[n]+h2)-ff(y[:n],y[n]-h2))/(2*h2)
    fxx=(ff(y[:n]+h2*z,y[n])-2*F+ff(y[:n]-h2*z,y[n]))/h2**2
    refinements.append({'h':h,'solver_success':bool(sr.success),'lambda':y[n],'equation_residual':max(abs(F)),'augmented_residual':max(abs(augmented(y))),'V5':abs(st[0][4]),'sigma_min':sv[-1],'left_null_dot_Flambda':U[:,-1]@fl,'left_null_dot_Fxx':U[:,-1]@fxx})
write('binding_circle_fold_refinements.json',refinements);print(json.dumps(refinements,indent=2))
