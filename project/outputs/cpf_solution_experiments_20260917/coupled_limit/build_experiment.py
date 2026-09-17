from pathlib import Path
import difflib
out=Path(__file__).resolve().parent
root=out.parents[2]
def replace(s,a,b):
    assert s.count(a)==1,(a[:100],s.count(a))
    return s.replace(a,b)
src=(root/'matpower/lib/runpf_vsc_mtdc_unified.m').read_text()
s=src.replace('runpf_vsc_mtdc_unified','exa_pf')
s=replace(s,"eval = struct('V', V, 'Va', Va, 'Vm', Vm, 'pac', pac, 'qac', qac, ...", """% Experiment A: physical converter-current row replaces the AC Q row.
if isfield(mpc,'exa_current_ilim')
    for k=find(mpc.exa_current_ilim(:)>0)'
        row=length(model.nonref)+find(model.qeq==model.map.internal(k));
        assert(isscalar(row),'Current limit must replace exactly one Q equation.');
        F(row)=iac(k)^2/mpc.exa_current_ilim(k)^2-1;
    end
end
eval = struct('V', V, 'Va', Va, 'Vm', Vm, 'pac', pac, 'qac', qac, ...""")
s=replace(s,'dPloss = converter_loss_derivatives(mpc, model, eval, dPac, dQac, dUc, idx);',"""% Analytic derivative of (Pconv^2+Qconv^2)/(baseMVA*Uc*Ilim)^2 - 1.
if isfield(mpc,'exa_current_ilim')
    for k=find(mpc.exa_current_ilim(:)>0)'
        row=length(model.nonref)+find(model.qeq==model.map.internal(k));
        U=eval.Vm(model.map.internal(k)); Ilim=mpc.exa_current_ilim(k);
        J(row,:)=2*(eval.pac(k)*dPac(k,:)+eval.qac(k)*dQac(k,:))/(baseMVA*U*Ilim)^2 ...
            -2*eval.iac(k)^2/(U*Ilim^2)*dUc(k,:);
    end
end
dPloss = converter_loss_derivatives(mpc, model, eval, dPac, dQac, dUc, idx);""")
(out/'exa_pf.m').write_text(s)
diff=''.join(difflib.unified_diff(src.splitlines(True),s.splitlines(True),fromfile='production/runpf_vsc_mtdc_unified.m',tofile='experiment/exa_pf.m'))
src=(root/'matpower/lib/runcpf_vsc_mtdc.m').read_text()
s=src.replace('runcpf_vsc_mtdc','exa_cpf').replace('runpf_vsc_mtdc_unified','exa_pf')
s=replace(s,"            P0 = r.vsc(k, c.PAC);", """            if isfield(current,'exa_current_ilim') && current.exa_current_ilim(k)>0
                % Already enforced in every residual/Jacobian/tangent and PF handoff.
                % No release heuristic in this bounded first prototype.
                continue;
            end
            P0 = r.vsc(k, c.PAC);""")
s=replace(s,"                [Psat, Qsat] = apply_vsc_capability_saturation_margin( ...\n                    P0, Q0, Psat, Qsat, policy, k);", """                coupled_current=strcmp(info.active_limit,'current') && ...
                    strcmp(mode,'preservar_p') && abs(Psat-P0)<=tol;
                if ~coupled_current
                    [Psat, Qsat] = apply_vsc_capability_saturation_margin( ...
                        P0, Q0, Psat, Qsat, policy, k);
                end""")
s=replace(s,"            old_vals = current.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]);\n            new_vals = [to_mode Psat Qsat];", """            old_vals = current.vsc(k, [c.AC_MODE c.PAC_SET c.QAC_SET]);
            new_vals = [to_mode Psat Qsat];
            if coupled_current
                % Retain user orders; replace the released Q equation with |Ic|=Imax.
                % DC slack stays AC-Q/DC-V: its P is still obtained from bridge balance.
                new_vals=[to_mode old_vals(2:3)];
                if ~isfield(bnext,'exa_current_ilim')
                    bnext.exa_current_ilim=zeros(size(current.vsc,1),1);
                    tnext.exa_current_ilim=bnext.exa_current_ilim;
                end
                bnext.exa_current_ilim(k)=info.Smax/current.baseMVA;
                tnext.exa_current_ilim(k)=info.Smax/current.baseMVA;
                exa_log('append',struct('kind','current_activate','lambda',lam,'converter',k, ...
                    'P',P0,'Q',Q0,'V',V0,'Ilim_system_pu',info.Smax/current.baseMVA));
            end""")
s=s.replace('            if all(abs(old_vals - new_vals) <= tol)', '            if all(abs(old_vals - new_vals) <= tol) && ~coupled_current',1)
s=replace(s,"        sig = strjoin(parts, ';');", """        if isfield(mpc,'exa_current_ilim')
            parts{end+1}=numeric_signature(mpc.exa_current_ilim);
        end
        sig = strjoin(parts, ';');""")
s=replace(s,"        vals = reshape(mpc.vsc(:, cols), [], 1);", """        vals = reshape(mpc.vsc(:, cols), [], 1);
        if isfield(mpc,'exa_current_ilim'), vals=[vals;mpc.exa_current_ilim(:)]; end""")
s=replace(s,"                profile_count('vsc_capability_recorr_failed_inner');", """                profile_count('vsc_capability_recorr_failed_inner');
                exa_log('append',struct('kind','vsc_inner_failed','lambda',lam,'normF',normF));""")
s=replace(s,"            profile_count('vsc_capability_settle_iteration');", """            profile_count('vsc_capability_settle_iteration');
            if isfield(mpcb,'exa_current_ilim')
                for ja=find(mpcb.exa_current_ilim(:)>0)'
                    [ap,~]=cached_vsc_capability_params(mpcb,ja,ja);
                    if r.vsc(ja,c.VAC_INTERNAL)>ap.Vmax+1e-8 || ...
                            abs(r.vsc(ja,c.PAC))>mpcb.exa_current_ilim(ja)*mpcb.baseMVA+1e-6
                        exa_log('append',struct('kind','unsupported_second_limit','lambda',lam, ...
                            'converter',ja,'Uc',r.vsc(ja,c.VAC_INTERNAL),'P',r.vsc(ja,c.PAC)));
                        V=original_ac_voltage_for_result(r,bus_ids); success=0; return;
                    end
                end
            end""")
# Retain detailed failure stages already available in CPF.failed and journal activations.
(out/'exa_cpf.m').write_text(s)
diff+=''.join(difflib.unified_diff(src.splitlines(True),s.splitlines(True),fromfile='production/runcpf_vsc_mtdc.m',tofile='experiment/exa_cpf.m'))
src=(root/'matpower/lib/runcpf_psse.m').read_text(); s=src.replace('runcpf_psse','exa_psse').replace('runcpf_vsc_mtdc','exa_cpf')
(out/'exa_psse.m').write_text(s)
diff+=''.join(difflib.unified_diff(src.splitlines(True),s.splitlines(True),fromfile='production/runcpf_psse.m',tofile='experiment/exa_psse.m'))
(out/'experiment.diff').write_text(diff)
audit=(root/'outputs/ultc_swshunt_g2_150mw_20260916/g150_audit_trace.m').read_text().replace('g150_audit_trace','exa_audit_trace')
(out/'exa_audit_trace.m').write_text(audit)
print('Built uniquely named experimental copies; analytic current row, unchanged fixed-lambda transition correction.')


