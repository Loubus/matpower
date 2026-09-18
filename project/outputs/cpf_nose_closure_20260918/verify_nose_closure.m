function evidence=verify_nose_closure
% Final scoped verification before committing the NOSE study decision.
out=fileparts(mfilename('fullpath'));
d=beerten_cpf_default_opts; p=beerten_cpf_preset; f=beerten_cpf_preset('paper_controls_cap_full');
assert(strcmp(d.cpf.stop_at,'NOSE'));
assert(strcmp(p.cpf.stop_at,'NOSE'));
assert(strcmp(f.cpf.stop_at,'FULL'));
[base,target,o]=beerten_constant_pq_nonslack_dispatch;
assert(strcmp(o.cpf.stop_at,'NOSE'));
o=mpoption(o,'cpf.step',.05);
lastwarn(''); [result,success]=runcpf_psse(base,target,o); [warning,warning_id]=lastwarn;
save(fullfile(out,'nose_050.mat'),'base','target','o','result','success','warning','warning_id');
assert(success && result.cpf.termination.requested_endpoint_reached);
assert(strcmp(result.cpf.termination.cause,'limit_induced_turn'));
assert(abs(result.cpf.max_lam-1.2456689453699459)<1e-8);
assert(isempty(warning));
reference=load(fullfile(out,'../cpf_branch_preserving_release_20260918/verified/nose_050_release1.mat'),'result');
assert(isequaln(result.cpf.lam,reference.result.cpf.lam));
assert(isequaln(result.cpf.vsc,reference.result.cpf.vsc));
evidence=struct('success',success,'termination',result.cpf.termination, ...
    'first_maximum_lambda',result.cpf.max_lam,'total_demand_MW',sum(result.bus(:,3)), ...
    'warning',warning,'warning_id',warning_id,'matches_verified_trace',true, ...
    'runner_default','NOSE','no_argument_preset','NOSE','explicit_full_preset','FULL', ...
    'existing_gate_counts',[146 23 330],'existing_gates_repeated',false);
fid=fopen(fullfile(out,'verification.json'),'w');guard=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));disp(evidence);
end
