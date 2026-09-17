from pathlib import Path
exec(Path(__file__).with_name('edit_model.py').read_text().split("p='matpower/lib/runpf_vsc_mtdc_unified.m'")[0])
p='matpower/lib/runpf_vsc_mtdc.m';s=read(p)
s=s.replace('[~, ~, QG] = idx_gen;','[~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, ~, PT, QT] = idx_brch;')
s=s.replace('ac.branch(map.reactor_branch(k), 16)','ac.branch(map.reactor_branch(k), PT)').replace('ac.branch(map.reactor_branch(k), 17)','ac.branch(map.reactor_branch(k), QT)')
write(p,s)
p='matpower/lib/update_vsc_state.m';s=read(p).replace('[~, ~, QG] = idx_gen;\n','');write(p,s)
p='matpower/lib/calc_vsc_losses.m';s=read(p)
s=s.replace('Pac','Pconv').replace('Qac','Qconv').replace('Vac','Uconv')
s=s.replace('% Inputs PAC/QAC to this low-level helper are INTERNAL PCONV/QCONV,\n% not the public PCC result columns PAC/QAC. VAC is internal voltage.', '% Inputs PCONV/QCONV are INTERNAL terminal powers, not PCC PAC/QAC.\n% UCONV is the internal voltage; current is on the system MVA base.')
s=s.replace('BASEMVA, PAC, QAC, VAC, VSC','BASEMVA, PCONV, QCONV, UCONV, VSC')
write(p,s)
p='matpower/lib/runcpf_vsc_mtdc.m';s=read(p).replace('                else\n            V = vsc(row, c.VAC_SET);','        else\n            V = vsc(row, c.VAC_SET);');write(p,s)
# Clearly identify the changed power port in the earlier model comparison.
p='contraste_vsc_hvdc_psse.md';s=read(p)
s=s.replace('`PAC`, `PDC` y el balance `Pac + Pdc + Ploss = 0`','`PCONV`, `PDC` y el balance `Pconv + Pdc + Ploss = 0` (desde 2026-09-16 `PAC/QAC` son potencias en el PCC; ver [contrato PCC](docs/VSC_PCC_POWER_CONTRACT.md))')
write(p,s)
# Keep generated source mirrors consistent only for changed source files.
doc=ROOT/'matpower/docs/sphinx/source/matlab-source/matpower'
for p in (OUT/'before/matpower/lib').glob('*.m'):
    mirror=doc/p.name
    if mirror.exists(): write(mirror.relative_to(ROOT).as_posix(),read('matpower/lib/'+p.name))
