function evidence=t_cpf_local_release(outdir)
% Positive and negative local-release fixtures, independent of FULL completion.
if ~isfolder(outdir),mkdir(outdir);end
c=idx_vsc;q=case5_vsc_mtdc_beerten;
% Isolated fixture: realistic station impedances, a known Q injection, and
% enough generator capability that the test contains only a VSC transition.
q.gen(2,7)=187.5;
q.vsc(:,[c.TR_R c.TR_X c.FILTER_G c.FILTER_B c.REACTOR_R c.REACTOR_X])= ...
    repmat([.0015 .1121 .002 .0887 .0001 .16428],3,1);
q.vsc(3,c.QAC_SET)=40;
pfopt=mpoption('verbose',0,'out.all',0,'vsc_mtdc.method','unified', ...
    'vsc_mtdc.psse_aware',0,'vsc_mtdc.capability_enforce',1);
[r0,ok]=runpf_vsc_mtdc_unified(q,pfopt);assert(ok,'Fixture PF failed');
contact=q;contact.bus=r0.ac.bus(1:size(q.bus,1),:);
contact.gen=r0.ac.gen(1:size(q.gen,1),:);contact.vsc=r0.vsc;contact.busdc=r0.busdc;
contact.vsc(3,c.VAC_SET)=r0.vsc(3,c.VAC_PCC);
contact.vsc_current_limit=[0;0;hypot(r0.vsc(3,c.PCONV),r0.vsc(3,c.QCONV))/r0.vsc(3,c.VAC_INTERNAL)/q.baseMVA];
contact.vsc_current_restore_mode=[0;0;c.VSC_AC_PV];
contact.vsc_capability.Snom=[150;150;contact.vsc_current_limit(3)*q.baseMVA];
contact.vsc_capability.Vmax=1.15;
% A nonzero initial reactor voltage drop avoids a singular zero-current seed.
contact.bus(contact.bus(:,1)==contact.vsc(3,c.VSC_BUS),8)=contact.vsc(3,c.VAC_SET)-.01;
checks=struct('name',{},'passed',{},'error',{});runs=cell(3,1);
for trial=1:3
    direction=-1;if trial==3,direction=1;end
    b=contact;if trial==2,b.vsc(3,c.VAC_SET)=b.vsc(3,c.VAC_SET)+1e-4;end
    t=b;t.bus(:,3:4)=b.bus(:,3:4)*(1+direction*.2);
    opt=mpoption(pfopt,'cpf.stop_at',.05,'cpf.step',.02,'vsc_mtdc.current_limit_release',1);
    lastwarn('');[r,success]=runcpf_psse(b,t,opt);[warning,warning_id]=lastwarn;
    tags={'inward_at_base','inward_bracketed','outward'};tag=tags{trial};
    save(fullfile(outdir,[tag '.mat']),'b','t','opt','r','success','warning','warning_id');
    ev=r.cpf.events(strcmp({r.cpf.events.name},'VSC_CURRENT_RELEASE'));
    ck([tag '_endpoint'],success && r.cpf.termination.requested_endpoint_reached,0);
    if direction<0
        ck('inward_releases_once',isscalar(ev),numel(ev));
        if isscalar(ev)
            ck('same_boundary_equilibrium',ev.state_gap<=ev.state_tolerance,ev.state_gap);
            ck('voltage_continuity',abs(ev.voltage_before-ev.voltage_after)<1e-7,ev.voltage_before-ev.voltage_after);
            ck('current_contact',abs(ev.current_ratio_final-1)<1e-6,ev.current_ratio_final);
            ck('both_forward_probes_inward',max(ev.probe_current_ratio,ev.half_probe_current_ratio)<1,ev.probe_current_ratio);
            ck('tangent_orientation_preserved',ev.orientation_dot>0,ev.orientation_dot);
            ck('localized_event',strcmp(ev.kind,'localized_branch_intersection'),0);
            if trial==2
                ck('release_localized_inside_step',ev.lambda_event>0 && ev.lambda_event<.05,ev.lambda_event);
                ck('voltage_target_contact',abs(ev.contact_voltage_error)<1e-8,ev.contact_voltage_error);
            end
        end
        ck('ends_in_voltage_control',r.vsc(3,c.AC_MODE)==c.VSC_AC_PV,0);
    else
        ck('outward_does_not_release',isempty(ev),numel(ev));
        ck('outward_remains_current_limited',r.vsc_current_limit(3)>0,0);
    end
    runs{trial}=struct('direction',tag,'termination',r.cpf.termination,'events',ev, ...
        'warning',warning,'warning_id',warning_id);
    fprintf('%s success %d endpoint %d releases %d\n',tag,success,r.cpf.termination.requested_endpoint_reached,numel(ev));
end
evidence=struct('checks',checks,'passed',sum([checks.passed]),'total',numel(checks),'runs',{runs}, ...
    'fixture_voltage_target',contact.vsc(3,c.VAC_SET),'fixture_note','Synthetic reversal of demand at a solved contact, with physical controls fixed. No change to production study.');
fid=fopen(fullfile(outdir,'evidence.json'),'w');fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true));fclose(fid);
assert(all([checks.passed]),'Local release regression failed; inspect evidence.json');
    function ck(name,pass,err)
        checks(end+1)=struct('name',name,'passed',logical(pass),'error',err);
        if ~pass,fprintf('FAIL %s %.12g\n',name,err);end
    end
end
