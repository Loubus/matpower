"""Instrument isolated solver copies; never edit production solver behavior."""
from pathlib import Path
import difflib
out=Path(__file__).resolve().parent
root=out.parent.parent
source=(root/'matpower/lib/runcpf_vsc_mtdc.m').read_text()
s=source.replace('    runcpf_vsc_mtdc(basecasedata, targetcasedata, mpopt, fname, solvedcase)', '    g150_cpf_probe(basecasedata, targetcasedata, mpopt, fname, solvedcase)',1)
start=s.index('    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_vsc_capability_controls')
end=s.index('    function [changed, bnext, tnext, report] = ...\n            unified_vsc_capability_update',start)
part=s[start:end]
def hook(kind):
    return f"        g150_log('append',struct('kind','{kind}','lambda',lam,'iteration',ctrl_it,'k',event_k,'bus',r.bus,'branch',r.branch,'gen',r.gen,'vsc',r.vsc,'report',report,'normF',normF));\n"
needle='                unified_vsc_capability_update(r, lam);\n'
assert part.count(needle)==1
part=part.replace(needle,needle+hook('before'))
needle="                profile_count('vsc_capability_recorr_failed_inner');\n"
part=part.replace(needle,needle+hook('inner_pf_failed')+"                g150_log('failure',struct('ctx',ctx,'ctxt',ctxt,'Sdelta',Sdelta,'x',x,'lambda',lam,'base',mpcb,'target',mpct,'options',mpopt_pf,'normF',normF));\n")
needle='            [r, ~] = stamp_original_ac_solution(r, bus_ids, nbranch, ngen);\n'
assert part.count(needle)==1
part=part.replace(needle,needle+hook('after_pf'))
needle='                if ~handoff_ok\n'
part=part.replace(needle,needle+hook('control_handoff_failed'))
needle='        V = original_ac_voltage_for_result(r, bus_ids);\n        success = 0;\n    end\n'
assert part.count(needle)==1
part=part.replace(needle,hook('iteration_budget_exhausted')+"        g150_log('failure',struct('ctx',ctx,'ctxt',ctxt,'Sdelta',Sdelta,'x',x,'lambda',lam,'base',mpcb,'target',mpct,'options',mpopt_pf,'normF',normF));\n"+needle)
s=s[:start]+part+s[end:]
start=s.index('    function [ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_gen_capability_controls')
end=s.index('    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_hvdc_derating_controls',start)
part=s[start:end]
needle='                unified_gen_capability_update(r, lam);\n'
assert part.count(needle)==1
part=part.replace(needle,needle+hook('gen_before'))
needle='            if ~ok\n'
assert part.count(needle)==1
part=part.replace(needle,needle+hook('gen_inner_pf_failed'))
part=part.replace('            if ~handoff_ok\n','            if ~handoff_ok\n'+hook('gen_handoff_failed'))
s=s[:start]+part+s[end:]
(out/'g150_cpf_probe.m').write_text(s)
wrapper=(root/'matpower/lib/runcpf_psse.m').read_text()
wrapper=wrapper.replace('    runcpf_psse(basecasedata, targetcasedata, mpopt, fname, solvedcase)','    g150_psse_probe(basecasedata, targetcasedata, mpopt, fname, solvedcase)',1)
wrapper=wrapper.replace('[results, success] = runcpf_vsc_mtdc(mpcb, mpct, mpopt,', '[results, success] = g150_cpf_probe(mpcb, mpct, mpopt,',1)
(out/'g150_psse_probe.m').write_text(wrapper)
(out/'instrumentation.diff').write_text(''.join(difflib.unified_diff(source.splitlines(True),s.splitlines(True),fromfile='production',tofile='isolated diagnostic copy')))
print('Created isolated diagnostic copies and instrumentation.diff')
audit=(root/'outputs/ultc_swshunt_cpf_20260916/audit_control_cpf.m').read_text()
audit=audit[audit.index('function [T,s]=audit('):].replace('function [T,s]=audit(', 'function [T,s]=g150_audit_trace(',1).replace('T.Pg2-80','T.Pg2-150')
(out/'g150_audit_trace.m').write_text(audit)
