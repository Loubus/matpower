function run_regressions(outdir)
addpath('outputs/algorithm_cleanup_batch5_20260911/saturation_followup_01');
names={'t_beerten_reporting_batch6','t_control_acceptance_batch1','t_control_handoff_batch2', ...
 't_control_saturation_batch5','t_pqbrak_off_batch5','t_cpf','t_mpxt_psse','t_vsc_mtdc','t_beerten_capability_batch6'};
for k=1:numel(names)
 dest=fullfile(outdir,names{k});
 if ismember(k,[2 3 4 5 9])
  run_batch5_suite(names{k},dest,fullfile(dest,'evidence'));
 else
  run_batch5_suite(names{k},dest);
 end
end
end
