from pathlib import Path
import re,difflib,hashlib,json
root=Path.cwd(); out=root/'outputs/cpf_solution_experiments_20260917/continuation_limit'
src=root/'matpower/lib/runcpf_vsc_mtdc.m'; s=src.read_text(); original=s
s=s.replace('runcpf_vsc_mtdc(', 'b17_cpf(')
s=s.replace('vsc_capability_recorded_idx = [];','vsc_capability_recorded_idx = [];\nb17_carried = []; b17_carried_keys = strings(0,1);',1)
s=s.replace('            ctx_hat = ctx;','            b17_carried = []; b17_carried_keys = strings(0,1);\n            ctx_hat = ctx;',1)
# Add lambda output to every VSC settlement signature/call (six contexts).
p=re.compile(r'(\[ctx, ctxt, Sdelta, x, (?:eval|~), )(normF|~)(, iterations|, pf_it)(, (?:r|base), V, \.\.\.\s*[^\n]*\]\s*=\s*(?:\.\.\.\s*)?settle_unified_vsc_capability_controls)')
s,n=p.subn(r'\1lam, \2\3\4',s)
print('lambda direct patterns',n)
# Function header has separate line declaration before function name.
s=s.replace('function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_vsc_capability_controls', 'function [ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_vsc_capability_controls')
# stage dispatcher split call may be matched above, verify after.
for stage,nextmark in [('vsc','    function [changed, bnext, tnext, report] = ...\n            unified_vsc_capability_update'),('gen','    function [ctx, ctxt, Sdelta, x, eval, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_hvdc_derating_controls')]:
 start=s.index('    function [ctx, ctxt, Sdelta, x, eval, lam, normF, iterations, r, V, ...\n            ev, success, changed_any] = ...\n            settle_unified_'+stage+'_capability_controls')
 end=s.index(nextmark,start); body=s[start:end]
 needle='            [changed, mpcb_next, mpct_next, report] = ...'
 body=body.replace(needle,"            b17_oldctx = ctx;\n            b17_direction = b17_incoming_direction(ctx, Sdelta, x, lam, event_k);\n"+needle,1)
 old='            [x, eval, normF, it, ok] = ...\n                solve_unified_pf_at_lambda(ctx, x0, lam, Sdelta);'
 assert old in body
 body=body.replace(old,"            [x, lam, eval, normF, it, ok] = ...\n                b17_transition_corrector(b17_oldctx, ctx, Sdelta, x0, lam, ...\n                    b17_direction, event_k, '"+stage+"');",1)
 body=body.replace('re-corrected unified VSC-MTDC point at fixed lambda.', 're-corrected unified point on incoming CPF hyperplane (experimental).')
 if stage=='gen':
  # Do not silently fall back to old fixed-lambda event retry.
  body=body.replace('            if ~ok && localized','            if ~ok && localized && event_k == 0')
 s=s[:start]+body+s[end:]
insert=r'''
    function b17_t = b17_incoming_direction(b17_ctx, b17_sd, b17_x, b17_lam, b17_k)
        b17_t = zeros(length(b17_x)+1,1); b17_t(end)=1;
        if b17_k == 0, return; end
        b17_prior = unified_x_from_controlled_ac(b17_ctx, last.ac, last);
        b17_seed = [b17_x-b17_prior; b17_lam-last_lam];
        if norm(b17_seed) < 1e-10
            if length(z)==length(b17_t), b17_seed=z; else, b17_seed=b17_t; end
        end
        b17_seed=b17_seed/norm(b17_seed);
        b17_t=unified_cpf_tangent(b17_ctx,b17_x,b17_lam,b17_sd,...
            b17_seed,b17_x,b17_lam,3,1);
        if dot(b17_t,b17_seed)<0, b17_t=-b17_t; end
    end

    function b17_keys = b17_state_keys(b17_ctx)
        m=b17_ctx.model;
        b17_keys=["va:"+string(m.nonref(:)); "vm:"+string(m.vm_vars(:)); ...
            "pac:"+string(m.pac_vars(:)); "dc:"+string(m.dc_var(:))];
    end

    function [xx,ll,ee,nn,ii,ok] = b17_transition_corrector(oc,nc,sd,xx0,ll0,tt,kk,stage)
        if kk==0 || ~isempty(target_lam)
            [xx,ee,nn,ii,ok]=solve_unified_pf_at_lambda(nc,xx0,ll0,sd);
            ll=ll0; return;
        end
        ko=b17_state_keys(oc); kn=b17_state_keys(nc);
        nt=zeros(length(xx0)+1,1); nt(end)=tt(end);
        [matched,where]=ismember(kn,ko); nt(find(matched))=tt(where(matched)); %#ok<FNDSB>
        nt=nt/norm(nt);
        % The old corrected candidate anchors a transverse hyperplane. New
        % Q-fixed branch is corrected with lambda free; no arbitrary retreat.
        [xx,ll,ee,nn,ii,ok]=unified_cpf_corrector(nc,sd,xx0,ll0,xx0,ll0,nt,0,3);
        rr=struct('stage',stage,'candidate_index',kk,'lambda_before',ll0, ...
            'lambda_after',ll,'lambda_shift',ll-ll0,'incoming_lambda_tangent',nt(end), ...
            'hyperplane_residual',nt'*([xx;ll]-[xx0;ll0]),'residual',nn, ...
            'iterations',ii,'success',ok,'state_size_before',length(ko), ...
            'state_size_after',length(kn),'state_correction_norm',norm(xx-xx0));
        b17_journal('append',rr);
        if ok
            b17_carried=nt; b17_carried_keys=kn;
        end
    end

'''
old_reset='''                    zseed = zeros(length(xnew) + 1, 1);
                    zseed(end) = direction;
                    znew = unified_cpf_tangent(ctx, xnew, lamnew, Sdelta, ...
                        zseed, xnew, lamnew, 1, direction);'''
new_reset='''                    if ~isempty(b17_carried)
                        b17_kn=b17_state_keys(ctx);
                        zseed=zeros(length(xnew)+1,1); zseed(end)=b17_carried(end);
                        [b17_matched,b17_where]=ismember(b17_kn,b17_carried_keys);
                        zseed(find(b17_matched))=b17_carried(b17_where(b17_matched)); %#ok<FNDSB>
                        zseed=zseed/norm(zseed);
                        znew=unified_cpf_tangent(ctx,xnew,lamnew,Sdelta,...
                            zseed,xnew,lamnew,3,1);
                        if dot(znew,zseed)<0, znew=-znew; end
                    else
                        zseed = zeros(length(xnew) + 1, 1);
                        zseed(end) = direction;
                        znew = unified_cpf_tangent(ctx, xnew, lamnew, Sdelta, ...
                            zseed, xnew, lamnew, 1, direction);
                    end'''
assert old_reset in s
s=s.replace(old_reset,new_reset,1)
s=s.replace('    function [x, eval, normF, iterations, success] = ...\n            solve_unified_pf_at_lambda',insert+'    function [x, eval, normF, iterations, success] = ...\n            solve_unified_pf_at_lambda',1)
(out/'b17_cpf.m').write_text(s)
p=(root/'matpower/lib/runcpf_psse.m').read_text().replace('runcpf_psse(', 'b17_psse(').replace('runcpf_vsc_mtdc(', 'b17_cpf(')
(out/'b17_psse.m').write_text(p)
(out/'implementation.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='production/runcpf_vsc_mtdc.m',tofile='experiment/b17_cpf.m')))
(out/'source_sha256.json').write_text(json.dumps({str(src.relative_to(root)):hashlib.sha256(src.read_bytes()).hexdigest()},indent=2))
