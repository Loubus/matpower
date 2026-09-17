from pathlib import Path
root=Path(__file__).resolve().parents[2]
src=(root/'tests/t_ultc_beerten_batch3.m').read_text()
src=src.replace('t_ultc_beerten_batch3','t_swshunt_beerten_batch4').replace('T_ULTC_BEERTEN_BATCH3','T_SWSHUNT_BEERTEN_BATCH4')
src=src.replace('Short Beerten controls-active PF/CPF physical gate.','Short Beerten shunt-only and combined PF/CPF physical gate.')
src=src.replace("s=mp.psse_xfmr_states(f); c=idx_vsc;", "c=idx_vsc;")
start=src.index('    target=f;')
end=src.index("    cop=",start)
src=src[:start]+'''    f=loadcase('case5_vsc_mtdc_beerten_ultc_swshunt');
    if scenario==1
        label='shunt_only'; f.psse=rmfield(f.psse,'xfmr'); s=[];
    else
        label='combined'; s=mp.psse_xfmr_states(f);
    end
    sh=mp.psse_swshunt_states(f);
    target=f; target.bus(5,[3 4])=5*f.bus(5,[3 4]); stop=.4;
'''+src[end:]
start=src.index("    check([label '.policy']")
end=src.index('    fixed=cell',start)
src=src[:start]+'''    check([label '.policy'],strcmp(r.cpf.active_set_failure_policy.psse_control.declared_policy,'stop') && ...
        ~any(contains({r.cpf.events.name},'FREEZE')), 'controls active with original stop policy and no freeze event');
    if scenario==2
        check([label '.initial_tap'],any(abs(r.cpf.branch(s.branch_idx,9,1)-f.branch(s.branch_idx,9))>1e-10), ...
            'combined controls normalize the original off-grid tap and electrically correct it');
    end
    check([label '.shunt_event'],any(abs(diff(squeeze(r.cpf.bus(5,6,:))))>1e-9) && ...
        any(strcmp({r.cpf.events.name},'PSSE_CONTROL') & [r.cpf.events.k]>0), ...
        'a post-base switched-shunt event is accepted after electrical correction');
'''+src[end:]
start=src.index('        taps=r.cpf.branch')
end=src.index("        check([tag '.generator_bounds']",start)
src=src[:start]+'''        if scenario==2
            taps=r.cpf.branch(s.branch_idx,9,k);
            check([tag '.tap_grid'],all(arrayfun(@(j) min(abs(s.states_tap{j}-taps(j)))<1e-10,1:s.n)), ...
                'accepted taps remain on original grid');
        else
            check([tag '.fixed_tap'],isequal(r.cpf.branch(:,9,k),f.branch(:,9)), ...
                'shunt-only fixture retains fixed transformer ratios');
        end
        current_b=r.cpf.bus(sh.bus_idx,6,k)-sh.base_bs(sh.bus_idx);
        check([tag '.shunt_grid'],all(arrayfun(@(j) min(abs(sh.states{j}-current_b(j)))<1e-10,1:sh.n)), ...
            'every accepted shunt state is on unchanged finite RAW grid');
        check([tag '.shunt_injection'],all(isfinite(current_b.*r.cpf.bus(sh.bus_idx,8,k).^2)), ...
            'local-voltage-squared reactive injection is finite; nodal balance independently includes bus BS');
'''+src[end:]
start=src.index("    check([label '.raw_sync']")
end=src.index('    half=',start)
src=src[:start]+'''    check([label '.raw_sync'],max(abs(r.psse.swshunt.num(:,sh.binit_col)+sh.base_bs(sh.bus_idx)-r.bus(sh.bus_idx,6)))<1e-10, ...
        'RAW BINIT plus original fixed susceptance equals exported BS');
'''+src[end:]
src=src.replace("max(abs(half.branch(:,9)-r.branch(:,9)))<1e-10", "max(abs(half.branch(:,9)-r.branch(:,9)))<1e-10 && ...\n        max(abs(half.bus(:,6)-r.bus(:,6)))<1e-10")
src=src.replace("struct('target',target", "struct('base',f,'target',target")
(root/'tests/t_swshunt_beerten_batch4.m').write_text(src)
