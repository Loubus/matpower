function iniciar_proyecto_legacy
%INICIAR_PROYECTO_LEGACY Enable preserved PSS/E/TRANSPA study workflows.
% Compatibility paths retain the directory depth expected by old scripts.
iniciar_proyecto;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'auditoria_psse_matpower'));
addpath(fullfile(root,'auditoria_psse_matpower','tools'));
addpath(fullfile(root,'auditoria_psse_matpower','transpa_reduccion'));
addpath(fullfile(root,'auditoria_psse_matpower','transpa_reduccion','cpf_psse_runner'));
addpath(fullfile(root,'auditoria_psse_matpower','results','transpa_reduccion_v1'));
fprintf('Estudios historicos habilitados mediante rutas de compatibilidad.\n');
end
