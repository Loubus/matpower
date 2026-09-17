function m = vsc_station_map(row, baseMVA, elementMVA)
% VSC_STATION_MAP Exact linear station map, in per unit on elementMVA.
% For phasors us and is=conj(ss/us), positive current towards the grid:
%   uf = Fv*us + Fi*is; uc = D*us + E*is; ic = B*us + A*is.
% ic is the converter terminal current (including reactor charging).
% Supports filter G+jB, both branch pi shunts and transformer phase shift.
% No division by impedance: ideal zero-impedance limits are well defined.
% The network PF still requires nonzero explicit branch impedances.
if nargin < 3, elementMVA = baseMVA; end
c = idx_vsc;
k = elementMVA/baseMVA;
zt = complex(row(c.TR_R), row(c.TR_X))*k;
zr = complex(row(c.REACTOR_R), row(c.REACTOR_X))*k;
yf = complex(row(c.FILTER_G), row(c.FILTER_B))/k;
yt = 1j*row(c.TR_B)/(2*k);
yr = 1j*row(c.REACTOR_B)/(2*k);
tau = exp(1j*pi/180*row(c.TR_SHIFT));
Fv = (1+zt*yt)/tau;
Fi = zt*conj(tau);
Tv = yt/tau + yt*Fv;
Ti = conj(tau) + yt*Fi;
D = Fv + zr*(Tv+(yf+yr)*Fv);
E = Fi + zr*(Ti+(yf+yr)*Fi);
B = Tv+(yf+yr)*Fv+yr*D;
A = Ti+(yf+yr)*Fi+yr*E;
m = struct('A', A, 'B', B, 'D', D, 'E', E, 'Fv', Fv, ...
    'Fi', Fi, 'baseMVA', elementMVA, 'power_port', 'PCC');
end
