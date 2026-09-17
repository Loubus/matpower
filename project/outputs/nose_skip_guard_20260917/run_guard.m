function run_guard
out=fileparts(mfilename('fullpath')); root=fileparts(fileparts(out));
src=fullfile(root,'outputs','cpf_solution_experiments_20260917');
folders={src,fullfile(src,'coupled_limit'),fullfile(src,'continuation_limit','all_controls'),fullfile(src,'coupled_limit','combined_all_controls')};
for k=1:numel(folders),addpath(folders{k});end
cleanup=onCleanup(@()clean(folders)); %#ok<NASGU>
old=load(fullfile(root,'outputs','ultc_swshunt_g2_150mw_20260916','main_run.mat'));
base=old.g150_b;target=old.g150_t; names={'baseline','coupled','augmented','combined'};
summary=cell(0,1);
for k=1:4
 for step=[.1 .05]
    stem=sprintf('%s_%03d',names{k},round(1000*step)); assert(~isfile(fullfile(out,[stem '.mat'])));
    options=mpoption(old.g150_o,'cpf.stop_at','NOSE','cpf.step',step);lastwarn('');tic;
    fn=str2func(sprintf('ng%d_psse',k-1));[result,success]=fn(base,target,options);
    elapsed=toc;[warning_text,warning_id]=lastwarn;
    save(fullfile(out,[stem '.mat']),'base','target','options','result','success','elapsed','warning_text','warning_id','-v7.3');
    audit=cpfexp_independent_audit(result,base,target,options,fullfile(out,stem));
    item=struct('variant',names{k},'step',step,'points',numel(result.cpf.lam), ...
        'lambda',result.cpf.lam(end),'termination',result.cpf.termination, ...
        'guard',result.cpf.guard_stop,'history',{result.cpf.guard_history}, ...
        'physical_checks_pass',audit.all_required_physical_checks_pass,'warning',warning_text);
    summary{end+1}=item; %#ok<AGROW>
    fid=fopen(fullfile(out,[stem '.json']),'w');fprintf(fid,'%s',jsonencode(item,PrettyPrint=true));fclose(fid);
    fprintf('%s step%.2f stop=%s lambda%.12g guardtrials=%d checks=%d\n',names{k},step,result.cpf.termination.cause,item.lambda,numel(result.cpf.guard_history),audit.all_required_physical_checks_pass);
 end
end
fid=fopen(fullfile(out,'comparison.json'),'w');fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true));fclose(fid);
end
function clean(folders)
for k=1:numel(folders),rmpath(folders{k});end
end
