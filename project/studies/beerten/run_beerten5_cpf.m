function results = run_beerten5_cpf(opts)
%RUN_BEERTEN5_CPF Canonical Beerten 5-bus CPF runner.
%
% This thin wrapper exposes the dedicated implementation folder without
% requiring callers to add that subfolder manually.

runner_dir = fullfile(fileparts(mfilename('fullpath')), 'cpf_runner');
if ~contains(path, runner_dir)
    addpath(runner_dir);
end

if nargin < 1
    opts = struct();
end
results = beerten_cpf_run(opts);
end
