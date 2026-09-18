"""Create an isolated diagnostic copy; production source is never edited."""
from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
source = root / 'matpower/lib/runcpf_vsc_mtdc.m'
raw = source.read_bytes()
try:
    text = raw.decode('utf-8-sig')
except UnicodeDecodeError:
    text = raw.decode('cp1252')
text = text.replace('\r\n', '\n')
text = text.replace('    runcpf_vsc_mtdc(basecasedata,', '    runcpf_endpoint_probe(basecasedata,', 1)

def insert(anchor, replacement):
    global text
    assert text.count(anchor) == 1, (anchor, text.count(anchor))
    text = text.replace(anchor, replacement)

insert('        stage0 = active_set_stage_snapshot(ctx, ctxt, Sdelta);\n        switch lower(kind)', '''        global CPF_STOP_TRACE;
        if event_k >= 87 && strcmp(kind,'vsc')
            CPF_STOP_TRACE{end+1}=struct('tag','stage_enter','k',event_k, ...
                'step',trial_step,'lambda',lam,'residual',normF,'r',r, ...
                'mpcb',mpcb,'mpct',mpct,'ctx',ctx,'sd',Sdelta,'x',x);
        end
        stage0 = active_set_stage_snapshot(ctx, ctxt, Sdelta);
        switch lower(kind)''')
insert('        retry_step = [];\n        active_changed = active_changed || changed_any;', '''        if event_k >= 87 && strcmp(kind,'vsc')
            CPF_STOP_TRACE{end+1}=struct('tag','stage_exit','k',event_k, ...
                'step',trial_step,'lambda',lam,'success',success, ...
                'changed',changed_any,'r',r,'events',ev);
        end
        retry_step = [];
        active_changed = active_changed || changed_any;''')
insert("                unified_vsc_capability_update(r, lam);\n            if ~changed", """                unified_vsc_capability_update(r, lam);
            if event_k >= 87 && changed
                global CPF_STOP_TRACE;
                CPF_STOP_TRACE{end+1}=struct('tag','capability_update', ...
                    'k',event_k,'lambda',lam,'report',report,'r',r);
            end
            if ~changed""")
insert('        if kk==0 || ~isempty(target_lam)\n', '''        global CPF_STOP_TRACE;
        if kk >= 87
            CPF_STOP_TRACE{end+1}=struct('tag','transition_enter','k',kk, ...
                'lambda',ll0,'x',xx0);
        end
        if kk==0 || ~isempty(target_lam)
''')
insert('        if ok\n            transition_carried=nt;', '''        if kk >= 87
            CPF_STOP_TRACE{end+1}=struct('tag','transition_exit','k',kk, ...
                'lambda',ll,'residual',nn,'iterations',ii,'success',ok, ...
                'state_gap',norm([xx;ll]-[xx0;ll0],inf));
        end
        if ok
            transition_carried=nt;''')
(out/'runcpf_endpoint_probe.m').write_text(text, encoding='utf-8')
wrapper = (root/'matpower/lib/runcpf_psse.m').read_text(encoding='utf-8-sig')
wrapper = wrapper.replace('runcpf_psse(', 'runcpf_psse_endpoint_probe(', 1)
wrapper = wrapper.replace('= runcpf_vsc_mtdc(mpcb, mpct, mpopt,', '= runcpf_endpoint_probe(mpcb, mpct, mpopt,')
(out/'runcpf_psse_endpoint_probe.m').write_text(wrapper, encoding='utf-8')
(out/'instrumentation_provenance.json').write_text(json.dumps({
    'source': str(source), 'source_sha256': hashlib.sha256(raw).hexdigest(),
    'copy': 'runcpf_endpoint_probe.m',
    'changes': 'Rename entry point; add read-only diagnostic snapshots only. No numerical equations, options, controls or policies changed.'
}, indent=2), encoding='utf-8')
print('Created isolated instrumented copy.')
