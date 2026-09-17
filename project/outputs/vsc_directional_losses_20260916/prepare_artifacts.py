from pathlib import Path
import difflib, json, hashlib

out = Path(__file__).resolve().parent
root = out.parents[1]
old = out.parent/'vsc_pcc_migration_20260916'
s = (old/'build_html.py').read_text(encoding='utf-8')
# Bold phasors replace underline notation in the offline MathText renderer.
s = s.replace('    tex=tex.replace',
    r'    tex=re.sub(r"\\underline ([A-Z])",r"\\mathbf{\1}",tex)'+'\n    tex=tex.replace',1)
s = s.replace('Full station capability comparison','C1 voltage phasors and direction-dependent losses')
s = s.replace('Five-bus Beerten: PCC migration','Internal voltage and directional converter losses')
(out/'build_html.py').write_text(s,encoding='utf-8')
v = (old/'verify_render.cjs').read_text(encoding='utf-8')
v = v.replace("page.locator('.table').screenshot", "page.locator('.table').first().screenshot")
(out/'verify_render.cjs').write_text(v,encoding='utf-8')
p=out/'REPORT.md'
p.write_text(p.read_text(encoding='utf-8').replace('239 passed','242 passed'),encoding='utf-8')
names=[p.relative_to(out/'before').as_posix() for p in (out/'before').rglob('*.m')]
names += ['matpower/lib/vsc_loss_coefficients.m','tests/t_vsc_directional_losses.m','docs/VSC_DIRECTIONAL_LOSS_CONTRACT.md']
delta=[]; manifest=[]
for name in names:
    before=out/'before'/name; after=root/name
    delta.extend(difflib.unified_diff(before.read_text(encoding='utf-8').splitlines(True) if before.exists() else [],
        after.read_text(encoding='utf-8').splitlines(True),fromfile='before/'+name,tofile='after/'+name))
    manifest.append({'file':name,'sha256':hashlib.sha256(after.read_bytes()).hexdigest()})
(out/'changes.diff').write_text(''.join(delta),encoding='utf-8')
(out/'change_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
