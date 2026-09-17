function postprocess()
out=fileparts(mfilename('fullpath'));root=fileparts(fileparts(fileparts(out)));
s=load(fullfile(out,'verification_03','pqbrak_evidence','evidence.mat'));
inputs=load(fullfile(out,'nose_03','inputs.mat'));
restored_options=inputs.options;
restored_options.cpf.stop_at=inputs.original_options.cpf.stop_at;
restored_options.vsc_mtdc.psse_control_limit=inputs.original_options.vsc_mtdc.psse_control_limit;
restored_options.v=inputs.original_options.v;
if isfield(inputs.original_options.exp,'psse_pqbrak')
    restored_options.exp.psse_pqbrak=inputs.original_options.exp.psse_pqbrak;
else
    restored_options.exp=rmfield(restored_options.exp,'psse_pqbrak');
end
assert(isequaln(restored_options,inputs.original_options),'Unexpected option change');
fid=fopen(fullfile(out,'option_changes.json'),'w');
fprintf(fid,'%s\n',jsonencode(struct('changes',{{'cpf.stop_at: 0.8 -> NOSE', ...
    'vsc_mtdc.psse_control_limit: stop -> saturate', ...
    'exp.psse_pqbrak: absent (historically on) -> 0', 'option schema v26 -> v27'}}, ...
    'all_other_options_identical',true),'PrettyPrint',true));fclose(fid);
r=s.evidence.step100;
summary=struct('termination',r.cpf.termination,'convergence',r.convergence, ...
    'vm5',r.bus(5,8),'p5',r.bus(5,3),'q5',r.bus(5,4), ...
    'tap',r.branch(9,9),'pqbrak',r.psse.pqbrak, ...
    'capability_audit',s.evidence.nose_capability_audit, ...
    'localized_controls',s.evidence.localized_nose_controls,'steps',[]);
for name={'step100','step50','step25'}
    a=s.evidence.(name{1});
    row=struct('step',a.cpf.default_step,'lambda',a.cpf.lam(end), ...
        'vm5',a.bus(5,8),'tangent_lambda',a.cpf.z(end,end), ...
        'residual',a.convergence.max_mismatch,'accepted_points',numel(a.cpf.lam));
    summary.steps=[summary.steps row];
end
fid=fopen(fullfile(out,'final_summary.json'),'w');fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));fclose(fid);
fig=figure('Visible','off','Color','w','Theme','light','Position',[100 100 1000 650]);
cleanup=onCleanup(@()close(fig));
plot(r.cpf.lam,squeeze(r.cpf.bus(5,8,:)),'o-','LineWidth',1.4,'MarkerSize',3);hold on;
plot(r.cpf.lam(end),r.bus(5,8),'ro','MarkerFaceColor','r','MarkerSize',7);
set(gca,'Color','w','XColor','k','YColor','k','FontSize',12);
xlabel('Loading parameter lambda');ylabel('Bus 5 voltage (pu)');grid on;
title({'Beerten CPF: PQBRAK off, automatic controls', ...
    sprintf('Detected model nose: lambda %.8f, V_5 %.6f pu',r.cpf.lam(end),r.bus(5,8))},'Color','k');
subtitle('Original enforcement settings retained; equipment limits are exceeded','Color','k');
exportgraphics(fig,fullfile(out,'beerten_pv.png'),'Resolution',180);
files={'matpower/lib/mpoption.m','matpower/lib/+mp/psse_prepare_case.m', ...
    'matpower/lib/+mp/psse_pqbrak_prepare.m','matpower/lib/+mp/psse_coordinated_active_set.m', ...
    'matpower/lib/+mp/psse_solver_options.m','matpower/lib/runcpf_vsc_mtdc.m', ...
    'tests/t_pqbrak_off_batch5.m'};
analysis=struct('file',{},'issues',{});
for k=1:numel(files)
    analysis(k)=struct('file',files{k},'issues',checkcode(fullfile(root,files{k}),'-id'));
end
fid=fopen(fullfile(out,'code_analysis.json'),'w');fprintf(fid,'%s\n',jsonencode(analysis,'PrettyPrint',true));fclose(fid);
disp(summary.steps);disp(summary.capability_audit);
end
