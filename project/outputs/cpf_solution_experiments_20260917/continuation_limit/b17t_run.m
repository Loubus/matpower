function b17t_run(step)
% Isolated continuation transition experiment. Original case/options retained.
folder=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(fileparts(folder)));
data=load(fullfile(root,'outputs','ultc_swshunt_g2_150mw_20260916','main_run.mat'));
base=data.g150_b; target=data.g150_t;
options=mpoption(data.g150_o,'cpf.step',step);
name=sprintf('diagnostic_step_%03d',round(1000*step));
assert(~isfile(fullfile(folder,[name '.mat'])),'Preserve prior experimental output');
b17_journal('reset'); lastwarn('');
diary(fullfile(folder,[name '.log'])); cleaner=onCleanup(@()diary('off'));
tic;
[result,success]=b17t_psse(base,target,options);
elapsed=toc; [warning,warning_id]=lastwarn; journal=b17_journal('get');
save(fullfile(folder,[name '.mat']),'base','target','options','result','success','elapsed','warning','warning_id','journal','-v7.3');
summary=struct('step',step,'success',success,'elapsed',elapsed,'warning',warning,'warning_id',warning_id, ...
    'points',numel(result.cpf.lam),'lambda_final',result.cpf.lam(end),'lambda_max',max(result.cpf.lam), ...
    'termination',result.cpf.termination,'transition_corrections',numel(journal), ...
    'negative_lambda_steps',sum(diff(result.cpf.lam)<0));
summary.turn_indices=find(diff(sign(result.cpf.z(end,:)))<0)+1;
summary.events=result.cpf.events;
if ~isempty(journal), summary.journal=[journal{:}]; end
fid=fopen(fullfile(folder,[name '_summary.json']),'w'); fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true)); fclose(fid);
disp(summary.termination); fprintf('B17 step=%g points=%d max_lambda=%.12g last_lambda=%.12g transitions=%d elapsed=%.1f\n',step,summary.points,summary.lambda_max,summary.lambda_final,numel(journal),elapsed);
end
