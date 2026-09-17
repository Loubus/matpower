function findings = verify_code_analysis(root,outdir)
% Persist MATLAB Code Analyzer diagnostics for the final changed MATLAB files.
files={'matpower/lib/+mp/psse_swshunt_control.m', ...
    'matpower/lib/+mp/psse_unified_control_update.m', ...
    'matpower/lib/+mp/psse_swshunt_group_action.m', ...
    'matpower/lib/+mp/psse_swshunt_discrete_next.m', ...
    'tests/t_swshunt_acceptance_batch4.m','tests/t_swshunt_beerten_batch4.m'};
findings=struct('file',{},'issues',{});
for k=1:length(files)
    findings(k)=struct('file',files{k},'issues',checkcode(fullfile(root,files{k}),'-id'));
end
fid=fopen(fullfile(outdir,'code_analysis.json'),'w'); cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(findings,'PrettyPrint',true));
disp(findings);
end
