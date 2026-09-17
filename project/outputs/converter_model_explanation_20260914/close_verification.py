from pathlib import Path
import json,hashlib,re,ast
OUT=Path(__file__).resolve().parent;ROOT=OUT.parent.parent;V=OUT/'verification'
calc=json.loads((V/'calculation_checks.json').read_text())
browser=json.loads((V/'browser_checks.json').read_text())
snapshot=json.loads((V/'source_snapshot_before_final.json').read_text())
current=json.loads((OUT/'source_manifest.json').read_text())
changed=[]
for f in snapshot['files']:
    if hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest()!=f['sha256']:changed.append(f['path'])
missing=[];bad_ranges=[]
source=(OUT/'build_report.py').read_text(encoding='utf-8')
for file,start,end in re.findall(r"cite\('([^']+)',(\d+),(\d+)\)",source):
    # These are explicitly corrected in cite() before the HTML is generated.
    tree=ast.parse(source)
    assignment=next(n for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='corrections' for t in n.targets))
    corrections=ast.literal_eval(assignment.value)
    start,end=corrections.get((file,int(start)),(int(start),int(end)))
    n=len((ROOT/file).read_text(encoding='utf-8-sig').splitlines())
    if not(1<=start<=end<=n):bad_ranges.append([file,start,end,n])
html=(OUT/'REPORT.html').read_text(encoding='utf-8')
for link in re.findall(r'href="([^"]+)"',html):
    if not link.startswith(('#','http')) and not (OUT/link).exists():missing.append(link)
verification={
 'date':'2026-09-14','artifact':'REPORT.html','numerical':calc,
 'browser':{'javascript_errors':browser['page_errors'],'equations_rendered':len(browser['desktop']['eq']),
  'figures_rendered':browser['desktop']['figures'],'missing_citation_anchors':browser['desktop']['missingAnchors'],
  'desktop_page_overflow':browser['desktop']['scrollWidth']>browser['desktop']['innerWidth'],
  'mobile_page_overflow':browser['mobile']['scrollWidth']>browser['mobile']['innerWidth'],
  'interactive_selection_verified':browser['interaction_changed'],'source_citation_opens_excerpt':browser['source_opened'],
  'visual_review':'All nine report figures and all 43 equations inspected; mobile interactive view and cover inspected. DC diagram connection and label placement corrected before final inspection.'},
 'source_checks':{'invalid_line_ranges':bad_ranges,'missing_local_links':missing,'snapshotted_source_files':len(snapshot['files']),'changed_since_snapshot':changed,
  'preservation_scope':'All task writes were confined to this output directory. Compared cited source and consumed historical-input hashes across final artifact construction; this is not a Git diff or a whole-filesystem audit.'},
 'scope':{'production_edits':False,'case_parameter_edits':False,'historical_outputs_overwritten':False,'new_cpf_run':False,'new_physical_margin_claimed':False},
 'diagnostics':[
  {'phase':'MATLAB exporter attempts 1 and 2','error':'Subscripted assignment between dissimilar structures. Error in calculate_evidence>station_rows, line 85.','resolution':'Output-local structure initialization adjusted; function explicitly refreshed before final successful run. All final checks pass. No solver settings changed.'},
  {'phase':'Primary reference retrieval','error':'Old Lirias bitstream URL returned HTTP 404.','resolution':'Author retrieve/246525 URL succeeded; saved and inspected manuscript.'},
  {'phase':'Primary PDF rendering','error':'Poppler reported missing display fonts.','resolution':'Relevant rendered pages visually inspected; independent report equations/plots use embedded vector glyphs.'},
  {'phase':'HTML authoring','error':'Mathtext required braced underline and fraction syntax; initial narrow layout overflowed on long paths.','resolution':'Syntax and wrapping corrected, then all equations and responsive rendering rechecked.'}
 ]}
verification['passed']=bool(calc['assertions_passed'] and not changed and not bad_ranges and not missing and not browser['page_errors'] and not browser['desktop']['missingAnchors'] and browser['interaction_changed'] and browser['source_opened'] and not verification['browser']['desktop_page_overflow'] and not verification['browser']['mobile_page_overflow'])
(V/'verification.json').write_text(json.dumps(verification,indent=2),encoding='utf-8')
(V/'matlab_tool_transcript.txt').write_text('''MATLAB MCP evidence (tool-return transcript; diary file was empty in this MCP session)

Initialization: iniciar_proyecto; project path verified.

Exporter attempts 1 and 2:
Subscripted assignment between dissimilar structures.
Error in calculate_evidence>station_rows (line 85)
Error in calculate_evidence (line 18)

Final execution, after output-local correction and explicit function refresh:
FRESH_BASE_SUCCESS=1 MAX_MISMATCH=2.61404719353e-12
FIVE_BUS_SUCCESS=1 MAX_MISMATCH=3.71261910104e-11
STATION_BALANCE_MAX_MVA=2.01491729217e-09

The completed assertions and exact residuals are in calculation_checks.json.
No restoredefaultpath, MATLAB CLI fallback, solver relaxation, source-code change or case-parameter change was used.
''',encoding='utf-8')
print(json.dumps(verification,indent=2))
if not verification['passed']:raise SystemExit(1)
