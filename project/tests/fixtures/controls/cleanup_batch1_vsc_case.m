function mpc = cleanup_batch1_vsc_case(kind)
%CLEANUP_BATCH1_VSC_CASE Exact small VSC regression fixtures, no rating changes.
% Mirrors t_vsc_mtdc local fixtures as audited on 2026-09-10.
mpc = loadcase('case5_vsc_mtdc_beerten');
switch kind
    case 'shunt'
        cols = {'I', 'MODSW', 'ADJM', 'STAT', 'VSWHI', 'VSWLO', ...
            'SWREG', 'RMPCT', 'RMIDNT', 'BINIT', ...
            'N1', 'B1', 'N2', 'B2', 'N3', 'B3', 'N4', 'B4', ...
            'N5', 'B5', 'N6', 'B6', 'N7', 'B7', 'N8', 'B8', 'NREG'};
        row = nan(1, 27);
        row([1:8 10:12 27]) = [5 1 0 1 1.005 0.995 5 100 0 10 1 0];
        mpc.psse.rev = 34;
        mpc.psse.system.solver.SWSHNT = 1;
        mpc.psse.system.adjust.MXTPSS = 10;
        mpc.psse.swshunt = struct('colnames', {cols}, 'num', row, ...
            'txt', {cell(1, 27)}, 'binit_col', 10, 'status_col', 4);
    case 'genq'
        [~, ~, QG, QMAX, QMIN] = idx_gen;
        mpc.gen(2, QG) = 0;
        mpc.gen(2, QMAX) = -20;
        mpc.gen(2, QMIN) = -100;
        mpc.psse.rev = 34;
        mpc.psse.system.solver.VARLIM = 1;
        mpc.psse.system.adjust.MXTPSS = 10;
        mpc.psse.system.newton.VCTOLQ = 0.01;
        mpc.psse.genq = struct('colnames', {{'I'}}, 'num', zeros(2, 1), ...
            'txt', {cell(2, 1)}, 'bus_ext', [1; 2], 'reg_bus_ext', [1; 2], ...
            'status', [1; 1], 'qg', [0; 0], 'qmax', [500; -20], ...
            'qmin', [-500; -100], 'vs', [1.06; 1.00], 'rmpct', [100; 100]);
    otherwise
        error('cleanup_batch1:fixture', 'Unknown fixture: %s', kind);
end
end
