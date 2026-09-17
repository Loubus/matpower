function evidence = investigate_boundaries
% Instrument handoffs using unchanged solvers; repair export only in a named
% diagnostic projection. Does not change original ratings or production code.
outdir = fileparts(mfilename('fullpath'));
[~, ~, ~, ~, BUS_I, BT, ~, ~, ~, BS, ~, VM, VA] = idx_bus;
[GEN_BUS, ~, QG] = idx_gen;
opt = mpoption('out.all',0,'verbose',0);
opt.vsc_mtdc.method = 'unified';
evidence = struct();
for name = {'shunt', 'genq'}
    kind = name{1};
    f = cleanup_batch1_vsc_case(kind);
    [prepared, ~, op] = mp.psse_prepare_case(f,mp.psse_mpx_options(opt),'pf');
    op.vsc_mtdc.psse_aware = 0; % first electrical solve before control decisions
    raw = runpf_vsc_mtdc(prepared,op);
    original = mp.psse_unified_active_set('control_case_from_unified_result',raw);
    repaired = original;
    ni = size(raw.ac.order.int.gen,1); ne = size(raw.ac.gen,1);
    missing = raw.ac.order.int.gen(ne+1:ni,:);
    missing(:,GEN_BUS) = raw.ac.order.bus.i2e(missing(:,GEN_BUS));
    repaired.gen = [repaired.gen; missing];
    ai = ext2int(repaired);
    V = ai.bus(:,VM).*exp(1j*pi/180*ai.bus(:,VA));
    residual = norm(V.*conj(makeYbus(ai.baseMVA,ai.bus,ai.branch)*V)- ...
        makeSbus(ai.baseMVA,ai.bus,ai.gen),Inf);
    fprintf('%s: exported/internal gen rows=%d/%d; restored-proxy balance=%g pu\n',kind,ne,ni,residual);
    acopt = rmfield(op,'vsc_mtdc');
    aux = runpf_psse(original,acopt);
    before = int2ext(aux.task.dm.source);
    repaired_aux = runpf_psse(repaired,acopt);
    row2 = find(before.bus(:,BUS_I)==2,1);
    row5 = find(before.bus(:,BUS_I)==5,1);
    fprintf('%s: collapse active=%d; BS5 before/after expand=%g/%g; bus2 before/after=%g/%g; QG2=%g\n', ...
        kind,aux.psse.branch_collapsed.active,before.bus(row5,BS),aux.bus(5,BS), ...
        before.bus(row2,BT),aux.bus(2,BT),aux.gen(2,QG));
    if strcmp(kind,'shunt')
        fprintf('shunt original/repaired-proxy BINIT=%g/%g\n',aux.psse.swshunt.num(1,10),repaired_aux.psse.swshunt.num(1,10));
    else
        fprintf('genq original/repaired-proxy limited=%d/%d QG=%g/%g\n',aux.psse.genq.control.limited(2), ...
            repaired_aux.psse.genq.control.limited(2),aux.gen(2,QG),repaired_aux.gen(2,QG));
    end
    evidence.(kind) = struct('raw',raw,'original_projection',original, ...
        'repaired_projection',repaired,'auxiliary',aux,'before_expansion',before, ...
        'repaired_auxiliary',repaired_aux,'repaired_balance',residual);
end
save(fullfile(outdir,'boundaries.mat'),'evidence');
end
