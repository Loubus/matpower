from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
files = ['calc_vsc_losses.m', 'runpf_vsc_mtdc.m', 'runpf_vsc_mtdc_unified.m',
         'update_vsc_state.m', 'savecase.m', 'runcpf_vsc_mtdc.m', 'idx_vsc.m']
for name in files:
    src = root / 'matpower/lib' / name
    dst = out / 'before/matpower/lib' / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists():
        shutil.copy2(src, dst)

def edit(name, old, new, count=1):
    p = root / 'matpower/lib' / name
    s = p.read_text(encoding='utf-8')
    assert s.count(old) == count, (name, old, s.count(old))
    p.write_text(s.replace(old,new), encoding='utf-8')

edit('calc_vsc_losses.m',
     'function [Ploss, Iac] = calc_vsc_losses(baseMVA, Pconv, Qconv, Uconv, vsc)',
     'function [Ploss, Iac] = calc_vsc_losses(baseMVA, Pconv, Qconv, Uconv, vsc, mpc)')
edit('calc_vsc_losses.m', 'c = idx_vsc;',
     "if nargin < 6, mpc = struct; end\nc = idx_vsc;")
edit('calc_vsc_losses.m',
     'Ploss = vsc(:, c.LOSS_A) + vsc(:, c.LOSS_B) .* Iac + vsc(:, c.LOSS_C) .* Iac.^2;',
     'C = vsc_loss_coefficients(vsc, Pconv, mpc);\nPloss = vsc(:, c.LOSS_A) + vsc(:, c.LOSS_B) .* Iac + C .* Iac.^2;')
for name, count in [('runpf_vsc_mtdc.m',2),('update_vsc_state.m',1),('runpf_vsc_mtdc_unified.m',1)]:
    edit(name, 'state.qac, state.vac_internal, vsc);',
         'state.qac, state.vac_internal, vsc, mpc);', count)
edit('runpf_vsc_mtdc_unified.m',
     'calc_vsc_losses(baseMVA, pac, qac, vac_internal, vsc);',
     'calc_vsc_losses(baseMVA, pac, qac, vac_internal, vsc, mpc);')
edit('runpf_vsc_mtdc_unified.m',
     "dPloss = zeros(nv, nx);\n\nfor k = model.active'",
     "dPloss = zeros(nv, nx);\n[C, dC_dP] = vsc_loss_coefficients(vsc, eval.pac, mpc);\n\nfor k = model.active'")
edit('runpf_vsc_mtdc_unified.m',
     'dL_dI = vsc(k, c.LOSS_B) + 2 * vsc(k, c.LOSS_C) * I;',
     'dL_dI = vsc(k, c.LOSS_B) + 2 * C(k) * I;')
edit('runpf_vsc_mtdc_unified.m',
     'dI_dQ * dQac(k, :) + dI_dU * dUc(k, :));',
     'dI_dQ * dQac(k, :) + dI_dU * dUc(k, :)) + ...\n        I^2 * dC_dP(k) * dPac(k, :);')
edit('savecase.m', "if isfield(mpc, 'vsc_capability') && ...",
     "if isfield(mpc, 'vsc_loss')\n    fprintf(fd, '\\n%%%% VSC directional loss metadata\\n');\n    print_case_value(fd, sprintf('%svsc_loss', prefix), mpc.vsc_loss);\nend\n\nif isfield(mpc, 'vsc_capability') && ...")
