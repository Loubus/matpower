from pathlib import Path
exec(Path(__file__).with_name('edit_model.py').read_text().split("p='matpower/lib/runpf_vsc_mtdc_unified.m'")[0])
for p in ['cases/beerten/variants/case5_vsc_mtdc_beerten.m','matpower/data/case5_vsc_mtdc_beerten.m']:
    s=read(p).replace('% This case reproduces the data used for the 5-bus, 3-terminal VSC-MTDC', '% This case is a simplified reconstruction of the 5-bus, 3-terminal VSC-MTDC')
    s=s.replace('% Pac + Pdc + Ploss = 0.', '% Pconv + Pdc + Ploss = 0 (Pac/Qac are measured at the PCC).')
    write(p,s)
p='matpower/lib/savecase.m'; s=read(p)
s=s.replace("'tr_branch', 'reactor_branch'};", "'tr_branch', 'reactor_branch', 'Pconv', 'Qconv'};")
write(p,s)
for p in ['matpower/lib/make_vsc_hvdc_pac_dispatch_target.m','matpower/lib/make_vsc_hvdc_dispatch_target.m']:
    s=read(p); s=s.replace('% ::','% PAC_SET/QAC_SET schedules are measured at the PCC; positive means\n% injection into the AC grid. PDC_SET remains a DC-terminal schedule.\n% ::',1); write(p,s)
# Existing rendered-source mirrors are documentation, not alternate solvers.
doc=ROOT/'matpower/docs/sphinx/source/matlab-source/matpower'
for p in (OUT/'before/matpower/lib').glob('*.m'):
    mirror=doc/p.name
    if mirror.exists(): write(mirror.relative_to(ROOT).as_posix(),read('matpower/lib/'+p.name))
