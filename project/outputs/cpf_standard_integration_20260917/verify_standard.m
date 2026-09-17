function verify_standard(mode,step,subdirectory)
out=fileparts(mfilename('fullpath'));root=fileparts(fileparts(out));
if nargin>2, out=fullfile(out,subdirectory); if ~isfolder(out),mkdir(out);end;end
auditpath=fullfile(root,'outputs','cpf_solution_experiments_20260917');
addpath(auditpath); cleanup=onCleanup(@()rmpath(auditpath)); %#ok<NASGU>
d=load(fullfile(root,'outputs','ultc_swshunt_g2_150mw_20260916','main_run.mat'));
base=d.g150_b;target=d.g150_t;
options=mpoption(d.g150_o,'cpf.stop_at',mode,'cpf.step',step);
stem=sprintf('%s_%03d',lower(mode),round(1000*step));
assert(~isfile(fullfile(out,[stem '.mat'])),'Preserve existing verification output');
lastwarn('');tic;[result,success]=runcpf_psse(base,target,options);elapsed=toc;
[warning_text,warning_id]=lastwarn;
save(fullfile(out,[stem '.mat']),'base','target','options','result','success','elapsed','warning_text','warning_id','-v7.3');
audit=cpfexp_independent_audit(result,base,target,options,fullfile(out,stem));
summary=struct('mode',mode,'step',step,'elapsed',elapsed,'termination',result.cpf.termination, ...
    'lambda',result.cpf.lam(end),'V5',result.bus(5,8), ...
    'physical_checks_pass',audit.all_required_physical_checks_pass, ...
    'turn_events',result.cpf.events(ismember({result.cpf.events.name},{'NOSE','LIMIT_INDUCED_TURN'})), ...
    'turn_trials',{result.cpf.turn_detection.history},'warning',warning_text);
fid=fopen(fullfile(out,[stem '.json']),'w');fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true));fclose(fid);
disp(summary.termination);fprintf('lambda=%.12f V5=%.12f physical_checks=%d elapsed=%.1fs\n',summary.lambda,summary.V5,summary.physical_checks_pass,elapsed);
end
