function b17_derived_report
folder=fileparts(mfilename('fullpath')); derived=struct;
for st=[100 50]
    a=load(fullfile(folder,sprintf('step_%03d.mat',st)));
    z=a.result.cpf.z; tangent_lambda=nan(1,size(z,2));
    for k=1:size(z,2), tangent_lambda(k)=z(find(isfinite(z(:,k)),1,'last'),k); end
    crossing=find(tangent_lambda(1:end-1)>0 & tangent_lambda(2:end)<0)+1;
    item=struct('tangent_lambda',tangent_lambda,'sign_change_indices',crossing, ...
        'sign_change_lambda',a.result.cpf.lam(crossing),'exact_nose_localized',false);
    derived.(sprintf('step_%03d',st))=item;
end
c=idx_vsc; derived.C3_fixed_PQ_voltage_threshold=hypot(a.base.vsc(3,c.PAC_SET),a.base.vsc(3,c.QAC_SET))/150;
d=load(fullfile(folder,'diagnostic_step_100.mat')); o=load(fullfile(folder,'step_100.mat'));
fields={'lam','bus','vsc','gen','branch'}; eq=struct;
for k=1:numel(fields), f=fields{k};eq.(f)=isequaln(d.result.cpf.(f),o.result.cpf.(f));end
derived.logging_replay_exact=eq;
fid=fopen(fullfile(folder,'derived_diagnostics.json'),'w');fprintf(fid,'%s',jsonencode(derived,PrettyPrint=true));fclose(fid);
disp(derived.C3_fixed_PQ_voltage_threshold);disp(derived.step_100.sign_change_indices);disp(derived.step_050.sign_change_indices);
end
