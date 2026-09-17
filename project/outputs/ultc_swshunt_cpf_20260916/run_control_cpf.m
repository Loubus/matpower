function run_control_cpf(project_root)
% User-selected saved constant-P/Q, non-slack dispatch scenario; fresh FULL run.
out=fileparts(mfilename('fullpath'));
assert(~isfile(fullfile(out,'full_run.mat')),'Preserve the existing full run.');
clear runpf_vsc_mtdc runpf_vsc_mtdc_unified runcpf_vsc_mtdc runcpf_psse calc_vsc_losses vsc_loss_coefficients
[base,target,options,study]=beerten_constant_pq_nonslack_dispatch;
original_options=options;
options=mpoption(options,'cpf.stop_at','FULL','out.all',0,'verbose',1);
% Retain electrical parameters, step settings, tolerances and control policies.
save(fullfile(out,'inputs.mat'),'base','target','options','original_options','study','project_root');
diary(fullfile(out,'run.log'));
cleanup=onCleanup(@() diary('off'));
fprintf('Fresh FULL CPF: %s\n',study.name);
fprintf('Control policy: %s; capability policy: %s\n',options.vsc_mtdc.psse_control_limit,options.vsc_mtdc.capability_limit);
lastwarn(''); clock_start=tic;
try
    [result,success]=runcpf_psse(base,target,options);
    elapsed=toc(clock_start); [last_warning,last_warning_id]=lastwarn;
    save(fullfile(out,'full_run.mat'),'result','success','elapsed','last_warning','last_warning_id','base','target','options','study','-v7.3');
    summary=struct('scenario',study.name,'requested_stop','FULL','success',success,'elapsed_seconds',elapsed, ...
        'last_warning',last_warning,'last_warning_id',last_warning_id,'directional_loss_metadata',isfield(base,'vsc_loss'));
    if isfield(result,'cpf')
        summary.done_msg=result.cpf.done_msg;
        summary.points=numel(result.cpf.lam);
        summary.lambda_start=result.cpf.lam(1);
        summary.lambda_end=result.cpf.lam(end);
        summary.max_lambda=result.cpf.max_lam;
        summary.returned_to_zero_after_nose=any(diff(result.cpf.lam)<-1e-7) && abs(result.cpf.lam(end))<1e-6;
        summary.event_count=numel(result.cpf.events);
        summary.cpf_fields=fieldnames(result.cpf);
    end
catch e
    elapsed=toc(clock_start);
    summary=struct('scenario',study.name,'success',false,'elapsed_seconds',elapsed, ...
        'exception_identifier',e.identifier,'exception_message',e.message,'exception_report',getReport(e,'extended','hyperlinks','off'));
    save(fullfile(out,'exception.mat'),'e','summary','base','target','options','study');
end
fid=fopen(fullfile(out,'summary.json'),'w'); fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true)); fclose(fid);
disp(jsonencode(summary,PrettyPrint=true));
end
