"""Create an instrumented diagnostic copy, preserving the production solver."""
from pathlib import Path
import hashlib
import json

out = Path(__file__).resolve().parent
root = out.parent.parent
src = root / 'matpower/lib/runcpf_vsc_mtdc.m'
original = src.read_text(encoding='utf-8')
traced = original.replace('runcpf_vsc_mtdc(basecasedata,',
                          'runcpf_vsc_mtdc_batch1_trace(basecasedata,', 1)
assert traced != original
needle = '        tnext = copy_psse_control_fields(tnext, ac);'
assert traced.count(needle) == 1
traced = traced.replace(needle, needle + """
        global batch1_genq_trace;
        batch1_genq_trace{end+1} = struct('stage', 'apply_active_set', ...
            'current', current, 'auxiliary', ac, 'base_next', bnext, ...
            'target_next', tnext, 'gen_rows', gen_rows);
""")
needle = '        r = runpf_vsc_mtdc_unified(\'__results\', ctx, eval, mpc);'
assert traced.count(needle) == 1
traced = traced.replace(needle, needle + """
        global batch1_genq_trace;
        batch1_genq_trace{end+1} = struct('stage', 'build_result', ...
            'lambda', lam, 'current', mpc, 'context_case', ctx.mpc, ...
            'result', r);
""")
(out / 'runcpf_vsc_mtdc_batch1_trace.m').write_text(traced, encoding='utf-8')
files = [root / 'matpower/lib/runpf_vsc_mtdc_unified.m', src,
         root / 'matpower/lib/t/t_vsc_mtdc.m',
         root / 'matpower/lib/t/t_mpxt_psse.m']
record = {str(f.relative_to(root)): hashlib.sha256(f.read_bytes()).hexdigest()
          for f in files}
(out / 'source_hashes.json').write_text(json.dumps(record, indent=2)+'\n')
