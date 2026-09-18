function opts = beerten_cpf_preset(name)
%BEERTEN_CPF_PRESET Named configurations for repeatable Beerten CPF runs.

if nargin < 1 || isempty(name)
    name = 'paper_controls_cap_nose';
end

opts = beerten_cpf_default_opts();
switch lower(char(name))
    case 'paper_controls_cap_full'
        opts.cpf.stop_at = 'FULL';
    case 'paper_controls_cap_nose'
        opts.cpf.stop_at = 'NOSE';
        opts.cpf.step = 0.05;
        opts.cpf.step_max = 0.05;
        opts.vsc_mtdc.cpf_max_it = 1000;
    case 'paper_controls_cap_ac_only_nose'
        opts.cpf.stop_at = 'NOSE';
        opts.cpf.step = 0.05;
        opts.cpf.step_max = 0.05;
        opts.vsc_hvdc.enabled = false;
        opts.vsc_mtdc.capability_enforce = 0;
    case 'gen_redispatch_nose'
        opts.case_function = 'case5_vsc_mtdc_beerten_gen_redispatch';
        opts.target_function = 'case5_vsc_mtdc_beerten_gen_redispatch_target';
        opts.mode = 'vsc_mtdc';
        opts.controls.ACTAPS = 0;
        opts.controls.SWSHNT = 0;
        opts.cpf.stop_at = 'NOSE';
        opts.cpf.step = 0.05;
        opts.cpf.step_max = 0.1;
        opts.vsc_mtdc.cpf_max_lam = 10;
        opts.vsc_mtdc.cpf_max_it = 1000;
        opts.vsc_mtdc.capability_enforce = 0;
        opts.vsc_mtdc.capability_gen_enforce = 0;
        opts.policy.disable_hvdc_redispatch_for_full_trace = false;
        opts.policy.disable_vsc_derating_for_full_trace = false;
    case 'gen_redispatch_ac_only_nose'
        opts = beerten_cpf_preset('gen_redispatch_nose');
        opts.mode = 'regular';
        opts.vsc_hvdc.enabled = false;
    otherwise
        error('beerten_cpf_preset:unknown_preset', ...
            'Unknown Beerten CPF preset ''%s''.', name);
end
end
