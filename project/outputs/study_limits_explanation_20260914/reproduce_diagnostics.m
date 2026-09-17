function reproduce_diagnostics(destination)
%REPRODUCE_DIAGNOSTICS Replay bounded checks into a new output directory.
% Call via MATLAB MCP after iniciar_proyecto from the project root.
% This output-local helper does not modify cases or production solver files.
arguments
    destination (1,:) char
end
assert(~isfolder(destination) && ~isfile(destination), ...
    'Destination already exists; choose a new directory to preserve results.');
[base,target,options,study] = beerten_constant_pq_nonslack_dispatch;
mkdir(destination);
diary(fullfile(destination,'diagnostics.log'));
cleanup = onCleanup(@() diary('off'));
targets = [1/6, 0.2];
names = {'boundary', 'dispatch_020'};
for k = 1:numel(targets)
    run_options = mpoption(options,'cpf.stop_at',targets(k), ...
        'verbose',0,'out.all',0,'cpf.plot.level',0);
    lastwarn('');
    result = runcpf_psse(base,target,run_options);
    [warning_message,warning_id] = lastwarn;
    save(fullfile(destination,[names{k} '.mat']), ...
        'base','target','options','run_options','study','result', ...
        'warning_message','warning_id');
    lam = result.cpf.lam(end);
    fprintf('%s: success=%d lambda=%.15g PG2=%.15g scheduled=%.15g\n', ...
        names{k},result.success,lam,result.gen(2,2),40+240*lam);
    disp(result.cpf.termination);
end
end
