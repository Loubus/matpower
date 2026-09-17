function run_nose(folder)
% Full automatic-control scenario; only declared modeling/endpoint changes.
assert(~isfolder(folder),'Use a fresh output directory'); mkdir(folder);
diary(fullfile(folder,'run.log')); cleanup=onCleanup(@() diary('off'));
s=load(fullfile('outputs','algorithm_cleanup_batch4_20260911','beerten_probe.mat'));
base=s.b4f; target=s.b4t; original_options=s.b4o;
options=mpoption(original_options,'exp.psse_pqbrak',0, ...
    'vsc_mtdc.psse_control_limit','saturate','cpf.stop_at','NOSE');
[prepared,~,effective_options]=mp.psse_prepare_case(base,options,'cpf');
assert(~prepared.psse.pqbrak.enabled && all(prepared.psse.pqbrak.scale==1));
save(fullfile(folder,'inputs.mat'),'base','target','original_options','options','prepared','effective_options');
fprintf('Starting full NOSE run, PQBRAK off, %s\n',char(datetime('now')));
started=tic;
result=runcpf_psse(base,target,options);
elapsed_seconds=toc(started);
save(fullfile(folder,'nose.mat'),'result','options','elapsed_seconds','-v7.3');
summary=struct('success',result.success,'termination',result.cpf.termination, ...
    'convergence',result.convergence,'elapsed_seconds',elapsed_seconds, ...
    'lambda',result.cpf.lam,'vm5',result.bus(result.bus(:,1)==5,8), ...
    'tap',result.branch(9,9),'events',result.cpf.events);
if isfield(result.psse,'pqbrak'), summary.pqbrak=result.psse.pqbrak; end
if isfield(result.cpf,'failure'), summary.failure=result.cpf.failure; end
fid=fopen(fullfile(folder,'summary.json'),'w'); fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true)); fclose(fid);
disp(result.cpf.termination); disp(result.convergence);
fprintf('Completed in %.3f seconds\n',elapsed_seconds);
end
