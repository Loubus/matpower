function run_id = beerten_cpf_run_id(opts)
%BEERTEN_CPF_RUN_ID Build a deterministic result folder name from options.

parts = ["beerten5_cpf", string(opts.mode)];
parts(end+1) = lower(string(opts.cpf.stop_at));
if opts.vsc_hvdc.enabled
    parts(end+1) = "vschvdc_on";
else
    parts(end+1) = "vschvdc_off";
end
parts(end+1) = sprintf('actaps%d', opts.controls.ACTAPS ~= 0);
parts(end+1) = sprintf('swshnt%d', opts.controls.SWSHNT ~= 0);
if ~opts.devices.ultc_transformer
    parts(end+1) = "no_ultc";
end
if ~opts.devices.switched_shunt
    parts(end+1) = "no_swshunt_device";
end
if isfield(opts.vsc_mtdc, 'capability_enforce') && ...
        opts.vsc_mtdc.capability_enforce
    parts(end+1) = "vsccap";
end
if isfield(opts.vsc_mtdc, 'capability_gen_enforce') && ...
        opts.vsc_mtdc.capability_gen_enforce
    parts(end+1) = "gencap";
end
run_id = char(strjoin(parts, '_'));
run_id = regexprep(run_id, '[^\w.-]', '_');
end
