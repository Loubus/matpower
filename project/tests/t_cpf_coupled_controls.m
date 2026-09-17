function evidence=t_cpf_coupled_controls(outdir,study_dir,legacy_file)
% Current-row derivatives, persisted active-set state, event semantics and
% independent network/capability checks on the actual returned CPF traces.
if ~isfolder(outdir),mkdir(outdir);end
c=idx_vsc;o=mpoption('verbose',0,'out.all',0);o.vsc_mtdc.method='unified';
checks=struct('name',{},'passed',{},'error',{});
for station=1:3
    b=case5_vsc_mtdc_beerten;
    if station>1
        b.vsc(:,[c.TR_R c.TR_X c.FILTER_G c.FILTER_B c.REACTOR_R c.REACTOR_X])= ...
            repmat([.0015 .1121 .002 .0887 .0001 .16428],3,1);
    end
    if station==3
        b.vsc(:,[c.TR_B c.REACTOR_B c.TR_SHIFT])=repmat([.013 .017 8],3,1);
    end
    b.vsc(2,c.AC_MODE)=c.VSC_AC_Q;b.vsc_current_limit=[0;1.5;0];
    ctx=runpf_vsc_mtdc_unified('__setup',b,o);x=ctx.x0;
    [F,e]=runpf_vsc_mtdc_unified('__mismatch',ctx,x,ctx.Sbase);
    J=runpf_vsc_mtdc_unified('__jacobian',ctx,e,[]);D=zeros(size(J));
    for j=1:numel(x)
        h=1e-6*max(1,abs(x(j)));xp=x;xm=x;xp(j)=xp(j)+h;xm(j)=xm(j)-h;
        fp=runpf_vsc_mtdc_unified('__mismatch',ctx,xp,ctx.Sbase);
        fm=runpf_vsc_mtdc_unified('__mismatch',ctx,xm,ctx.Sbase);D(:,j)=(fp-fm)/(2*h);
    end
    row=numel(ctx.model.nonref)+find(ctx.model.qeq==ctx.model.map.internal(2));
    err=norm(J(row,:)-D(row,:),Inf)/max(1,norm(D(row,:),Inf));
    ck(sprintf('station_%d_current_row_derivative',station),err<2e-6,err);
    err=abs(F(row)-(e.iac(2)/1.5)^2+1);
    ck(sprintf('station_%d_actual_internal_current',station),err<1e-12,err);
end
bad=b;bad.vsc_current_limit=[0 NaN 0];expect_error(bad,'runpf_vsc_mtdc_unified:current_limit');
bad=b;bad.vsc_current_limit=[0 -1 0];expect_error(bad,'runpf_vsc_mtdc_unified:current_limit');
bad=b;bad.vsc_current_limit=[0 1];expect_error(bad,'runpf_vsc_mtdc_unified:current_limit');
bad=b;bad.vsc(2,c.AC_MODE)=c.VSC_AC_V;expect_error(bad,'runpf_vsc_mtdc_unified:current_limit_mode');
f=fullfile(outdir,'current_state_roundtrip.m');savecase(f,b);bb=loadcase(f);
ck('current_active_set_survives_save_load',isequal(b.vsc_current_limit,bb.vsc_current_limit),0);
rejected=false;os=o;os.vsc_mtdc.method='sequential';
try,runpf_vsc_mtdc(bb,os);catch me,rejected=strcmp(me.identifier,'runpf_vsc_mtdc:current_limit_method');end
ck('sequential_rejects_unsupported_active_current',rejected,0);
events=zeros(2,2);
for mode={'nose','full'}
 for step=[100 50]
    d=load(fullfile(study_dir,sprintf('%s_%03d.mat',mode{1},step)));r=d.result;
    tag=sprintf('%s_%03d',mode{1},step);ev=r.cpf.events(strcmp({r.cpf.events.name},'LIMIT_INDUCED_TURN'));
    ck([tag '_one_limit_turn'],numel(ev)==1,numel(ev));
    if isempty(ev),continue;end
    ix=1+(step==50);iy=1+strcmp(mode{1},'full');events(ix,iy)=ev.lambda_event;
    ck([tag '_correct_oriented_turn'],ev.tangent_before>0 && ev.tangent_after<0,ev.tangent_after);
    ck([tag '_localized_state_interval'],max(ev.state_interval,ev.incoming_interval)<=ev.event_tolerance,ev.state_interval);
    ck([tag '_independent_event_benchmark'],abs(ev.lambda_event-1.245668943509885)<1e-7,abs(ev.lambda_event-1.245668943509885));
    hist=r.cpf.turn_detection.history;rejected_trials=hist(~cellfun(@(h)h.localized,hist));
    ck([tag '_rollback_exercised'],~isempty(rejected_trials) && all(cellfun(@(h)h.rollback_verified,rejected_trials)),numel(rejected_trials));
    if strcmp(mode{1},'nose')
        ck([tag '_requested_endpoint'],r.success && r.cpf.termination.requested_endpoint_reached,0);
        ck([tag '_stops_at_first_turn'],abs(r.cpf.lam(end)-ev.lambda_event)<1e-10,0);
    else
        ck([tag '_continues_after_turn'],r.cpf.lam(end)<ev.lambda_event-.1,0);
        ck([tag '_does_not_claim_full_completion'],~r.cpf.termination.requested_endpoint_reached,0);
    end
    audit=physical_trace(r,d.base,d.options);
    ck([tag '_AC_DC_bridge_balance'],audit.balance_MVA<1e-5,audit.balance_MVA);
    ck([tag '_converter_capability'],audit.cap_violation_MVA<1e-5,audit.cap_violation_MVA);
 end
