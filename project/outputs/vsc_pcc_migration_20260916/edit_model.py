from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
def read(p): return (ROOT/p).read_text(encoding='utf-8-sig')
def write(p,s):
    f=ROOT/p; b=OUT/'before'/p
    if f.exists() and not b.exists():
        b.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(f,b)
    f.write_text(s,encoding='utf-8')
def replace(s,a,b):
    assert a in s,a[:100]
    return s.replace(a,b)

p='matpower/lib/runpf_vsc_mtdc_unified.m'; s=read(p)
s=replace(s,'model = build_unified_model(mpc, ac, map, Gdc, idx);','''model = build_unified_model(mpc, ac, map, Gdc, idx);
% Station PCC power is the negative transformer sending-end flow.
model.Yport = sparse(size(mpc.vsc, 1), size(ac.bus, 1));
model.Cport = model.Yport;
for k = model.active'
    br = find(ac.branch(:, idx.F_BUS) == map.pcc(k) & ...
        ac.branch(:, idx.T_BUS) == map.filter(k), 1);
    model.Yport(k, :) = -Yf(br, :);
    model.Cport(k, map.pcc(k)) = 1;
end''')
start=s.index('Sspec = Sbase;',s.index('function [F, eval] = unified_mismatch'))
end=s.index('vac_internal = ones',start)
s=s[:start]+'''% Keep internal power variables for bridge balance, but impose P/Q orders
% on the measured PCC transformer flow. Auxiliary-node KCL is unchanged.
Scalc = V .* conj(Ybus * V);
Spcc = (model.Cport * V) .* conj(model.Yport * V);
mis = Scalc - Sbase;
qac = zeros(size(vsc, 1), 1);
for k = model.active'
    internal = model.map.internal(k);
    qac(k) = baseMVA * imag(Scalc(internal) - Sbase(internal));
    if model.fixed_pac(k)
        pac(k) = baseMVA * real(Scalc(internal) - Sbase(internal));
        mis(internal) = real(Spcc(k)) - vsc(k, c.PAC_SET)/baseMVA ...
            + 1j*imag(mis(internal));
    else
        mis(internal) = mis(internal) - pac(k)/baseMVA;
    end
    if vsc(k, c.AC_MODE) == c.VSC_AC_Q || vsc(k, c.AC_MODE) == c.VSC_AC_PQ
        mis(internal) = real(mis(internal)) + ...
            1j*(imag(Spcc(k)) - vsc(k, c.QAC_SET)/baseMVA);
    end
end

''' + s[end:]
s=replace(s,"'Scalc', Scalc, 'Pnet', Pnet, 'Idc', I);","'Scalc', Scalc, 'Pnet', Pnet, 'Idc', I, ...\n    'ps', real(Spcc)*baseMVA, 'qs', imag(Spcc)*baseMVA);")
start=s.index('dQac = zeros(nv, nx);',s.index('function J = unified_jacobian'))
end=s.index('dUc = zeros',start)
s=s[:start]+'''% Derivatives of S_PCC = C*V .* conj(Yport*V), including phase shift
% and branch charging. Never substitute internal voltage for PCC voltage.
V = eval.V;
Dn = spdiags(V ./ abs(V), 0, length(V), length(V));
Dv = spdiags(V, 0, length(V), length(V));
Cv = spdiags(model.Cport*V, 0, nv, nv);
Di = spdiags(conj(model.Yport*V), 0, nv, nv);
dSsVa = 1j*(Di*model.Cport*Dv - Cv*conj(model.Yport*Dv));
dSsVm = Di*model.Cport*Dn + Cv*conj(model.Yport*Dn);
dQac = zeros(nv, nx);
for k = model.active'
    internal = model.map.internal(k);
    dQac(k, col_va) = baseMVA * imag(dS_dVa(internal, model.nonref));
    dQac(k, col_vm) = baseMVA * imag(dS_dVm(internal, model.vm_vars));
    if model.fixed_pac(k)
        dPac(k, col_va) = baseMVA * real(dS_dVa(internal, model.nonref));
        dPac(k, col_vm) = baseMVA * real(dS_dVm(internal, model.vm_vars));
        r = row_p(model.nonref == internal);
        J(r, col_va) = real(dSsVa(k, model.nonref));
        J(r, col_vm) = real(dSsVm(k, model.vm_vars));
    end
    if vsc(k, c.AC_MODE) == c.VSC_AC_Q || vsc(k, c.AC_MODE) == c.VSC_AC_PQ
        r = row_q(model.qeq == internal);
        J(r, col_va) = imag(dSsVa(k, model.nonref));
        J(r, col_vm) = imag(dSsVm(k, model.vm_vars));
    end
end

''' +s[end:]
s=replace(s,'r.vsc(ctx.model.pac_vars, c.PAC)','r.vsc(ctx.model.pac_vars, c.PCONV)')
s=replace(s,'c.REACTOR_BRANCH - size(vsc, 2)','c.QCONV - size(vsc, 2)')
s=replace(s,'if size(vsc, 2) < c.REACTOR_BRANCH','if size(vsc, 2) < c.QCONV')
s=replace(s,'vsc_out(:, c.PAC:c.REACTOR_BRANCH) = 0;','vsc_out(:, c.PAC:c.QCONV) = 0;')
s=replace(s,'vsc_out(active, c.PAC) = eval.pac(active);','vsc_out(active, c.PAC) = eval.ps(active);\nvsc_out(active, c.PCONV) = eval.pac(active);')
s=replace(s,'vsc_out(active, c.QAC) = eval.qac(active);','vsc_out(active, c.QAC) = eval.qs(active);\nvsc_out(active, c.QCONV) = eval.qac(active);')
s=replace(s,"'pac', eval.pac, ...\n    'qac', eval.qac, ...","'pac', eval.ps, ...\n    'qac', eval.qs, ...\n    'pconv', eval.pac, ...\n    'qconv', eval.qac, ...")
# Fill station loss reporting from the same solved branch flows.
s=replace(s,'results.vsc_state = eval_to_state(mpc, ctx.map_ext, ctx.map, eval, ctx.idx);','''results.vsc_state = eval_to_state(mpc, ctx.map_ext, ctx.map, eval, ctx.idx);
c = ctx.idx.c;
for k = ctx.model.active'
    tr = ctx.map_ext.tr_branch(k); rr = ctx.map_ext.reactor_branch(k);
    pt = sum(results.ac.branch(tr, [ctx.idx.PF ctx.idx.PT]));
    pr = sum(results.ac.branch(rr, [ctx.idx.PF ctx.idx.PT]));
    results.vsc(k, [c.PTR_LOSS c.PREACTOR_LOSS]) = [pt pr];
    results.vsc_state.ptr_loss(k) = pt;
    results.vsc_state.preactor_loss(k) = pr;
end
results.vsc_power_port = 'PCC';''')
write(p,s)

