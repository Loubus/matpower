from pathlib import Path
import difflib
out=Path(__file__).resolve().parent; root=out.parent.parent
src=root/'outputs/cpf_solution_experiments_20260917'
sources=[root/'matpower/lib/runcpf_vsc_mtdc.m',src/'coupled_limit/exa_cpf.m',src/'continuation_limit/all_controls/b17a_cpf.m',src/'coupled_limit/combined_all_controls/exd_cpf.m']
snapshot='''            % Isolated NOSE guard: checkpoint before ANY trial control mutation.
            ng_stage=active_set_stage_snapshot(ctx,ctxt,Sdelta);
            ng_events=events;
            ng_misc={psse_controls_frozen,vsc_capability_transfer_frozen, ...
                vsc_capability_transfer_backoff_count,vsc_capability_resaturation_count, ...
                vsc_slack_q_backoff_count,gen_capability_dispatch_frozen, ...
                unified_context_cache,vsc_capability_param_cache,psse_diagnostic};
'''
guard='''                % Guard against silently crossing a turn during a control switch,
                % or reversing the full-state direction to force increasing lambda.
                ng_oldkeys=ng_state_keys(ng_stage.ctx); ng_newkeys=ng_state_keys(ctx);
                ng_zmap=zeros(numel(xnew)+1,1); ng_zmap(end)=z(end);
                [ng_match,ng_where]=ismember(ng_newkeys,ng_oldkeys);
                ng_zmap(find(ng_match))=z(ng_where(ng_match)); %#ok<FNDSB>
                ng_dot=dot(ng_zmap,znew)/max(norm(ng_zmap),eps);
                ng_alarm=active_set_changed && z(end)>0 && ...
                    (znew(end)<=0 || ng_dot<0);
                if strcmpi(stop_at,'NOSE') && ng_alarm
                    ng_rec=struct('last_lambda',lam,'pre_control_lambda',ng_raw_lam, ...
                        'post_control_lambda',lamnew,'trial_step',trial_step, ...
                        'tangent_before',z(end),'tangent_after',znew(end), ...
                        'orientation_dot',ng_dot,'G2_Q_before',last.gen(2,QG), ...
                        'G2_Q_pre_control',ng_raw_q,'G2_mode_before',last.bus(6,BUS_TYPE), ...
                        'G2_mode_after',r.bus(6,BUS_TYPE));
                    ng_history{end+1}=ng_rec;
                    % Restore every mutable study/control/cache field touched here.
                    [ctx,ctxt,Sdelta]=restore_active_set_stage_snapshot(ng_stage);
                    events=ng_events;
                    psse_controls_frozen=ng_misc{1};vsc_capability_transfer_frozen=ng_misc{2};
                    vsc_capability_transfer_backoff_count=ng_misc{3};vsc_capability_resaturation_count=ng_misc{4};
                    vsc_slack_q_backoff_count=ng_misc{5};gen_capability_dispatch_frozen=ng_misc{6};
                    unified_context_cache=ng_misc{7};vsc_capability_param_cache=ng_misc{8};psse_diagnostic=ng_misc{9};
                    ng_restored=isequaln(mpcb,ng_stage.mpcb)&&isequaln(mpct,ng_stage.mpct) ...
                        &&isequaln(cpf_policy_state,ng_stage.cpf_policy_state)&&isequaln(events,ng_events);
                    assert(ng_restored,'NOSE guard rollback mismatch');
                    ng_history{end}.rollback_verified=ng_restored;
                    if trial_step/2>=step_min && abs(ng_raw_lam-lam)>nose_tol
                        curr_step=trial_step/2;
                        continue;
                    end
                    ng_stop=struct('classification','control_transition_turn_bracket', ...
                        'lambda_low',lam,'lambda_high',ng_raw_lam, ...
                        'bracket_width',abs(ng_raw_lam-lam),'event_tolerance',nose_tol, ...
                        'within_event_tolerance',abs(ng_raw_lam-lam)<=nose_tol, ...
                        'refinements',numel(ng_history),'local_nose_certified',false);
                    ng_checkpoint=struct('stage',ng_stage,'x',x,'z',z,'last',last, ...
                        'lambda',lam,'raw_candidate_x',ng_raw_x,'raw_candidate_lambda',ng_raw_lam);
                    done_msg='Possible control-induced turn bracketed; smooth NOSE not certified.';
                    events=vsc_mtdc_cpf_append_event(events,vsc_mtdc_cpf_event( ...
                        'NOSE_SKIP_GUARD',cont_steps,1,done_msg));
                    failure=[];success=0;break;
                end
'''
helper='''    function keys=ng_state_keys(cc)
        m=cc.model;
        keys=["va:"+string(m.nonref(:));"vm:"+string(m.vm_vars(:)); ...
            "pac:"+string(m.pac_vars(:));"dc:"+string(m.dc_var(:))];
    end

'''
for k,p in enumerate(sources):
    old=p.read_text(); prefix=f'ng{k}'; s=old.replace(p.stem,prefix+'_cpf')
    needle='        nose_tol = mpopt.cpf.nose_tol;'
    assert s.count(needle)==1
    s=s.replace(needle,needle+'\n        ng_history={};ng_stop=[];ng_checkpoint=[];')
    needle='            ctx_hat = ctx;'
    assert s.count(needle)>=1;s=s.replace(needle,snapshot+needle,1)
    needle='                active_set_changed = 0;'
    assert s.count(needle)==1
    s=s.replace(needle,'                ng_raw_lam=lamnew;ng_raw_q=r.gen(2,QG);ng_raw_x=xnew;\n'+needle)
    needle='                nose_event = ~active_set_changed && isempty(target_lam) && ...'
    assert s.count(needle)==1;s=s.replace(needle,guard+needle)
    needle="        results.cpf.jacobian = 'analytic';"
    assert s.count(needle)==1
    s=s.replace(needle,needle+"\n        results.cpf.guard_history=ng_history;\n        results.cpf.guard_stop=ng_stop;\n        results.cpf.guard_checkpoint=ng_checkpoint;")
    needle="        if ~accepted && contains(trace.done_msg, 'PSS/E control') && ..."
    assert s.count(needle)==1
    s=s.replace(needle,"        if isfield(trace,'guard_stop') && ~isempty(trace.guard_stop)\n            r.cpf.termination.cause='control_transition_turn_bracket';\n            r.cpf.termination.success_scope='guard_stop_not_certified_nose';\n        end\n"+needle)
    needle='    function tf = unified_nose_event(z0, z1, tol)'
    assert s.count(needle)==1;s=s.replace(needle,helper+needle)
    (out/(prefix+'_cpf.m')).write_text(s)
    w=(root/'matpower/lib/runcpf_psse.m').read_text().replace('runcpf_psse',prefix+'_psse').replace('runcpf_vsc_mtdc',prefix+'_cpf')
    (out/(prefix+'_psse.m')).write_text(w)
    (out/(prefix+'.diff')).write_text(''.join(difflib.unified_diff(old.splitlines(True),s.splitlines(True),fromfile=str(p.relative_to(root)),tofile=prefix+'_cpf.m')))
print('Generated four isolated NOSE-guard solvers; original sources untouched.')
