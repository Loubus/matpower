function replay_cycle
% Diagnostic restart near the exploratory cycle, not a new main loading case.
out=fileparts(mfilename('fullpath'));
q=load(fullfile(out,'nose_probe.mat'));
r=q.b5satnose; d=r.cpf.failure.diagnostic;
summary=struct('exploratory_termination',r.cpf.termination, ...
    'candidate_lambda',r.cpf.failure.lambda,'last_lambda',r.cpf.lam(end), ...
    'candidate_electrical_converged',d.candidate_electrical_converged, ...
    'cause',d.cause,'decision_count',numel(d.decisions));
for k=1:numel(d.decisions)
    z=d.decisions{k};
    summary.decisions(k)=struct('iteration',z.iteration,'changed',z.changed, ...
        'report',z.report,'tap',z.input_result.branch(9,9), ...
        'vm5',z.input_result.bus(5,8),'vm7',z.input_result.bus(7,8), ...
        'residual',z.input_result.convergence.max_mismatch);
end
% Shift the loading origin using the last accepted exported electrical case.
% Original demand-growth direction and all ratings/control rules are retained.
s=load(fullfile(fileparts(out),'..','algorithm_cleanup_batch4_20260911','beerten_probe.mat'));
b=r;b=rmfield(b,intersect(fieldnames(b),{'cpf','convergence','ac','success','iterations','et'}));
t=b;t.bus(:,[3 4])=b.bus(:,[3 4])+s.b4t.bus(:,[3 4])-s.b4f.bus(:,[3 4]);
opt=q.b5noseopt;
% Explicitly bounded restart diagnostic; it is not the main lambda-0.8 run.
opt.vsc_mtdc.cpf_max_it=3;
logtext=evalc('a=runcpf_psse(b,t,opt);');
summary.restart_termination=a.cpf.termination;
summary.restart_origin=r.cpf.lam(end);
save(fullfile(out,'cycle_restart.mat'),'b','t','opt','a','summary','-v7.3');
fid=fopen(fullfile(out,'cycle_restart.log'),'w');fprintf(fid,'%s',logtext);fclose(fid);
fid=fopen(fullfile(out,'cycle_summary.json'),'w');fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));fclose(fid);
disp(summary.restart_termination);
end