p='matpower/lib/idx_vsc.m'; s=read(p)
s=s.replace('Pac > 0 is active power injection into the AC network.','Pac/Qac > 0 is power injection at the station PCC into the AC grid.')
s=s.replace('Ploss >= 0 and Pac + Pdc + Ploss = 0.','Ploss >= 0 and Pconv + Pdc + Ploss = 0.\n%     Pac additionally excludes transformer, filter and reactor losses.')
s=s.replace('active power set point or initial value (MW)','PCC active power set point or initial value (MW)').replace('reactive power set point (MVAr)','PCC reactive power set point (MVAr)')
s=s.replace('active power injection into AC network (MW)','PCC active power injection into AC grid (MW)').replace('reactive power injection into AC network (MVAr)','PCC reactive power injection into AC grid (MVAr)')
s=s.replace('columns 30-44','columns 30-46')
s=s.replace('%   AC control mode codes:', '%   45  PCONV            internal converter active injection (MW)\n%   46  QCONV            internal converter reactive injection (MVAr)\n%\n%   AC control mode codes:')
s=s.replace("    'VSC_AC_Q',         1,", "    'PCONV',           45, ... %% internal converter active injection (MW)\n    'QCONV',           46, ... %% internal converter reactive injection (MVAr)\n    'VSC_AC_Q',         1,")
write(p,s)

p='matpower/lib/runcpf_vsc_mtdc.m'; s=read(p)
s=s.replace('r.vsc(ctx.model.pac_vars, c.PAC)','r.vsc(ctx.model.pac_vars, c.PCONV)')
start=s.index('        TorF = 0;',s.index('function TorF = vsc_capability_definitely_no_action'))
end=s.index('    function val = finite_or_zero',start)
s=s[:start]+'''        % Use the same full station constraints as the projection. A separate
        % lumped-impedance prefilter can silently skip filter-aware violations.
        [sat, ~, ~, ~, info] = vsc_capability_curve(P, Q, params.Smax, ...
            V, vsc_row, params.mode, params.Vmax, mpcb.baseMVA);
        TorF = ~sat && info.margin > tol;
    end

'''+s[end:]
write(p,s)
