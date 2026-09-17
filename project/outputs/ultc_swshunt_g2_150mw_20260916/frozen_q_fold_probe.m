function evidence=frozen_q_fold_probe(failure,seed,Qorders)
% Local electrical branch diagnostic with frozen discrete controls and Q.
% Parameterize by V5 and solve lambda as an unknown to cross a PF fold.
out=fileparts(mfilename('fullpath')); samples=cell(1,numel(Qorders));
for z=1:numel(Qorders)
    p=failure.base; t=failure.target; p.vsc(2,7)=Qorders(z); t.vsc(2,7)=Qorders(z);
    opt=failure.options; opt.vsc_mtdc.psse_aware=0;
    ctx=runpf_vsc_mtdc_unified('__setup',p,opt); ct=runpf_vsc_mtdc_unified('__setup',t,opt);
    Sd=ct.Sbase-ctx.Sbase; ix=numel(ctx.model.nonref)+find(ctx.model.vm_vars==5);
    x=seed; lam=failure.lambda; trace=zeros(351,5);
    targets=linspace(.71,.64,351);
    for k=1:numel(targets)
        for it=1:25
            [F,e]=runpf_vsc_mtdc_unified('__mismatch',ctx,x,ctx.Sbase+lam*Sd);
            H=[F; x(ix)-targets(k)]; if norm(H,inf)<1e-9, break; end
            J=runpf_vsc_mtdc_unified('__jacobian',ctx,e,[]);
            f1=runpf_vsc_mtdc_unified('__mismatch',ctx,x,ctx.Sbase+(lam+1)*Sd); dl=f1-F;
            vrow=zeros(1,numel(x)); vrow(ix)=1; step=-[J dl; vrow 0]\H;
            x=x+step(1:end-1); lam=lam+step(end);
        end
        [F,e]=runpf_vsc_mtdc_unified('__mismatch',ctx,x,ctx.Sbase+lam*Sd);
        trace(k,:)=[targets(k) lam norm(F,inf) e.iac(2)/1.5 e.Vm(ctx.model.map.pcc(2))];
    end
    [peak,ii]=max(trace(:,2));
    samples{z}=struct('Qorder',Qorders(z),'trace',trace,'max_lambda',peak,'V5_at_max',trace(ii,1),'max_residual',max(trace(:,3)));
end
evidence=[samples{:}];
save(fullfile(out,'frozen_Q_folds.mat'),'evidence');
fid=fopen(fullfile(out,'frozen_Q_folds.json'),'w'); fprintf(fid,'%s',jsonencode(evidence,PrettyPrint=true)); fclose(fid);
f=figure('Visible','off','Color','w','Theme','light','Position',[30 30 1150 700]); hold on;
for z=1:numel(evidence)
    ee=evidence(z); plot(ee.trace(:,2),ee.trace(:,1),'LineWidth',2,'DisplayName',sprintf('Fixed Q = %.6f MVAr',ee.Qorder));
    scatter(ee.max_lambda,ee.V5_at_max,65,'k','filled','HandleVisibility','off');
end
xline(failure.lambda,'--','Failed trial loading','LabelOrientation','horizontal','LineWidth',1.5,'DisplayName','Failed CPF trial');
xlabel('Loading parameter \lambda'); ylabel('Bus 5 voltage (p.u.)'); grid on;
title({'Local fixed-Q curves with identical generator/tap/shunt states','The inward Q adjustment shifts the fold below the requested loading'});
legend('Location','southwest'); exportgraphics(f,fullfile(out,'fixed_Q_fold_shift.png'),'Resolution',155); close(f);
for z=1:numel(evidence), fprintf('Q %.9f: sampled local fold lambda %.12f V5 %.6f maxF %.3g\n',evidence(z).Qorder,evidence(z).max_lambda,evidence(z).V5_at_max,evidence(z).max_residual); end
end
