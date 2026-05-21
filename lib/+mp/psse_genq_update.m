function mpc = psse_genq_update(mpc, state)
% psse_genq_update - Applies PSS/E generator Q-control state to an MPC.
% ::
%
%   MPC = MP.PSSE_GENQ_UPDATE(MPC, STATE)
%
% Updates ``mpc.gen(:, QG)``, generator Q limits, bus types, and
% ``mpc.psse.genq.control`` from the current PSS/E generator Q-control
% state.
%
% See also mp.psse_genq_control, mp.psse_genq_report.

%   MATPOWER
%   Copyright (c) 2026, Power Systems Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

[PQ, PV, REF, ~, ~, BUS_TYPE] = idx_bus;
[~, ~, QG, QMAX, QMIN, VG] = idx_gen;

mapped = find(state.gen_idx > 0);
for kk = mapped(:)'
    gi = state.gen_idx(kk);
    mpc.gen(gi, QG) = state.current_q(kk);
    mpc.gen(gi, VG) = state.vs(kk);
    if state.remote(kk) || state.limited(kk)
        mpc.gen(gi, QMAX) = state.current_q(kk);
        mpc.gen(gi, QMIN) = state.current_q(kk);
    else
        mpc.gen(gi, QMAX) = state.qmax(kk);
        mpc.gen(gi, QMIN) = state.qmin(kk);
    end
end

bus_list = unique(state.bus_idx(state.active & state.bus_idx > 0));
for jj = 1:length(bus_list)
    b = bus_list(jj);
    if b <= 0 || b > size(mpc.bus, 1)
        continue;
    end
    at_bus = state.active & state.bus_idx == b;
    if any(state.swing(at_bus)) || any(state.base_bus_type(at_bus) == REF)
        mpc.bus(b, BUS_TYPE) = REF;
    elseif any(state.local(at_bus) & ~state.limited(at_bus))
        if any(state.base_bus_type(at_bus) == PV)
            mpc.bus(b, BUS_TYPE) = PV;
        else
            mpc.bus(b, BUS_TYPE) = state.base_bus_type(find(at_bus, 1));
        end
    else
        mpc.bus(b, BUS_TYPE) = PQ;
    end
end

mpc.psse.genq.current_q = state.current_q;
mpc.psse.genq.limited = state.limited;
mpc.psse.genq.at_min = state.at_min;
mpc.psse.genq.at_max = state.at_max;
mpc.psse.genq.code_final = state.code_final;
mpc.psse.genq.control = mp.psse_genq_report(state);
