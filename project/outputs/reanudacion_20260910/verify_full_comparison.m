function verify_full_comparison
out = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(out));
addpath(root); iniciar_proyecto;
mpc = psse2mpc(fullfile(root,'PSSE','V26p_Trs_2532.raw'),0,34);
reference = psse2mpc(fullfile(out,'psse_full','solved_raw','V26p_Trs_2532_solved.raw'),0,34);
opt = mpoption('verbose',0,'out.all',0);
checks = struct('solver',{},'success',{},'seconds',{},'physical_buses_compared',{},'max_dVM',{},'rms_dVM',{},'max_dVA',{},'failure',{});
for k = 1:2
    solvers = {'runpf','runpf_psse'};
    tic;
    fprintf('START full RAW %s\n',solvers{k});
    r = feval(solvers{k},mpc,opt);
    elapsed=toc;
    physical = reference.bus(:,1) < 900000 & reference.bus(:,2) ~= 4;
    rb = reference.bus(physical,:);
    [~,ia,ib] = intersect(r.bus(:,1),rb(:,1));
    dv = r.bus(ia,8)-rb(ib,8);
    da = r.bus(ia,9)-rb(ib,9);
    failure = '';
    if isfield(r,'psse') && isfield(r.psse,'control_failure')
        failure = jsonencode(r.psse.control_failure);
    end
    checks(k)=struct('solver',solvers{k},'success',logical(r.success),'seconds',elapsed, ...
        'physical_buses_compared',numel(ia),'max_dVM',max(abs(dv)),'rms_dVM',sqrt(mean(dv.^2)), ...
        'max_dVA',max(abs(da)),'failure',failure);
    writetable(struct2table(checks,'AsArray',true),fullfile(out,'full_raw_comparison.csv'));
    fprintf('%s success=%d max_dVM=%.9g time=%.1fs\n',solvers{k},r.success,max(abs(dv)),elapsed);
end
end
