function iniciar_proyecto
%INICIAR_PROYECTO Configure thesis paths for the current MATLAB session.
% Run from the project root. Does not modify MATLAB's saved global path.
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'matpower'));
matpower_project_startup;
addpath(fullfile(root,'auditoria_psse_matpower'));
addpath(fullfile(root,'auditoria_psse_matpower','tools'));
addpath(fullfile(root,'auditoria_psse_matpower','transpa_reduccion'));
addpath(fullfile(root,'auditoria_psse_matpower','transpa_reduccion','cpf_psse_runner'));
addpath(fullfile(root,'auditoria_psse_matpower','beerten_5bus'));
addpath(fullfile(root,'auditoria_psse_matpower','beerten_5bus','cpf_runner'));
addpath(fullfile(root,'auditoria_psse_matpower','results','transpa_reduccion_v1'));
fprintf('Proyecto listo. MATPOWER: %s\n',which('runpf_psse'));
end
