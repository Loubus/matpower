function evidence=t_cpf_event_release(outdir)
% Regression for solved generator contacts and reversible VSC release.
% Historical scientific results are inputs only; all runs go to OUTDIR.
if nargin<1,error('An explicit new output directory is required.');end
if ~isfolder(outdir),mkdir(outdir);end
[base,target,options]=beerten_constant_pq_nonslack_dispatch;
c=idx_vsc;checks=struct('name',{},'passed',{},'error',{});runs=struct();
for typ=1:3
    [~,lim]=gen_capability_headroom(50,0,187.5,typ);
    for q=[lim(4)-1,lim(4),0,lim(3),lim(3)+1]
        m=gen_capability_headroom(50,q,187.5,typ);
        [~,pp,qq]=gen_capability_curve(50,q,187.5,typ);
        ck(sprintf('headroom_projection_type%d_q%.4g',typ,q), ...
            (min(m)>=-1e-8)==(max(abs([pp-50 qq-q]))<1e-8),min(m));
    end
end
for step=[.1 .05]
 for endpoint={'NOSE','FULL'}
  for enabled=[0 1]
    tag=sprintf('%s_%03d_release%d',lower(endpoint{1}),round(step*1000),enabled);
    o=mpoption(options,'cpf.stop_at',endpoint{1},'cpf.step',step, ...
        'vsc_mtdc.current_limit_release',enabled);
    lastwarn('');[result,success]=runcpf_psse(base,target,o);[warning,warning_id]=lastwarn;
    save(fullfile(outdir,[tag '.mat']),'base','target','o','result','success','warning','warning_id');
    ev=result.cpf.events; ge=ev(strcmp({ev.name},'GEN_CAPABILITY'));
    contact=find(arrayfun(@(v)any(strcmp(v.active_limit,'p_max')),ge),1);
    ck([tag '_P_contact_reported'],~isempty(contact),numel(contact));
    if ~isempty(contact)
        err=abs(ge(contact).lambda_event-11/24);
        ck([tag '_P_exact_contact'],err<1e-9,err);
        ck([tag '_P_contact_on_accepted_trace'],min(abs(result.cpf.lam-11/24))<1e-9,0);
        ck([tag '_P_positive_previous_headroom'],ge(contact).margin_previous>0,ge(contact).margin_previous);
        ix=find(abs(result.cpf.lam-11/24)<1e-9,1);
        ck([tag '_P_limit_retains_PV'],~isempty(ix) && result.cpf.bus(6,2,ix)==2,0);
    end
    [peak,imax]=max(result.cpf.lam);pg=reshape(result.cpf.gen(2,2,:),1,[]);
    err=max(abs(pg(1:imax)-min(40+240*result.cpf.lam(1:imax),150)));
    ck([tag '_ascending_P_schedule'],err<1e-6,err);
    ck([tag '_first_turn_benchmark'],abs(peak-1.24566894351)<1e-7,peak);
    re=ev(strcmp({ev.name},'VSC_CURRENT_RELEASE'));
    ck([tag '_no_unlocalized_gen_contact'],all(arrayfun(@(v) ...
        strcmp(v.event_location_method{1},'solved_boundary') && abs(v.margin_event)<1e-7,ge)),0);
    if strcmp(endpoint{1},'NOSE') || ~enabled
        ck([tag '_no_release'],isempty(re),numel(re));
    else
        ck([tag '_one_release_no_cycle'],numel(re)==1,numel(re));
        if ~isempty(re)
            ck([tag '_release_current_headroom'],re(1).current_ratio_final<=.999,re(1).current_ratio_final);
            ck([tag '_release_declared_transition'],strcmp(re(1).kind,'fixed_lambda_control_transition'),0);
            ck([tag '_descending_after_release'],all(diff(result.cpf.lam(re(1).k+1:end))<=1e-8),0);
        end
    end
    if strcmp(endpoint{1},'NOSE') || enabled
        ck([tag '_requested_endpoint'],success && result.cpf.termination.requested_endpoint_reached,0);
    else
        ck([tag '_latched_FULL_not_complete'],~result.cpf.termination.requested_endpoint_reached,0);
    end
    audit=physical_audit(result,base,target,o);
    ck([tag '_physical_balance'],audit.balance_MVA<1e-5,audit.balance_MVA);
    ck([tag '_all_capability'],audit.capability_violation<1e-5,audit.capability_violation);
    ck([tag '_load_interpolation'],audit.load_error<1e-7,audit.load_error);
    ck([tag '_physical_controls'],audit.controls_accepted,audit.bad_control_points);
    if strcmp(endpoint{1},'NOSE')
        if ~enabled
            off=result;
        else
            err=max(abs(result.cpf.bus(:)-off.cpf.bus(:)));
            ck([tag '_rejected_release_restores_trace'],err==0,err);
            ck([tag '_rejected_release_restores_gen'],isequal(result.cpf.gen,off.cpf.gen),0);
        end
    end
    runs.(tag)=struct('success',success,'termination',result.cpf.termination, ...
        'peak_lambda',peak,'release_count',numel(re),'audit',audit,'warning',warning,'warning_id',warning_id);
    fprintf('%s success=%d endpoint=%d lambda=%.12g releases=%d\n',tag,success, ...
        result.cpf.termination.requested_endpoint_reached,result.cpf.lam(end),numel(re));
  end
 end
