function evidence=t_cpf_checkpoint_replay(base,target,options,outdir)
% Verify rewind recovery, unchanged non-replay behavior and bounded policy.
if ~isfolder(outdir),mkdir(outdir);end
checks=struct('name',{},'passed',{});runs=cell(1,6);summary=cell(1,6);
names={'off_disabled','off_nose','on_nose','off_full','on_full','off_one_retry'};
for k=1:6
    mode='NOSE';if ismember(k,[4 5]),mode='FULL';end
    coupled=ismember(k,[3 5]);limit=3;if k==1,limit=0;elseif k==6,limit=1;end
    o=mpoption(options,'cpf.stop_at',mode,'cpf.step',.1, ...
        'vsc_mtdc.coupled_current_limits',coupled,'vsc_mtdc.nose_replay_max',limit);
    file=fullfile(outdir,[names{k} '.mat']);assert(~isfile(file),'Preserve verification outputs');
    lastwarn('');tic;[r,success]=runcpf_psse(base,target,o);elapsed=toc;
    [warning_text,warning_id]=lastwarn;
    save(file,'r','success','base','target','o','elapsed','warning_text','warning_id','-v7.3');runs{k}=r;
    ck([names{k} '_bounded'],r.cpf.checkpoint_replay.attempts<=limit);
    summary{k}=struct('name',names{k},'lambda',r.cpf.lam(end),'V5',r.bus(5,8), ...
        'termination',r.cpf.termination,'replay',r.cpf.checkpoint_replay, ...
        'warning',warning_text,'elapsed',elapsed);
    fprintf('%s: lambda %.12f endpoint %d replays %d cause %s\n',names{k}, ...
        r.cpf.lam(end),r.cpf.termination.requested_endpoint_reached, ...
        r.cpf.checkpoint_replay.attempts,r.cpf.termination.cause);
end
a=runs{1};b=runs{2};rec=b.cpf.checkpoint_replay;
ck('disabled_preserves_honest_failure',~a.success && strcmp(a.cpf.termination.cause,'turn_localization_failed') && ~a.cpf.termination.nose_detected);
ck('replay_recovers_NOSE',b.success && b.cpf.termination.requested_endpoint_reached && b.cpf.termination.smooth_nose_detected);
ck('actual_rewind_exercised',rec.attempts>=1 && rec.history{1}.discarded_points>0);
ck('restoration_verified',all(cellfun(@(s)s.restoration_verified,rec.history)));
n=rec.history{1}.checkpoint_index;
ck('prefix_lambda_preserved',isequaln(a.cpf.lam(1:n),b.cpf.lam(1:n)));
for field={'bus','gen','branch','vsc','busdc','branchdc'}
    name=field{1};ck(['prefix_' name '_preserved'],isequaln(a.cpf.(name)(:,:,1:n),b.cpf.(name)(:,:,1:n)));
    ck(['trace_' name '_aligned'],size(b.cpf.(name),3)==numel(b.cpf.lam));
end
ck('exact_halving',all(cellfun(@(s)s.step_cap==s.previous_step_cap/2,rec.history)));
ck('one_retry_budget_is_sufficient',runs{6}.success && runs{6}.cpf.checkpoint_replay.attempts==1);
ck('budget_does_not_change_successful_replay',isequaln(runs{6}.cpf.lam,b.cpf.lam));
ck('on_NOSE_needs_no_replay',runs{3}.cpf.termination.requested_endpoint_reached && runs{3}.cpf.checkpoint_replay.attempts==0);
ck('on_FULL_needs_no_replay',runs{5}.cpf.checkpoint_replay.attempts==0);
ck('off_FULL_records_nose_and_continues',runs{4}.cpf.termination.nose_detected && runs{4}.cpf.lam(end)<b.cpf.lam(end)-.1);
% All returned trace arrays/events refer only to the replayed, accepted path.
ck('event_indices_in_retained_trace',all([b.cpf.events.k]<=numel(b.cpf.lam)-1));
zz=b.cpf.z(:,end);zz=zz(find(isfinite(zz),1,'last'));
ck('smooth_nose_tangent_within_tolerance',abs(zz)<=10*options.cpf.nose_tol);
for bad={-1,.5,NaN,[0 1]}
    o=options;o.vsc_mtdc.nose_replay_max=bad{1};rejected=false;
    try,runcpf_vsc_mtdc(base,target,o);catch me,rejected=strcmp(me.identifier,'runcpf_vsc_mtdc:nose_replay_max');end
    ck('invalid_replay_budget_rejected',rejected);
end
evidence=struct('passed',sum([checks.passed]),'failed',sum(~[checks.passed]), ...
    'checks',checks,'runs',{summary});
fid=fopen(fullfile(outdir,'replay_tests.json'),'w');fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));fclose(fid);
fprintf('CHECKPOINT_REPLAY: %d passed, %d failed\n',evidence.passed,evidence.failed);
assert(evidence.failed==0,'Checkpoint replay regression failed; see saved evidence');
 function ck(name,passed)
    checks(end+1)=struct('name',name,'passed',logical(passed));
 end
end
