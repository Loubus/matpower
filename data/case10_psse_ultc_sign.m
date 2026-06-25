function mpc = case10_psse_ultc_sign()
% case10_psse_ultc_sign - 10-bus PSS/E ULTC tap-sign validation fixture.

case_file = mfilename('fullpath');
data_dir = fileparts(case_file);
matpower_dir = fileparts(data_dir);
project_dir = fileparts(matpower_dir);
raw_file = fullfile(project_dir, 'PSSE', 'RAW', ...
    'psse_ultc_10bus_sign.raw');

mpc = psse2mpc(raw_file, 0, 34);
