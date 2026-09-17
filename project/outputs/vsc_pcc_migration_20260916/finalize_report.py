from pathlib import Path
import json,re
out=Path(__file__).resolve().parent
p=out/'REPORT.md';s=p.read_text(encoding='utf-8')
expressions=['j0.0001','0.0015+j0.1121','G_f=B_f=0','G_f=0, B_f=0.0887',
 '0.0009615+j0.0399','0.0001+j0.16428','j0.0392','0.000785+j0.0399',
 'P_s=-60, Q_s=-40','P_s=35, Q_s=5','U_s=1, U_{dc}=1',r'i_c\ne i_s',
 r'P_s^2+Q_s^2\le(U_sI_{c,\max}S_b)^2']
for x in expressions:
    s=s.replace('('+x+')',r'\('+x+r'\)')
s=s.replace('0.887 kV with current in kA; requires base conversion',
 '0.887 kV; 0.148437591 MW/pu current on its AC base')
s=s.replace('2.885 Ω rectifier / 4.371 Ω inverter with current in kA',
 '2.885 / 4.371 Ω; 0.080795351 / 0.122411258 MW/pu current squared on its AC base')
p.write_text(s,encoding='utf-8')
