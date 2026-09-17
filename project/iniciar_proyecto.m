function iniciar_proyecto
%INICIAR_PROYECTO Configure thesis paths for the current MATLAB session.
% Run from the project root. Does not modify MATLAB's saved global path.
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'matpower'));
matpower_project_startup;
% Remove only the project's former default study paths, if this session has
% already used them. MATLAB/MCP and unrelated user paths are left intact.
legacy = {
    fullfile(root,'auditoria_psse_matpower')
    fullfile(root,'auditoria_psse_matpower','tools')
    fullfile(root,'auditoria_psse_matpower','transpa_reduccion')
    fullfile(root,'auditoria_psse_matpower','transpa_reduccion','cpf_psse_runner')
    fullfile(root,'auditoria_psse_matpower','beerten_5bus')
    fullfile(root,'auditoria_psse_matpower','beerten_5bus','cpf_runner')
    fullfile(root,'auditoria_psse_matpower','results','transpa_reduccion_v1')
    fullfile(root,'archive','psse_compatibility','auditoria_psse_matpower')
    fullfile(root,'archive','psse_compatibility','auditoria_psse_matpower','tools')
    fullfile(root,'archive','transpa_reduction_v1','studies')
    fullfile(root,'archive','transpa_reduction_v1','studies','cpf_psse_runner')
    fullfile(root,'archive','transpa_reduction_v1','results')
    };
% Filter the stored path text: rmpath canonicalizes Windows junctions and
% may miss an old path entry after its directory has been moved.
path_entries = strsplit(path,pathsep);
keep = true(size(path_entries));
for k = 1:numel(legacy)
    keep = keep & ~strcmpi(path_entries,legacy{k});
end
if any(~keep)
    path(strjoin(path_entries(keep),pathsep));
end
addpath(fullfile(root,'cases','beerten','variants'));
for case_id = {'14','30','39','57'}
    addpath(fullfile(root,'cases','ieee',case_id{1}));
end
addpath(fullfile(root,'studies','beerten'));
addpath(fullfile(root,'studies','beerten','cpf_runner'));
fprintf('Proyecto listo. MATPOWER: %s\n',which('runpf_psse'));
end
