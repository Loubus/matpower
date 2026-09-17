function [sat, P, Q, S, info] = vsc_capability_geometry(P, Q, Smax, V, xEq, mode, Vmax)
% VSC_CAPABILITY_GEOMETRY Legacy scalar syntax for a filter-free station.
% P/Q are PCC powers on the caller's power base. xEq is purely reactive
% impedance on that base. Uses the same station engine as VSC_CAPABILITY_CURVE.
if nargin<6 || isempty(mode), mode='radial'; end
if nargin<7 || isempty(Vmax), Vmax=1.15; end
if ~isscalar(Smax) || ~isfinite(Smax) || Smax<=0
    error('vsc_capability_geometry: Smax must be positive');
end
if ~isscalar(V) || ~isfinite(V) || V<=0
    error('vsc_capability_geometry: V must be positive');
end
if ~isscalar(Vmax) || ~isfinite(Vmax) || Vmax<=0
    error('vsc_capability_geometry: Vmax must be positive');
end
validateattributes(xEq,{'numeric'},{'finite','scalar'});
[sat,P,Q,S,info]=vsc_capability_curve(P,Q,Smax,V,abs(xEq)*Smax,mode,Vmax,1);
end
