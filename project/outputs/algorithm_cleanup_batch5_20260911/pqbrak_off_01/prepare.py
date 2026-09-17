from pathlib import Path
import hashlib, json, shutil
root=Path.cwd()
out=root/'outputs/algorithm_cleanup_batch5_20260911/pqbrak_off_01'
files=['matpower/lib/mpoption.m','matpower/lib/+mp/psse_prepare_case.m','matpower/lib/+mp/psse_pqbrak_prepare.m','matpower/lib/+mp/psse_coordinated_active_set.m','matpower/lib/+mp/psse_solver_options.m','matpower/lib/t/t_mpxt_psse.m']
baseline={}
for name in files:
    p=root/name; baseline[name]=hashlib.sha256(p.read_bytes()).hexdigest()
    b=out/'before'/name; b.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,b)
(out/'baseline.json').write_text(json.dumps(baseline,indent=2))
def edit(name,old,new):
    p=root/name; s=p.read_text(encoding='utf-8'); assert old in s,(name,old); p.write_text(s.replace(old,new),encoding='utf-8',newline='\n')
p='matpower/lib/mpoption.m'
edit(p,"%      exp.use_legacy_core", "%      exp.psse_pqbrak            0           enable PSS/E low-voltage load scaling\n%      exp.use_legacy_core")
edit(p,"            opt0.v = v;", "            if opt0.v <= 26 && ~isfield(opt0.exp, 'psse_pqbrak')\n                opt0.exp.psse_pqbrak = opt_d.exp.psse_pqbrak;\n            end\n            opt0.v = v;")
edit(p,"            'use_legacy_core', 0, ...", "            'psse_pqbrak', 0, ...\n            'use_legacy_core', 0, ...")
edit(p,'v = 26;','v = 27;')
edit(p,"%% v26  - add 'vsc_mtdc' field", "%% v26  - add 'vsc_mtdc' field\n            %% v27  - add 'exp.psse_pqbrak', disabled by default")
for p in ['matpower/lib/+mp/psse_prepare_case.m','matpower/lib/+mp/psse_coordinated_active_set.m']:
    edit(p,'mp.psse_pqbrak_prepare(mpc);','mp.psse_pqbrak_prepare(mpc, mpopt);')
p='matpower/lib/+mp/psse_coordinated_active_set.m'
edit(p,"if isnan(pqbrak) || pqbrak <= 0\n    pqbrak = 0.7;", "if ~mpce.psse.pqbrak.enabled || isnan(pqbrak) || pqbrak <= 0\n    pqbrak = 0;")
p='matpower/lib/+mp/psse_pqbrak_prepare.m'
edit(p,'function mpc = psse_pqbrak_prepare(mpc)','function mpc = psse_pqbrak_prepare(mpc, mpopt)')
edit(p,'%   MPC = MP.PSSE_PQBRAK_PREPARE(MPC)', '%   MPC = MP.PSSE_PQBRAK_PREPARE(MPC, MPOPT)\n%\n% Disabled globally by default. Explicit exp.psse_pqbrak = 1 opts in.\n% Disabling a prepared cache restores only its scaled native-load component;\n% other equivalent demands are preserved. RAW thresholds remain unchanged.')
edit(p,"pqbrak = mp.psse_system_value(mpc, 'general', 'PQBRAK', 0.7);\nif isnan(pqbrak) || pqbrak <= 0\n    return;\nend", """enabled = nargin >= 2 && isfield(mpopt, 'exp') && ...
    isfield(mpopt.exp, 'psse_pqbrak') && logical(mpopt.exp.psse_pqbrak);
pqbrak = mp.psse_system_value(mpc, 'general', 'PQBRAK', 0.7);
enabled = enabled && isfinite(pqbrak) && pqbrak > 0;
if ~enabled
    if isfield(mpc.psse, 'pqbrak')
        old = mpc.psse.pqbrak;
        if all(isfield(old, {'bus_ext', 'pd0', 'qd0', 'scale'}))
            [found, loc] = ismember(mpc.bus(:, BUS_I), old.bus_ext);
            idx = loc(found);
            mpc.bus(found, PD) = mpc.bus(found, PD) + old.pd0(idx) .* (1-old.scale(idx));
            mpc.bus(found, QD) = mpc.bus(found, QD) + old.qd0(idx) .* (1-old.scale(idx));
        end
    end
    mpc.psse.pqbrak = struct('enabled', 0, 'pqbrak', 0, ...
        'disabled_reason', 'exp.psse_pqbrak_off_or_invalid_threshold', ...
        'bus_ext', mpc.bus(:, BUS_I), 'pd0', mpc.bus(:, PD), ...
        'qd0', mpc.bus(:, QD), 'scale', ones(size(mpc.bus,1),1), ...
        'iterations', 0, 'changed_last', 0);
    return;
end""")
p='matpower/lib/+mp/psse_solver_options.m'
edit(p,'policy = empty_policy();', "pqbrak_enabled = isfield(mpopt, 'exp') && ...\n    isfield(mpopt.exp, 'psse_pqbrak') && logical(mpopt.exp.psse_pqbrak);\npolicy = empty_policy();")
edit(p,'classify_param(section, name, value)', 'classify_param(section, name, value, pqbrak_enabled)')
edit(p,'add_default_effective_entries(policy)', 'add_default_effective_entries(policy, pqbrak_enabled)')
edit(p,'classify_general(name)', 'classify_general(name, pqbrak_enabled)')
edit(p,"        reason = 'Used by the PSS/E low-voltage load scaling helper.';", "        reason = 'Used by the PSS/E low-voltage load scaling helper.';\n        if ~pqbrak_enabled\n            category = 'ignored';\n            status = 'disabled';\n            reason = 'Low-voltage load scaling disabled by exp.psse_pqbrak = 0; RAW threshold preserved.';\n        end")
edit(p,'d.section, d.name, d.value);','d.section, d.name, d.value, pqbrak_enabled);')
# Retain the historical PQBRAK-on suite as an explicit compatibility scenario.
edit('matpower/lib/t/t_mpxt_psse.m', "mpopt = mpoption('verbose', 0, 'out.all', 0);", "% Historical PSS/E modeling compatibility scenario explicitly includes PQBRAK.\nmpopt = mpoption('verbose', 0, 'out.all', 0, 'exp.psse_pqbrak', 1);")
