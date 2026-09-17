function run_study(destination)
% Reproduce the production runs in a NEW destination. Preserve saved evidence.
assert(nargin==1,'Supply a fresh output directory.');
assert(~isfolder(destination),'Use a fresh directory to preserve historical runs.');
mkdir(destination);
[g150_b,g150_t,g150_o,g150_study]=beerten_constant_pq_nonslack_dispatch;
g150_o=mpoption(g150_o,'cpf.stop_at','FULL','verbose',0,'out.all',0);
[sat,P]=gen_capability_curve(151,0,g150_b.gen_capability.Snom(2),2);
[~,~,Q]=gen_capability_curve(151,200,g150_b.gen_capability.Snom(2),2);
assert(sat && P==150 && Q==112.5,'Requested generator capability must be active.');
lastwarn(''); start=tic;
[g150_r,g150_success]=runcpf_psse(g150_b,g150_t,g150_o);
g150_elapsed=toc(start); [g150_warning,g150_warning_id]=lastwarn;
save(fullfile(destination,'main_run.mat'),'g150_b','g150_t','g150_o','g150_study','g150_r', ...
    'g150_success','g150_elapsed','g150_warning','g150_warning_id','-v7.3');
g150_ho=mpoption(g150_o,'cpf.step',.05); lastwarn('');
[g150_hr,g150_hsuccess]=runcpf_psse(g150_b,g150_t,g150_ho);
[g150_hw,g150_hwid]=lastwarn;
save(fullfile(destination,'half_step_run.mat'),'g150_hr','g150_hsuccess','g150_ho','g150_hw','g150_hwid','-v7.3');
disp(g150_r.cpf.termination); disp(g150_hr.cpf.termination);
end
