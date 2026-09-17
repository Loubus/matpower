"""Check report structure, saved arithmetic and inspected-input preservation."""
from pathlib import Path
import hashlib, json, csv, re
from pypdf import PdfReader
from PIL import Image, ImageOps
P=Path(__file__).resolve().parent
baseline=json.loads((P/'source_hashes_before.json').read_text(encoding='utf-8-sig'))
changed=[];missing=[]
for item in baseline:
    f=Path(item['Path'])
    if not f.exists():missing.append(str(f))
    elif hashlib.sha256(f.read_bytes()).hexdigest().upper()!=item['Hash']:changed.append(str(f))
preservation={'files_checked':len(baseline),'changed':changed,'missing':missing,'preserved':not changed and not missing,'scope':'Inspected MATLAB library, Beerten studies, docs and key historical evidence; recorded after first read-only diagnostic.'}
(P/'preservation_check.json').write_text(json.dumps(preservation,indent=2))
pages=json.loads((P/'report_content.json').read_text())
event=next(x for x in pages if x['title']=='Compact event and acceptance contract')
head,rows,_=next(v for t,v in event['blocks'] if t=='table')
with (P/'event_acceptance_table.csv').open('w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f);w.writerow(head);w.writerows(rows)
reader=PdfReader(P/'operational_limits_and_voltage_loadability.pdf')
assert len(reader.pages)==17
assert all(len(p.extract_text())>800 for p in reader.pages)
assert not changed and not missing
for page in pages:
    for typ,val in page['blocks']:
        if typ=='fig': assert (P/'figures'/f'{val[0]}.png').is_file()
        if typ=='eq': assert (P/'figures'/f'{val}.svg').is_file()
with (P/'diagnostic_points.csv').open(newline='') as f:points=list(csv.DictReader(f))
fail=[{'run':r['run'],'lambda':float(r['lambda_value']),'dispatch_error_MW':float(r['dispatch_error_MW'])} for r in points if abs(float(r['dispatch_error_MW']))>1e-7]
assert len(fail)==3 and abs(fail[-1]['dispatch_error_MW']+8)<1e-7
boundary=[r for r in points if r['run']=='run_boundary']
assert all(abs(float(r['dispatch_error_MW']))<1e-7 for r in boundary)
files=sorted((P/'qa').glob('page-*.png'))
for i in range(0,len(files),4):
    canvas=Image.new('RGB',(1240,1740),'#ccd7dd')
    for j,f in enumerate(files[i:i+4]):canvas.paste(ImageOps.contain(Image.open(f).convert('RGB'),(595,845)),((j%2)*620+10,(j//2)*870+20))
    canvas.save(P/'qa'/f'contact-{i//4+1}.png')
v={'pdf_pages':len(reader.pages),'illustrated_figures':8,'event_rows':len(rows),'saved_diagnostic_samples':len(points),'boundary_schedule_checks_pass':True,'dispatch_acceptance_failures_retained':fail,'production_preservation':preservation,'source_class_labels':'illustrative / code-derived / measured; historical separated','visual_qa':'Rendered by Poppler; pages inspected by assistant before delivery.','new_nose_validated':False,'new_complete_operational_margin_certified':False}
(P/'verification.json').write_text(json.dumps(v,indent=2))
print(json.dumps(v))