end
% Saved active-set provenance survives round-trip; unknown modes stay unknown.
q=base;q.vsc(2,c.AC_MODE)=c.VSC_AC_Q;q.vsc_current_limit=[0;1.5;0];
q.vsc_current_restore_mode=[0;c.VSC_AC_V;0];
f=fullfile(outdir,'current_release_roundtrip.m');savecase(f,q);qq=loadcase(f);
ck('restore_mode_roundtrip',isequal(q.vsc_current_restore_mode,qq.vsc_current_restore_mode),0);
% Incremental policy anchors must carry activation, release, and rollback.
po=struct('cpf_policies',struct('load',struct('k',.1), ...
    'gen',struct('policy','none'),'hvdc',struct('policy','none')));
st=vsc_mtdc_cpf_policy_state('init',base,target,po);
active=vsc_mtdc_cpf_policy_state('current_mpc',q,.2,st);
ck('incremental_activation_carries_current',isequal(active.vsc_current_limit,q.vsc_current_limit),0);
st.anchor_mpc=active;st.anchor_lam=.2;
released=q;released.vsc(2,c.AC_MODE)=c.VSC_AC_V;released.vsc_current_limit(2)=0;
restored=vsc_mtdc_cpf_policy_state('current_mpc',released,.2,st);
ck('incremental_release_restores_original_mode',restored.vsc(2,c.AC_MODE)==c.VSC_AC_V && restored.vsc_current_limit(2)==0,0);
prior=vsc_mtdc_cpf_policy_state('current_mpc',base,.1,st);
ck('incremental_prior_context_does_not_inherit_current',~isfield(prior,'vsc_current_limit'),0);
for bad={[0;NaN;0],[0;3;0],[0;2]}
    qq.vsc_current_restore_mode=bad{1};caught=false;
    try,runpf_vsc_mtdc_unified('__setup',qq,options);catch me
        caught=strcmp(me.identifier,'runpf_vsc_mtdc_unified:current_restore_mode');
    end
    ck('invalid_restore_metadata_rejected',caught,0);
end
evidence=struct('checks',checks,'passed',sum([checks.passed]),'total',numel(checks),'runs',runs);
fid=fopen(fullfile(outdir,'evidence.json'),'w');fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));fclose(fid);
fprintf('Event/release regression: %d/%d checks passed\n',evidence.passed,evidence.total);
assert(all([checks.passed]),'Event/release regression failed; inspect evidence.json');
    function ck(name,passed,err)
        checks(end+1)=struct('name',name,'passed',logical(passed),'error',err);
        if ~passed,fprintf('FAIL %s: %.12g\n',name,err);end
    end
