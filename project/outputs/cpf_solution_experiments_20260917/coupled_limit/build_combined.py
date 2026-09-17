from pathlib import Path
import subprocess,sys,hashlib,json
p=Path(__file__).resolve().parent
q=p/'combined';q.mkdir(exist_ok=True)
script=(p/'build_experiment.py').read_text().replace("root=out.parents[2]","root=out.parents[3]")
script=script.replace("src=(root/'matpower/lib/runcpf_vsc_mtdc.m').read_text()", "src=(root/'outputs/cpf_solution_experiments_20260917/continuation_limit/b17_cpf.m').read_text().replace('b17_cpf','runcpf_vsc_mtdc').replace('b17_journal','exc_transition_journal')")
script=script.replace('exa_','exc_')
(q/'build_combined_copies.py').write_text(script)
subprocess.run([sys.executable,str(q/'build_combined_copies.py')],check=True)
(q/'exc_log.m').write_text((p/'exa_log.m').read_text().replace('exa_','exc_'))
root=p.parents[2]
jb=root/'outputs/cpf_solution_experiments_20260917/continuation_limit/b17_journal.m'
(q/'exc_transition_journal.m').write_text(jb.read_text().replace('b17_journal','exc_transition_journal'))
run=(p/'run_experiment.m').read_text().replace('function run_experiment(step)','function exc_run(step)').replace('exa_','exc_')
run=run.replace("root=fileparts(fileparts(fileparts(out)));","root=fileparts(fileparts(fileparts(fileparts(out))));")
run=run.replace("exc_log('reset');", "exc_log('reset'); exc_transition_journal('reset');")
run=run.replace("journal=exc_log('read');", "journal=exc_log('read'); transitions=exc_transition_journal('get');")
run=run.replace("'warning_id','journal','-v7.3'", "'warning_id','journal','transitions','-v7.3'")
run=run.replace('audit.journal=journal;', 'audit.journal=journal; audit.transitions=transitions;')
(q/'exc_run.m').write_text(run)
(q/'source_hashes.json').write_text(json.dumps({str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in [p/'build_experiment.py',jb.parent/'b17_cpf.m',jb]},indent=2))
print('Combined A current row plus B incoming-direction augmented transition correction ready.')
