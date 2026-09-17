function opts = beerten_cpf_default_opts()
%BEERTEN_CPF_DEFAULT_OPTS Default options for the Beerten 5-bus CPF runner.

opts = struct();
opts.mode = 'psse';              % 'psse', 'vsc_mtdc', or 'regular'
opts.case_function = 'case5_vsc_mtdc_beerten_paper_controls_cap_explicit';
opts.target_function = ...
    'case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit';
opts.outdir = '';
opts.outdir_name = '';
opts.run_id = '';
opts.plots = true;
opts.save_mat = true;
opts.save_version = '-v7.3';

opts.vsc_hvdc = struct();
opts.vsc_hvdc.enabled = true;
opts.vsc_hvdc.force_in_service = false;
opts.vsc_hvdc.disable_hvdc_policy = true;
opts.vsc_hvdc.disable_vsc_capability_policy = true;

opts.controls = struct();
opts.controls.ACTAPS = 1;
opts.controls.SWSHNT = 1;

opts.devices = struct();
opts.devices.switched_shunt = true;
opts.devices.ultc_transformer = true;

opts.cpf = struct();
opts.cpf.stop_at = 'FULL';
opts.cpf.step = 0.025;
opts.cpf.step_max = 0.025;
opts.cpf.step_min = 1e-7;
opts.cpf.adapt_step = 1;
opts.cpf.enforce_q_lims = 0;
opts.cpf.plot_level = 0;

opts.vsc_mtdc = struct();
opts.vsc_mtdc.method = 'unified';
opts.vsc_mtdc.cpf_max_lam = 20;
opts.vsc_mtdc.cpf_max_it = 6000;
opts.vsc_mtdc.capability_enforce = 1;
opts.vsc_mtdc.capability_gen_enforce = 1;
opts.vsc_mtdc.capability_max_it = 10;
opts.vsc_mtdc.capability_limit = 'freeze';
opts.vsc_mtdc.psse_control_limit = 'freeze';

opts.policy = struct();
opts.policy.disable_hvdc_redispatch_for_full_trace = true;
opts.policy.disable_vsc_derating_for_full_trace = true;

opts.plot_prefix = 'pv';
end
