function exc_run(step)
% Called only by the coordinating parent through MATLAB MCP.
out=fileparts(mfilename('fullpath')); root=fileparts(fileparts(fileparts(fileparts(out))));
in=load(fullfile(root,'outputs','ultc_swshunt_g2_150mw_20260916','main_run.mat'));
b=in.g150_b;t=in.g150_t; o=in.g150_o;
o=mpoption(o,'cpf.step',step);
name=sprintf('step_%03d',round(1000*step));
assert(~isfile(fullfile(out,[name '.mat'])),'Do not overwrite saved experiment.');
exc_log('reset'); exc_transition_journal('reset'); lastwarn(''); st=tic;
[r,success]=exc_psse(b,t,o); elapsed=toc(st); [warning_text,warning_id]=lastwarn;
journal=exc_log('read'); transitions=exc_transition_journal('get');
save(fullfile(out,[name '.mat']),'b','t','o','r','success','elapsed','warning_text','warning_id','journal','transitions','-v7.3');
[T,audit]=exc_audit_trace(r,b,o);
[audit.max_lambda,audit.max_lambda_index]=max(r.cpf.lam);
audit.negative_lambda_steps=sum(diff(r.cpf.lam)<0);
audit.journal=journal; audit.transitions=transitions; audit.elapsed=elapsed; audit.warning=warning_text;
writetable(T,fullfile(out,[name '_trace.csv']));
fid=fopen(fullfile(out,[name '_audit.json']),'w'); fprintf(fid,'%s',jsonencode(audit,PrettyPrint=true)); fclose(fid);
disp(audit.termination); disp(audit.checks);
fprintf('COUPLED step=%g success=%d points=%d max_lambda=%.12g end_lambda=%.12g\n',step,success,height(T),audit.max_lambda,T.lambda(end));
end
