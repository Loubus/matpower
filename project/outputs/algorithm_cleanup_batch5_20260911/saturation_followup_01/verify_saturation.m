function verify_saturation(label)
out=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(fileparts(out)));
addpath(fullfile(root,'tests'));
dest=fullfile(out,label);assert(~isfolder(dest),'Use a fresh verification directory');mkdir(dest);
names={'t_control_saturation_batch5','t_beerten_termination_batch5', ...
    't_control_acceptance_batch1','t_control_handoff_batch2', ...
    't_ultc_acceptance_batch3','t_swshunt_acceptance_batch4', ...
    't_ultc_beerten_batch3','t_swshunt_beerten_batch4', ...
    't_cpf','t_mpxt_psse','t_vsc_mtdc'};
for k=1:numel(names)
    name=names{k};folder=fullfile(dest,name);
    if k<=8
        run_batch5_suite(name,folder,fullfile(folder,'evidence'));
    else
        run_batch5_suite(name,folder);
    end
end
end
