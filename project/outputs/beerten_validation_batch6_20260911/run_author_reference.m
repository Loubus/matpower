function run_author_reference(outdir)
% Run unmodified author software with scoped path additions (no path reset).
p=fullfile(outdir,'reference','MatACDC1.0');
paths={p,fullfile(p,'Cases','PowerflowAC'),fullfile(p,'Cases','PowerflowDC')};
for k=1:numel(paths),addpath(paths{k},'-begin');end
cleanup=onCleanup(@() release_paths(paths));
clear idx_busdc
diary(fullfile(outdir,'author_reference.log')); dcopt=macdcoption;
opt=mpoption('verbose',0,'out.all',0);
try
 [ac,dc,success,seconds]=runacdcpf('case5_stagg','case5_stagg_MTDCslack',dcopt,opt);
 save(fullfile(outdir,'author_reference.mat'),'ac','dc','success','seconds','dcopt','opt');
 fid=fopen(fullfile(outdir,'author_reference.json'),'w');fprintf(fid,'%s',jsonencode(struct('ac',ac,'dc',dc,'success',success,'seconds',seconds)));fclose(fid);
catch err
 fid=fopen(fullfile(outdir,'author_reference_error.txt'),'w');fprintf(fid,'%s',getReport(err,'extended','hyperlinks','off'));fclose(fid);disp(getReport(err));
end
diary off
end
function release_paths(paths)
for k=1:numel(paths),rmpath(paths{k});end
clear idx_busdc
end
