function inspect_results
out = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(out));
addpath(root);
iniciar_proyecto;
d = dir(fullfile(out,'transpa_controls','*.mat'));
s = load(fullfile(d(1).folder,d(1).name),'cpf_results','run_info');
r = s.cpf_results;
fprintf('CPF fields:\n'); disp(fieldnames(r.cpf));
for n = {'done_msg','stop_reason','success','iterations'}
    f=n{1};
    if isfield(r.cpf,f), fprintf('cpf.%s:\n',f); disp(r.cpf.(f)); end
    if isfield(r,f), fprintf('result.%s:\n',f); disp(r.(f)); end
end
if isfield(r,'psse') && isfield(r.psse,'cpf'), disp(r.psse.cpf); end
if isfield(r,'psse') && isfield(r.psse,'control_failure')
    fprintf('CONTROL FAILURE:\n'); disp(r.psse.control_failure);
end
if isfield(r,'task')
    fprintf('TASK MESSAGE:\n'); disp(r.task.message);
end
fprintf('RUN INFO:\n'); disp(s.run_info);
if isfield(r.cpf,'events') && ~isempty(r.cpf.events)
    fprintf('LAST EVENTS:\n'); disp(r.cpf.events(max(1,end-3):end));
end
assert(~isempty(which('transpa_cpf_default_opts')));
assert(~isempty(which('beerten_cpf_default_opts')));
fprintf('STARTUP_OK\n');
end
