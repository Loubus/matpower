function verify_suite
out = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(out));
addpath(fullfile(root,'matpower'));
matpower_project_startup;
cases = dir(fullfile(root,'auditoria_psse_matpower','psse_validation_suite','*.raw'));
opt = mpoption('verbose',0,'out.all',0);
opt.exp.psse_coordinated_active_set = 1;
rows = struct('case_name',{},'success',{},'seconds',{},'error',{});
results = cell(numel(cases),1);
for k = 1:numel(cases)
    tic;
    try
        mpc = psse2mpc(fullfile(cases(k).folder,cases(k).name),0,34);
        r = runpf_psse(mpc,opt);
        results{k} = struct('bus',r.bus,'gen',r.gen,'success',r.success);
        rows(k) = struct('case_name',cases(k).name,'success',logical(r.success),'seconds',toc,'error','');
    catch err
        rows(k) = struct('case_name',cases(k).name,'success',false,'seconds',toc,'error',err.message);
    end
    fprintf('%d/%d %s success=%d (%.2f s)\n',k,numel(cases),cases(k).name,rows(k).success,rows(k).seconds);
    writetable(struct2table(rows,'AsArray',true),fullfile(out,'matpower_suite.csv'));
end
save(fullfile(out,'matpower_suite.mat'),'results','rows');
fprintf('SUITE SUCCESS: %d/%d\n',sum([rows.success]),numel(rows));
end
