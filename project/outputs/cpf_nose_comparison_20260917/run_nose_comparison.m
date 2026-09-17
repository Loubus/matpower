function run_nose_comparison
% Explicit NOSE experiments; no production, previous experiments or case edits.
out=fileparts(mfilename('fullpath')); root=fileparts(fileparts(out));
src=fullfile(root,'outputs','cpf_solution_experiments_20260917');
folders={src,fullfile(src,'coupled_limit'),fullfile(src,'continuation_limit','all_controls'),fullfile(src,'coupled_limit','combined_all_controls')};
for k=1:numel(folders), addpath(folders{k}); end
cleaner=onCleanup(@()cleanup_paths(folders)); %#ok<NASGU>
d=load(fullfile(root,'outputs','ultc_swshunt_g2_150mw_20260916','main_run.mat'));
base=d.g150_b; target=d.g150_t;
names={'baseline','coupled_current','augmented_tangent','combined'};
solvers={@runcpf_psse,@exa_psse,@b17a_psse,@exd_psse};
all_summary=cell(0,1);
for k=1:4
    for step=[.1 .05]
        stem=sprintf('%s_%03d',names{k},round(step*1000));
        assert(~isfile(fullfile(out,[stem '.mat'])),'Preserve previous run.');
        options=mpoption(d.g150_o,'cpf.stop_at','NOSE','cpf.step',step);
        exa_log('reset'); b17a_journal('reset'); exd_log('reset'); exd_transition_journal('reset');
        lastwarn(''); tic;
        [result,success]=solvers{k}(base,target,options);
        elapsed=toc; [warning_text,warning_id]=lastwarn;
        journal=struct('A',{exa_log('read')},'B',{b17a_journal('get')},'AB',{exd_log('read')},'AB_transitions',{exd_transition_journal('get')});
        save(fullfile(out,[stem '.mat']),'base','target','options','result','success','elapsed','warning_text','warning_id','journal','-v7.3');
        audit=cpfexp_independent_audit(result,base,target,options,fullfile(out,stem));
        s=struct('variant',names{k},'step',step,'success',success,'points',numel(result.cpf.lam), ...
            'final_lambda',result.cpf.lam(end),'max_sample_lambda',max(result.cpf.lam), ...
            'final_V5',result.bus(5,8),'termination',result.cpf.termination, ...
            'all_physical_checks_pass',audit.all_required_physical_checks_pass, ...
            'sign_crossing_indices',audit.tangent_sign_crossings,'warning',warning_text,'elapsed',elapsed);
        s.final_loading_tangent=result.cpf.z(find(isfinite(result.cpf.z(:,end)),1,'last'),end);
        s.events=result.cpf.events;
        all_summary{end+1}=s; %#ok<AGROW>
        fid=fopen(fullfile(out,[stem '_summary.json']),'w'); fprintf(fid,'%s',jsonencode(s,PrettyPrint=true)); fclose(fid);
        fprintf('%s step=%.2f NOSE=%d endpoint=%d cause=%s lambda=%.12g V5=%.9g physical=%d\n',names{k},step,s.termination.nose_detected,s.termination.requested_endpoint_reached,s.termination.cause,s.final_lambda,s.final_V5,s.all_physical_checks_pass);
    end
end
fid=fopen(fullfile(out,'comparison.json'),'w'); fprintf(fid,'%s',jsonencode([all_summary{:}],PrettyPrint=true)); fclose(fid);
end
function cleanup_paths(folders)
for k=1:numel(folders), rmpath(folders{k}); end
end
