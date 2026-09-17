from pathlib import Path
exec(Path(__file__).with_name('edit_model.py').read_text().split("p='matpower/lib/runpf_vsc_mtdc_unified.m'")[0])
p='matpower/lib/vsc_capability_curve.m'; s=read(p)
s=s.replace('[sat, Ppu, Qpu, Spu, info_pu] = vsc_capability_geometry( ...\n    P / Sbase, Q / Sbase, 1, V, xEq, mode, Vmax);','''validateattributes(Smax, {'numeric'}, {'real','finite','scalar','positive'});
if isscalar(vsc_row)
    % Legacy scalar syntax means a filter-free, purely reactive station.
    row = zeros(1, c.REACTOR_RATE_C); row(c.REACTOR_X) = xEq;
    station = vsc_station_map(row, 1, 1);
else
    station = vsc_station_map(vsc_row, baseMVA, Sbase);
end
[sat, Ppu, Qpu, Spu, info_pu] = vsc_station_capability( ...
    P / Sbase, Q / Sbase, V, station, mode, Vmax);
info_pu.xEq = xEq;''')
start=s.index('%   VSC_ROW is a row'); end=s.index('%   When MODE',start)
s=s[:start]+'''%   P0/Q0 are PCC injections and V is the PCC voltage. Full station
%   transformer/reactor R+jX, filter G+jB, pi charging and phase shift map
%   PCC power to converter current and internal voltage. Zero impedances
%   are valid in this capability calculation. SMAX defines Imax=1 on its
%   element MVA base and retains the dispatch ceiling |P_PCC|<=SMAX.
%   If SMAX is empty, the minimum positive station branch rating is used.
%
'''+s[end:]
s=s.replace('info.source =', 'info.current_center = info_pu.current_center*Sbase;\ninfo.voltage_center = info_pu.voltage_center*Sbase;\ninfo.station_map = station;\ninfo.source =')
write(p,s)
# Remove voltage-terminal fallback: a missing PCC measurement is not Uc.
for p in ['matpower/lib/check_vsc_capability.m','matpower/lib/enforce_vsc_capability_active_set.m','matpower/lib/runcpf_vsc_mtdc.m']:
    s=read(p)
    import re
    s=re.sub(r'elseif size\(vsc(?:_result)?, 2\) >= c\.VAC_INTERNAL &&[^\n]*\n(?:[^\n]*\n){0,4}?\s*V = vsc(?:_result)?\(row, c\.VAC_INTERNAL\);\n', '', s)
    write(p,s)
# Never impose a fixed PCC active order on a DC reference converter.
p='matpower/lib/vsc_capability_policy.m'; s=read(p)
s=s.replace('target_if_p_changed = c.VSC_AC_PQ;', '''target_if_p_changed = c.VSC_AC_PQ;
if dc_mode == c.VSC_DC_VDC
    target_if_p_changed = c.VSC_AC_Q;
end''')
write(p,s)
