"""Create an output-local solver copy adding observations only."""
from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[2];out=Path(__file__).resolve().parent/'final_04'
src=(r/'matpower/lib/runcpf_vsc_mtdc.m').read_text(encoding='utf-8')
text=src.replace('= runcpf_vsc_mtdc(', '= runcpf_vsc_mtdc_b6_diagnostic(',1)
start=text.index('    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_vsc_capability_controls')
end=text.index('    function [changed, bnext, tnext, report] = ...\n            unified_vsc_capability_update',start)
part=text[start:end]
part=part.replace('            if ~changed\n',"            b6_probe_record('update',lam,ctrl_it,normF,1,report);\n            if ~changed\n",1)
part=part.replace('            if ~ok\n',"            b6_probe_record('correction',lam,ctrl_it,normF,ok,report);\n            if ~ok\n",1)
part=part.replace('        success = 0;\n    end',"        b6_probe_record('iteration_limit',lam,max_it,normF,0,report);\n        success = 0;\n    end",1)
text=text[:start]+part+text[end:]
text+='''
function b6_probe_record(reason,lambda,iteration,residual,success,report)
global b6capdiag
entry=struct('reason',reason,'lambda',lambda,'iteration',iteration, ...
 'residual',residual,'success',success,'report',report);
if isempty(b6capdiag),b6capdiag=entry;else,b6capdiag(end+1)=entry;end
end
'''
(out/'runcpf_vsc_mtdc_b6_diagnostic.m').write_text(text,encoding='utf-8')
(out/'diagnostic_copy_manifest.json').write_text(json.dumps({'source_sha256':hashlib.sha256(src.encode()).hexdigest(),'diagnostic_sha256':hashlib.sha256(text.encode()).hexdigest(),'changes':['rename function','observe update, correction and exhaustion','append recorder; no changed decisions or tolerances']},indent=2))
