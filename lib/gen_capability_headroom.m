function [margin, bounds] = gen_capability_headroom(P, Q, Smax, type)
%GEN_CAPABILITY_HEADROOM Signed P/Q headroom for the existing generic curve.
% Positive inside, zero at contact, negative outside. Units are MW/MVAr.
% Order: P minimum, P maximum, Q upper boundary, Q lower boundary.
% Unlike projection distance, these functions retain interior headroom.
[~,~,~,~,info] = gen_capability_curve(P,Q,Smax,type);
c = info.curve;
pmax = c.PC;
p = min(max(P,c.PA),pmax);
if info.gen_type_code == 3
    qmax = c.QB;
    if p <= c.PB
        qmax = c.QA+(c.QB-c.QA)*(p-c.PA)/(c.PB-c.PA);
    end
    qmin = -qmax;
else
    q0 = (c.QA^2-c.PB^2-c.QB^2)/(2*(c.QA-c.QB));
    radius = c.QA-q0;
    qmax = q0+sqrt(max(0,radius^2-p^2));
    qmin = c.QE;
    if p > c.PD
        qmin = c.QD+(c.QC-c.QD)*(p-c.PD)/(c.PC-c.PD);
    end
end
bounds = [c.PA; pmax; qmax; qmin];
margin = [P-c.PA; pmax-P; qmax-Q; Q-qmin];
end
