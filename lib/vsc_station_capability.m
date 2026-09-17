function [sat, P, Q, S, info] = vsc_station_capability(P, Q, V, m, mode, Vmax)
% Exact PCC capability on the converter MVA base (Imax=1).
% |P|<=1 is the retained dispatch ceiling; |ic|<=1, |uc|<=Vmax.
% Affine phasor inequalities avoid division by small station impedances.
validateattributes(P, {'numeric'}, {'real','finite','scalar'});
validateattributes(Q, {'numeric'}, {'real','finite','scalar'});
validateattributes(V, {'numeric'}, {'real','finite','scalar','positive'});
validateattributes(Vmax, {'numeric'}, {'real','finite','scalar','positive'});
a = [m.A; m.E]/V; b = [m.B; m.D]*V; lim = [1; Vmax];
Pin=P; Qin=Q; tol=1e-10;
values = abs(a*complex(P,-Q)+b);
viol = [abs(P)>1+tol; values>lim+tol];
sat = any(viol); alpha = 1;
if sat
    if strcmp(mode, 'radial')
        lo=0; hi=1;
        if P~=0, hi=min(hi,1/abs(P)); end
        for k=1:2
            [l,h]=line_interval(a(k)*complex(P,-Q),b(k),lim(k));
            lo=max(lo,l); hi=min(hi,h);
        end
        if lo>hi || hi<0
            error('vsc_station_capability:radialInfeasible', ...
                'No feasible point on the requested radial P/Q path.');
        end
        alpha=max(0,min(1,hi)); P=alpha*P; Q=alpha*Q;
    elseif strcmp(mode, 'preservar_p')
        [ql,qh]=q_interval(P,a,b,lim);
        if abs(P)>1 || ql>qh
            [pl,ph]=p_interval(a,b,lim);
            P=min(max(P,pl),ph);
            [ql,qh]=q_interval(P,a,b,lim);
        end
        if ql>qh+tol
            error('vsc_station_capability:infeasible','Station capability region is empty.');
        end
        Q=min(max(Q,ql),qh); alpha=NaN;
    else
        error('vsc_station_capability: invalid projection mode');
    end
end
[ql,qh]=q_interval(P,a,b,lim);
fin=abs(a*complex(P,-Q)+b);
labels={'p','current','voltage_internal'};
label=strjoin(labels(viol),'+'); if isempty(label), label='none'; end
dist=(lim-values)./max(abs(a),eps);
centers=complex(NaN(2,1)); radii=inf(2,1);
nz=a~=0; centers(nz)=-conj(b(nz)./a(nz)); radii(nz)=lim(nz)./abs(a(nz));
S=hypot(P,Q);
info=struct('kind','vsc','mode',mode,'Smax',1,'V',V,'Vmax',Vmax, ...
    'P_original',Pin,'Q_original',Qin,'S_original',hypot(Pin,Qin), ...
    'P',P,'Q',Q,'S',S,'sat',sat,'saturaP',abs(P-Pin)>tol, ...
    'saturaQ',abs(Q-Qin)>tol,'inside_original',~sat, ...
    'inside_final',abs(P)<=1+tol && all(fin<=lim+tol), ...
    'active_limit',label,'violated_p',viol(1),'violated_current',viol(2), ...
    'violated_voltage',viol(3),'qMin',ql,'qMax',qh, ...
    'q_on_limit',min(abs(Q-[ql qh]))<1e-7,'pMax',1, ...
    'pFactible',NaN,'iMax',radii(1),'qCenter',-imag(centers(2)), ...
    'vRadius',radii(2),'margin',min([1-abs(Pin);dist]), ...
    'projection_norm',hypot(P-Pin,Q-Qin),'radial_scale',alpha, ...
    'current_center',centers(1),'voltage_center',centers(2), ...
    'converter_current_pu',values(1),'converter_voltage_pu',values(2), ...
    'projected_current_pu',fin(1),'projected_voltage_pu',fin(2), ...
    'power_port','PCC','formulation','full_station_affine');
if ~info.inside_final
    error('vsc_station_capability:projectionFailed','Projected point fails station constraints.');
end
end

function [lo,hi]=line_interval(d,e,r)
% Real t satisfying |d*t+e|<=r. Stable quadratic roots, also for d=0.
aa=abs(d)^2; bb=2*real(conj(e)*d); cc=abs(e)^2-r^2;
if aa==0
    if cc<=1e-13*max(1,r^2), lo=-Inf; hi=Inf;
    else, lo=Inf; hi=-Inf; end
    return;
end
disc=bb^2-4*aa*cc;
if disc < -1e-13*max([bb^2,abs(4*aa*cc),eps])
    lo=Inf; hi=-Inf; return;
end
disc=sqrt(max(0,disc));
if bb>=0, rr=-0.5*(bb+disc); else, rr=-0.5*(bb-disc); end
if rr==0, lo=0; hi=0;
else, roots=[rr/aa cc/rr]; lo=min(roots); hi=max(roots); end
end

function [lo,hi]=q_interval(p,a,b,lim)
lo=-Inf; hi=Inf;
for k=1:2
    [l,h]=line_interval(-1j*a(k),a(k)*p+b(k),lim(k));
    lo=max(lo,l); hi=min(hi,h);
end
end

function [pl,ph]=p_interval(a,b,lim)
% Projection of the convex disk intersection onto the P axis.
pl=-1; ph=1;
for k=1:2
    if a(k)==0
        if abs(b(k))>lim(k), error('vsc_station_capability:infeasible','Station capability region is empty.'); end
    else
        center=-conj(b(k)/a(k)); radius=lim(k)/abs(a(k));
        pl=max(pl,real(center)-radius); ph=min(ph,real(center)+radius);
    end
end
if pl>ph, error('vsc_station_capability:infeasible','Station capability region is empty.'); end
p0=min(max(0,pl),ph);
if gap(p0,a,b,lim)>0
    p0=fminbnd(@(p) gap(p,a,b,lim),pl,ph,optimset('TolX',1e-13));
end
if gap(p0,a,b,lim)>1e-10
    error('vsc_station_capability:infeasible','Station capability region is empty.');
end
if gap(pl,a,b,lim)>0
    lo=pl; hi=p0;
    for n=1:60
        mid=(lo+hi)/2;
        if gap(mid,a,b,lim)>0, lo=mid; else, hi=mid; end
    end
    pl=hi;
end
if gap(ph,a,b,lim)>0
    lo=p0; hi=ph;
    for n=1:60
        mid=(lo+hi)/2;
        if gap(mid,a,b,lim)>0, hi=mid; else, lo=mid; end
    end
    ph=lo;
end
end

function g=gap(p,a,b,lim)
[lo,hi]=q_interval(p,a,b,lim); g=lo-hi;
end
