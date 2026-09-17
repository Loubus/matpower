function results = analyze_batch2(outdir)
% Compare Code Analyzer findings against preserved pre-edit sources.
root = fileparts(fileparts(outdir));
files = {'matpower/lib/runpf_vsc_mtdc_unified.m', ...
 'matpower/lib/runcpf_vsc_mtdc.m', 'matpower/lib/+mp/psse_unified_active_set.m', ...
 'matpower/lib/+mp/psse_genq_states.m', 'matpower/lib/+mp/psse_expand_bus_controls.m', ...
 'matpower/lib/+mp/psse_branch_collapse.m', 'matpower/lib/+mp/psse_branch_expand.m', ...
 'matpower/lib/+mp/psse_swdev_collapse.m', 'matpower/lib/+mp/psse_swdev_expand.m', ...
 'matpower/lib/t/t_vsc_mtdc.m', 'tests/t_control_handoff_batch2.m'};
results = struct('file',{},'before',{},'after',{},'new_messages',{});
for k = 1:length(files)
 rel = files{k}; before_path = fullfile(outdir,'before',rel);
 after = checkcode(fullfile(root,rel),'-id');
 before = struct('message',{});
 if exist(before_path,'file'), before = checkcode(before_path,'-id'); end
 added = setdiff({after.message},{before.message});
 results(k) = struct('file',rel,'before',{before},'after',{after},'new_messages',{added});
 fprintf('%s: before=%d after=%d new unique messages=%d\n',rel,length(before),length(after),length(added));
 if ~isempty(added), disp(added'); end
end
save(fullfile(outdir,'code_analysis.mat'),'results');
fid=fopen(fullfile(outdir,'code_analysis.json'),'w');
fprintf(fid,'%s\n',jsonencode(results,'PrettyPrint',true)); fclose(fid);
end
