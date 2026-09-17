from pathlib import Path
import hashlib,json,difflib
p=Path(__file__).resolve().parent
src=p/'combined';out=p/'combined_all_controls';out.mkdir(exist_ok=True)
for name in ['exc_pf.m','exc_psse.m','exc_log.m','exc_transition_journal.m','exc_audit_trace.m','exc_run.m']:
    (out/name.replace('exc_','exd_')).write_text((src/name).read_text().replace('exc_','exd_'))
original=(src/'exc_cpf.m').read_text()
s=original.replace('exc_','exd_')
a='            b17_carried = []; b17_carried_keys = strings(0,1);'
b='''            % AB2: carry the last accepted physical tangent across EVERY stage.
            % A failed trial restarts here from the restored accepted context.
            b17_carried = z; b17_carried_keys = b17_state_keys(ctx);'''
assert s.count(a)==1;s=s.replace(a,b)
a='                        if dot(znew,zseed)<0, znew=-znew; end'
b=a+'''
                        exd_log('append',struct('kind','outgoing_orientation', ...
                            'candidate_index',cont_steps+1,'lambda',lamnew, ...
                            'incoming_lambda_tangent',zseed(end),'outgoing_lambda_tangent',znew(end), ...
                            'orientation_dot',dot(znew,zseed),'matched_states',sum(b17_matched), ...
                            'new_states',numel(b17_kn)-sum(b17_matched),'tap9',r.branch(9,9)));
'''
assert s.count(a)==1;s=s.replace(a,b)
(out/'exd_cpf.m').write_text(s)
(out/'all_controls.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='combined/exc_cpf.m',tofile='combined_all_controls/exd_cpf.m')))
(out/'source_sha256.json').write_text(json.dumps({str(src/'exc_cpf.m'):hashlib.sha256((src/'exc_cpf.m').read_bytes()).hexdigest()},indent=2))
print('AB2 ready: exd_run(.1), exd_run(.05); original 200-step budget, no release change.')

