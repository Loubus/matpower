function probe_legacy_freeze
out=fileparts(mfilename('fullpath'));
backup=fullfile(out,'before','matpower','lib');
records={};
for old=[false true]
    if old, addpath(backup,'-begin'); end
    cleanup=onCleanup(@()restore(backup,old));
    clear_solvers;
    f=case5_vsc_mtdc_beerten_paper_controls_cap_explicit;
    t=case5_vsc_mtdc_beerten_paper_controls_cap_target_explicit;
    f.vsc_capability.Snom=500*ones(1,size(f.vsc,1));t.vsc_capability.Snom=f.vsc_capability.Snom;
    f.gen_capability.Snom=[500 90];t.gen_capability.Snom=[500 90];t.gen(2,2)=100;
    o=mpoption('verbose',0,'out.all',0,'cpf.stop_at','NOSE','cpf.step',.1, ...
        'cpf.step_min',1e-4,'cpf.step_max',.1,'cpf.adapt_step',0,'cpf.parameterization',3);
    o.vsc_mtdc.method='unified'; o.vsc_mtdc.cpf_max_lam=4; o.vsc_mtdc.cpf_max_it=160;
    o.vsc_mtdc.capability_enforce=1;o.vsc_mtdc.capability_gen_enforce=1;
    o.vsc_mtdc.capability_limit='freeze';o.vsc_mtdc.capability_vsc_limit='stop';
    o.vsc_mtdc.capability_gen_limit='freeze';o.vsc_mtdc.capability_gen_max_it=1;
    r=runcpf_vsc_mtdc(f,t,o);
    lam=NaN; if ~isempty(r.cpf.lam), lam=r.cpf.lam(end); end
    rec=struct('pre_migration',old,'success',r.success,'cause',r.cpf.termination.cause, ...
        'done_msg',r.cpf.done_msg,'lambda',lam,'policy',r.cpf.active_set_failure_policy, ...
        'events',{ {r.cpf.events.name} });
    records{end+1}=rec;
    fprintf('PRE_MIGRATION=%d success=%d lambda=%g cause=%s\n%s\n',old,r.success,lam,r.cpf.termination.cause,r.cpf.done_msg);
    clear cleanup;
end
fid=fopen(fullfile(out,'legacy_freeze_comparison.json'),'w');fprintf(fid,'%s',jsonencode(records,PrettyPrint=true));fclose(fid);
end
function restore(backup,old)
if old, rmpath(backup); end
clear_solvers;
end
function clear_solvers
clear runpf_vsc_mtdc runpf_vsc_mtdc_unified runcpf_vsc_mtdc idx_vsc ...
    update_vsc_state apply_vsc_ac_model vsc_capability_curve vsc_capability_geometry ...
    vsc_capability_policy check_vsc_capability enforce_vsc_capability_active_set
end
