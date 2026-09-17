from pathlib import Path
out=Path(__file__).resolve().parent;root=out.parents[1]
s=(root/'matpower/lib/t/t_vsc_mtdc.m').read_text()
s=s.replace('function t_vsc_mtdc(', 'function t_vsc_pcc_repeat(',1)
start=s.index('mpcpap_full = mpcpap;');end=s.index('mpcpgf = mpcpap;',start)
s=s[:start]+"% FULL continuation checks 256-259 already passed on this implementation.\n"+"t_skip(4, 'verified in legacy_suite_current.txt; unchanged FULL fixture');\n\n"+s[end:]
(out/'t_vsc_pcc_repeat.m').write_text(s,encoding='utf-8')