end
ck('NOSE_FULL_same_first_event',max(abs(events(:,1)-events(:,2)))<1e-10,max(abs(events(:,1)-events(:,2))));
ck('two_step_event_agreement',abs(events(1,1)-events(2,1))<1e-7,abs(events(1,1)-events(2,1)));
d=load(legacy_file);a=physical_trace(d.rpap_full,d.mpcpap_full,d.mpopt_pap_full);
ck('legacy_FULL_balance',a.balance_MVA<1e-5,a.balance_MVA);
ck('legacy_FULL_converter_capability',a.cap_violation_MVA<1e-5,a.cap_violation_MVA);
ck('legacy_FULL_requested_endpoint',d.rpap_full.cpf.termination.requested_endpoint_reached,0);
evidence=struct('checks',checks,'passed',sum([checks.passed]),'failed',sum(~[checks.passed]));
fid=fopen(fullfile(outdir,'coupled_controls.json'),'w');fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));fclose(fid);
fprintf('COUPLED_CONTROLS: %d passed, %d failed\n',evidence.passed,evidence.failed);
assert(evidence.failed==0,'Coupled-control regression failed; inspect evidence.');
 function ck(name,passed,err)
    checks(end+1)=struct('name',name,'passed',logical(passed),'error',err);
 end
 function expect_error(data,id)
    rejected=false;try,runpf_vsc_mtdc_unified('__setup',data,o);catch me,rejected=strcmp(me.identifier,id);end
    ck(['reject_' id],rejected,0);
 end
end
function a=physical_trace(r,b,o)
c=idx_vsc;balance=0;violation=0;
for k=1:numel(r.cpf.lam)
    q=b;q.bus=r.cpf.bus(:,:,k);q.gen=r.cpf.gen(:,:,k);q.branch=r.cpf.branch(:,:,k);
    q.vsc=r.cpf.vsc(:,:,k);q.busdc=r.cpf.busdc(:,:,k);
    ac=ext2int(struct('version','2','baseMVA',q.baseMVA,'bus',q.bus,'gen',q.gen,'branch',q.branch));
    U=ac.bus(:,8).*exp(1j*pi/180*ac.bus(:,9));Y=makeYbus(ac.baseMVA,ac.bus,ac.branch);
    S=makeSbus(ac.baseMVA,ac.bus,ac.gen);Pdc=zeros(size(q.busdc,1),1);
    for j=find(q.vsc(:,c.VSC_STATUS)>0)'
        bus=find(ac.order.bus.i2e==q.vsc(j,c.VSC_BUS));
        S(bus)=S(bus)+complex(q.vsc(j,c.PAC),q.vsc(j,c.QAC))/q.baseMVA;
        dc=find(q.busdc(:,1)==q.vsc(j,c.BUSDC));Pdc(dc)=Pdc(dc)+q.vsc(j,c.PDC);
        p=vsc_capability_params(q,o.vsc_mtdc,j,j);
        [~,~,~,~,info]=vsc_capability_curve(q.vsc(j,c.PAC),q.vsc(j,c.QAC),p.Smax, ...
            q.vsc(j,c.VAC_PCC),q.vsc(j,:),p.mode,p.Vmax,q.baseMVA);
        violation=max(violation,-info.margin);
    end
    G=makeGdc(q.busdc,r.cpf.branchdc(:,:,k));
    balance=max([balance;abs(U.*conj(Y*U)-S)*q.baseMVA; ...
        abs(q.busdc(:,3).*(G*q.busdc(:,3))*q.baseMVA-Pdc); ...
        abs(q.vsc(:,c.PCONV)+q.vsc(:,c.PDC)+q.vsc(:,c.PLOSS))]);
end
a=struct('balance_MVA',balance,'cap_violation_MVA',violation);
end
