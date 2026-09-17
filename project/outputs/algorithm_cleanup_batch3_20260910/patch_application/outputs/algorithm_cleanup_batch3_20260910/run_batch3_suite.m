function counts = run_batch3_suite(name, outdir, varargin)
% Capture MP-Test counts and exceptions without mistaking saved output for pass.
assert(~exist(outdir,'dir'), 'Use a fresh suite directory');
mkdir(outdir);
global t_num_of_tests t_counter t_ok_cnt t_not_ok_cnt t_skip_cnt
t_num_of_tests = 0; t_counter = 1; t_ok_cnt = 0; t_not_ok_cnt = 0; t_skip_cnt = 0;
started = tic; failure = ''; 
logtext = evalc('try; feval(name, 0, varargin{:}); catch err; failure = getReport(err, ''extended'', ''hyperlinks'', ''off''); disp(failure); end');
counts = struct('name',name,'planned',t_num_of_tests,'executed',t_ok_cnt+t_not_ok_cnt+t_skip_cnt, ...
 'passed',t_ok_cnt,'failed',t_not_ok_cnt,'skipped',t_skip_cnt, ...
 'exception',failure,'elapsed_seconds',toc(started),'matlab',version);
fid=fopen(fullfile(outdir,'run.log'),'w'); fprintf(fid,'%s',logtext); fclose(fid);
fid=fopen(fullfile(outdir,'counts.json'),'w'); fprintf(fid,'%s\n',jsonencode(counts,'PrettyPrint',true)); fclose(fid);
save(fullfile(outdir,'counts.mat'),'counts');
disp(counts);
end

