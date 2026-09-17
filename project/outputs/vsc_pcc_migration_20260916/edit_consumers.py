from pathlib import Path
exec(Path(__file__).with_name('edit_model.py').read_text().split("p='matpower/lib/runpf_vsc_mtdc_unified.m'")[0])
import re
# Bridge-balance/current tests must explicitly use the internal port.
for f in list((ROOT/'tests').glob('*.m'))+[ROOT/'matpower/lib/t/t_vsc_mtdc.m']:
    p=f.relative_to(ROOT).as_posix(); s=read(p); old=s
    s=re.sub(r'c\.PAC(?=\s+c\.PDC\s+c\.PLOSS)', 'c.PCONV', s)
    s=re.sub(r'(\w+\.vsc\([^\n]*?), c\.PAC\)( \+ \w+\.vsc\([^\n]*?, c\.PDC\))',r'\1, c.PCONV)\2',s)
    s=re.sub(r'hypot\(([^\n]*?),c\.PAC\),([^\n]*?),c\.QAC\)\)',r'hypot(\1,c.PCONV),\2,c.QCONV))',s)
    # Algebraic proxy generators live at the internal bus, not at the PCC.
    s=s.replace('r.vsc(proxy_vsc, [c.PAC c.QAC])','r.vsc(proxy_vsc, [c.PCONV c.QCONV])')
    if s!=old: write(p,s)
p='matpower/lib/vsc_capability_geometry.m'
write(p,'''function [sat, P, Q, S, info] = vsc_capability_geometry(P, Q, Smax, V, xEq, mode, Vmax)
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
''')
# Document physical power use where internal injections remain intentional.
p='matpower/lib/apply_vsc_ac_model.m'; s=read(p)
s=s.replace('%   the internal VSC AC bus using the sign convention from IDX_VSC.', '%   the internal VSC AC bus. STATE.pac/qac here are internal iteration\n%   variables; PAC_SET/QAC_SET and public PAC/QAC results are PCC powers.')
write(p,s)
p='matpower/lib/calc_vsc_losses.m'; s=read(p)
s=s.replace('% calc_vsc_losses -', '% calc_vsc_losses -')
s=s.replace('% ::', '% Inputs PAC/QAC to this low-level helper are INTERNAL PCONV/QCONV,\n% not the public PCC result columns PAC/QAC. VAC is internal voltage.\n% ::',1)
write(p,s)
