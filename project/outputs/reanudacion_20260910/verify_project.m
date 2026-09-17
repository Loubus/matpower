function verify_project
% Reproducible verification; writes only inside this audit directory.
out = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(out));
addpath(fullfile(root, 'matpower'));
matpower_project_startup;
addpath(fullfile(root, 'auditoria_psse_matpower'));
addpath(genpath(fullfile(root, 'auditoria_psse_matpower', 'transpa_reduccion')));
addpath(genpath(fullfile(root, 'auditoria_psse_matpower', 'beerten_5bus')));
addpath(fullfile(root, 'auditoria_psse_matpower', 'results', 'transpa_reduccion_v1'));
set(groot, 'defaultFigureVisible', 'off');
names = {'raw_full_pf', 'transpa_baseline_cpf', 'transpa_controls_cpf', 'beerten_vsc_cpf', 'diagnostics'};
checks = struct('name', {}, 'success', {}, 'seconds', {}, 'detail', {});
for k = 1:numel(names)
    tic;
    fprintf('\nSTART %s\n', names{k});
    try
        detail = struct();
        switch names{k}
            case 'raw_full_pf'
                mpc = psse2mpc(fullfile(root,'PSSE','V26p_Trs_2532.raw'),0,34);
                r = runpf(mpc, mpoption('verbose',0,'out.all',0));
                detail = struct('success',r.success,'buses',size(r.bus,1),'iterations',r.iterations);
                assert(r.success, 'Full RAW standard PF did not converge');
            case 'transpa_baseline_cpf'
                opts = transpa_cpf_preset('all_disabled_pv_only');
                opts.outdir = fullfile(out,'transpa_baseline');
                opts.plots = false;
                r = run_transpa_cpf_psse(opts);
                detail = r.summary;
                assert(r.success, 'TRANSPA baseline CPF did not converge');
            case 'transpa_controls_cpf'
                opts = transpa_cpf_default_opts();
                opts.outdir = fullfile(out,'transpa_controls');
                opts.plots = false;
                r = run_transpa_cpf_psse(opts);
                detail = r.summary;
                assert(r.success, 'TRANSPA controlled CPF did not converge');
            case 'beerten_vsc_cpf'
                opts = beerten_cpf_preset('paper_controls_cap_nose');
                opts.outdir = fullfile(out,'beerten_vsc');
                r = run_beerten5_cpf(opts);
                detail = r.summary;
                assert(r.success, 'Beerten VSC CPF did not converge');
            case 'diagnostics'
                opts = struct('plots', false);
                r = psse_study_diagnostics(fullfile(out,'beerten_vsc'),fullfile(out,'diagnostics'),opts);
                detail = struct('completed', ~isempty(r));
        end
        checks(k) = struct('name',names{k},'success',true,'seconds',toc,'detail',detail);
        fprintf('PASS %s (%.1f s)\n', names{k},checks(k).seconds);
    catch err
        checks(k) = struct('name',names{k},'success',false,'seconds',toc,'detail', ...
            struct('error',getReport(err,'extended','hyperlinks','off'),'partial',detail));
        fprintf('FAIL %s: %s\n', names{k}, checks(k).detail.error);
    end
    fid = fopen(fullfile(out,'project_checks.json'),'w');
    fprintf(fid,'%s',jsonencode(checks,PrettyPrint=true));
    fclose(fid);
    close all;
end
assert(all([checks.success]), 'One or more project checks failed; see project_checks.json');
end
