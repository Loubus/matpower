function probe_legacy_full
mpcpap=loadcase('case5_vsc_mtdc_beerten_paper_controls_cap_explicit');
mpctpap=loadcase('case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit');
mpopt=mpoption('out.all',0,'verbose',0);
mpcpap_full = mpcpap;
mpctpap_full = mpctpap;
mpcpap_full.cpf_policies.hvdc.policy = 'none';
mpctpap_full.cpf_policies.hvdc.policy = 'none';
mpcpap_full.explicit_options.cpf_policies.hvdc.policy = 'none';
mpctpap_full.explicit_options.cpf_policies.hvdc.policy = 'none';
mpcpap_full.cpf_policies.hvdc.vsc_derating.enabled = 0;
mpctpap_full.cpf_policies.hvdc.vsc_derating.enabled = 0;
mpcpap_full.explicit_options.cpf_policies.hvdc.vsc_derating.enabled = 0;
mpctpap_full.explicit_options.cpf_policies.hvdc.vsc_derating.enabled = 0;
mpopt_pap_full = mpoption(mpopt, 'cpf.stop_at', 'FULL', ...
    'cpf.step', 0.025, 'cpf.step_min', 1e-7, ...
    'cpf.step_max', 0.025, 'cpf.adapt_step', 1);
mpopt_pap_full.vsc_mtdc.method = 'unified';
mpopt_pap_full.vsc_mtdc.cpf_max_lam = 20;
mpopt_pap_full.vsc_mtdc.cpf_max_it = 900;
mpopt_pap_full.vsc_mtdc.capability_enforce = 1;
mpopt_pap_full.vsc_mtdc.capability_gen_enforce = 1;
mpopt_pap_full.vsc_mtdc.capability_max_it = 10;
mpopt_pap_full.vsc_mtdc.capability_limit = 'freeze';
mpopt_pap_full.vsc_mtdc.psse_control_limit = 'freeze';
[rpap_full, success] = runcpf_psse(mpcpap_full, mpctpap_full, ...
    mpopt_pap_full);

save(fullfile(fileparts(mfilename('fullpath')),'legacy_full_probe.mat'),'rpap_full','mpcpap_full','mpctpap_full','mpopt_pap_full','success','-v7.3');
disp(rpap_full.cpf.termination);disp(rpap_full.cpf.done_msg);disp({rpap_full.cpf.events.name});
end
