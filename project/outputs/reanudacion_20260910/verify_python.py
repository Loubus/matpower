import importlib.util
import pathlib
import shutil
import sys
import numpy
import PIL
root=pathlib.Path.cwd()
p=root/'auditoria_psse_matpower/transpa_reduccion/plot_cpf_genq_curves.py'
spec=importlib.util.spec_from_file_location('cpf_plots',p)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
out=root/'outputs/reanudacion_20260910/python_plots'
out.mkdir(exist_ok=True)
for name in ['cpf_lambda.csv','cpf_vmag.csv','cpf_bus_meta.csv','curve_sets.csv','summary_metrics.csv','event_counts.csv','genq_final_control.csv']:
    shutil.copy2(m.OUTDIR/name,out/name)
m.OUTDIR=out
print(sys.version, 'numpy',numpy.__version__,'Pillow',PIL.__version__,flush=True)
m.main()