end

function audit=physical_audit(r,b,t,o)
c=idx_vsc;balance=0;violation=0;loaderr=0;bad=0;
% Use resolved controller tolerances, including options applied at setup.
xs=mp.psse_xfmr_states(r);ss=mp.psse_swshunt_states(r);
for k=1:numel(r.cpf.lam)
    q=b;
    for fields={'bus','gen','branch','vsc','busdc','branchdc'}
        name=fields{1};q.(name)=r.cpf.(name)(:,:,k);
    end
    ac=ext2int(struct('version','2','baseMVA',q.baseMVA,'bus',q.bus,'gen',q.gen,'branch',q.branch));
    U=ac.bus(:,8).*exp(1j*pi/180*ac.bus(:,9));Y=makeYbus(ac.baseMVA,ac.bus,ac.branch);
    S=makeSbus(ac.baseMVA,ac.bus,ac.gen);Pdc=zeros(size(q.busdc,1),1);
    for j=find(q.vsc(:,c.VSC_STATUS)>0)'
        row=find(ac.order.bus.i2e==q.vsc(j,c.VSC_BUS));
        S(row)=S(row)+complex(q.vsc(j,c.PAC),q.vsc(j,c.QAC))/q.baseMVA;
        dc=find(q.busdc(:,1)==q.vsc(j,c.BUSDC));Pdc(dc)=Pdc(dc)+q.vsc(j,c.PDC);
        p=vsc_capability_params(q,o.vsc_mtdc,j,j);
        [~,~,~,~,info]=vsc_capability_curve(q.vsc(j,c.PAC),q.vsc(j,c.QAC),p.Smax, ...
            q.vsc(j,c.VAC_PCC),q.vsc(j,:),p.mode,p.Vmax,q.baseMVA);
        violation=max(violation,-info.margin);
    end
    [~,pg,qg]=gen_capability_curve(q.gen(2,2),q.gen(2,3),b.gen_capability.Snom(2),2);
    violation=max([violation abs(pg-q.gen(2,2)) abs(qg-q.gen(2,3))]);
    G=makeGdc(q.busdc,q.branchdc);
    balance=max([balance;abs(U.*conj(Y*U)-S)*q.baseMVA; ...
        abs(q.busdc(:,3).*(G*q.busdc(:,3))*q.baseMVA-Pdc); ...
        abs(q.vsc(:,c.PCONV)+q.vsc(:,c.PDC)+q.vsc(:,c.PLOSS))]);
    loaderr=max(loaderr,max(abs(q.bus(:,3:4)-b.bus(:,3:4)-r.cpf.lam(k)*(t.bus(:,3:4)-b.bus(:,3:4))),[],'all'));
    % Saved trace tables contain actual settings. The base PSSE metadata
    % contains the initial step positions and must not overwrite them.
    tap=q.branch(9,9);B=q.bus(5,6);v7=q.bus(7,8);v5=q.bus(5,8);
    tapok=(v7>=.95-xs.vtol && v7<=1.03+xs.vtol) || ...
        (v7<.95-xs.vtol && abs(tap-.9)<1e-9) || ...
        (v7>1.03+xs.vtol && abs(tap-1.1)<1e-9);
    shuntok=(v5>=.95-ss.vtol && v5<=1.03+ss.vtol) || ...
        (v5<.95-ss.vtol && abs(B-15)<1e-9) || ...
        (v5>1.03+ss.vtol && abs(B)<1e-9);
    gridok=tap>=.9-1e-9 && tap<=1.1+1e-9 && ...
        abs((tap-.9)/(.2/9)-round((tap-.9)/(.2/9)))<1e-8 && ...
        B>=-1e-9 && B<=15+1e-9 && abs(B/5-round(B/5))<1e-8;
    bad=bad+~(tapok && shuntok && gridok);
end
audit=struct('balance_MVA',balance,'capability_violation',violation,'load_error',loaderr, ...
    'controls_accepted',bad==0,'bad_control_points',bad);
end
