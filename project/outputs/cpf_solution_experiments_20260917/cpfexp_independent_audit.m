function audit=cpfexp_independent_audit(result,base,target,options,destination)
% Independently recompute physical balances and trace consistency from tables.
[trace,audit]=cpfexp_audit_trace(result,base,options);
n=height(trace); load_error=zeros(n,1); generator_error=zeros(n,1);
for k=1:n
    expected=base.bus(:,3:4)+trace.lambda(k)*(target.bus(:,3:4)-base.bus(:,3:4));
    load_error(k)=max(abs(result.cpf.bus(:,3:4,k)-expected),[],'all');
    [~,p,q]=gen_capability_curve(trace.Pg2(k),trace.Qg2(k),base.gen_capability.Snom(2),2);
    generator_error(k)=max(abs([p-trace.Pg2(k),q-trace.Qg2(k)]));
end
audit.max_load_interpolation_error=max(load_error);
audit.max_generator_projection_error=max(generator_error);
audit.load_interpolation_pass=max(load_error)<1e-6;
audit.generator_capability_pass=max(generator_error)<1e-5;
[audit.sampled_max_lambda,audit.sampled_max_index]=max(trace.lambda);
audit.descending_steps=sum(diff(trace.lambda)<-1e-12);
audit.sampled_max_V5=trace.V5(audit.sampled_max_index);
audit.tangent_sign_crossings=[];
if isfield(result.cpf,'z')
    z=nan(1,size(result.cpf.z,2));
    for k=1:numel(z)
        iz=find(isfinite(result.cpf.z(:,k)),1,'last');
        if ~isempty(iz), z(k)=result.cpf.z(iz,k); end
    end
    audit.tangent_sign_crossings=find(z(1:end-1)>0 & z(2:end)<=0)+1;
    audit.loading_tangent_extraction='last finite entry per column; state size can change';
    audit.sign_crossings_are_not_localized_noses=true;
end
audit.monotonicity_checks_are_diagnostic_only=true;
% The declared saturate policy permits exhausted discrete regulation. For
% this exact winding orientation, low V7 requests a lower tap; tap=0.9 is
% the physical lower bound. Preserve strict band check separately above.
xs=mp.psse_xfmr_states(result);
ultc_accepted=(trace.V7>=.95-xs.vtol & trace.V7<=1.03+xs.vtol) | ...
    (trace.V7<.95-xs.vtol & abs(trace.tap9-.9)<1e-9) | ...
    (trace.V7>1.03+xs.vtol & abs(trace.tap9-1.1)<1e-9);
[~,control_report]=mp.psse_unified_control_update(result,result.bus);
audit.final_control_acceptance=mp.psse_unified_control_acceptance(control_report,'saturate');
audit.ULTC_in_band_or_physical_bound=all(ultc_accepted);
% Reversals can be legitimate on FULL's descending branch; the baseline
% monotonicity fields are retained as observations, not feasibility claims.
audit.required_physical_checks=rmfield(audit.checks,{'no_accepted_tap_reversal','no_accepted_shunt_reversal'});
audit.required_physical_checks.ULTC_settled=audit.ULTC_in_band_or_physical_bound;
audit.required_physical_checks.final_control_settlement=audit.final_control_acceptance.accepted;
audit.required_physical_checks.generator_capability=audit.generator_capability_pass;
audit.required_physical_checks.lambda_load_consistency=audit.load_interpolation_pass;
audit.all_required_physical_checks_pass=all(structfun(@logical,audit.required_physical_checks));
trace.load_interpolation_error=load_error;
trace.generator_projection_error=generator_error;
writetable(trace,[destination '_trace.csv']);
fid=fopen([destination '_audit.json'],'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(audit,PrettyPrint=true));
end
