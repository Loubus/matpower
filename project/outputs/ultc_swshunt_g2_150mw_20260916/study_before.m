function [base,target,options,study] = beerten_constant_pq_nonslack_dispatch
%BEERTEN_CONSTANT_PQ_NONSLACK_DISPATCH User-declared study, 2026-09-14.
% Retains the batch-6 demand direction and supported capability settings.
% The non-slack generator supplies scheduled incremental demand; the AC slack
% retains its base balancing duty and supplies changes in total system losses.
% Historical batch-6 inputs/results are a different scenario and stay intact.
[base,target,options,study] = beerten_constant_pq_capability_batch6;
[~,~,REF,~,BUS_I,BUS_TYPE,PD] = idx_bus;
[GEN_BUS,PG,~,~,~,~,MBASE,GEN_STATUS] = idx_gen;
assert(isequal(base.gen(:,GEN_BUS),target.gen(:,GEN_BUS)), ...
    'Base and target generator identities must agree.');
online = base.gen(:,GEN_STATUS) > 0;
ref_buses = base.bus(base.bus(:,BUS_TYPE) == REF,BUS_I);
slack = find(online & ismember(base.gen(:,GEN_BUS),ref_buses));
participant = find(online & ~ismember(base.gen(:,GEN_BUS),ref_buses));
assert(isscalar(slack) && isscalar(participant), ...
    'This Beerten scenario requires one AC slack and one non-slack generator.');

% MBASE is in MVA, not MW. This does not change PMAX or slack exemptions.
base.gen(slack,MBASE) = 1000;
target.gen(slack,MBASE) = 1000;
delta_demand = sum(target.bus(:,PD)) - sum(base.bus(:,PD));
target.gen(participant,PG) = base.gen(participant,PG) + delta_demand;
target.gen(slack,PG) = base.gen(slack,PG);

study.name = 'beerten_constant_pq_nonslack_dispatch';
study.parent_scenario = 'beerten_constant_pq_supported_capabilities';
study.slack_mbase_MVA = 1000;
study.slack_bus = base.gen(slack,GEN_BUS);
study.dispatch_bus = base.gen(participant,GEN_BUS);
study.gen_dispatch = ['P2=40+240*lambda MW; AC slack supplies the base ' ...
    'balance and incremental losses. No automatic reassignment at a limit.'];
study.limit_scope = ['Original PMAX/Q boxes and non-slack MBASE/curve retained. ' ...
    'Generic slack capability exemption is unchanged. A scheduled point beyond ' ...
    'a participant limit is not automatically feasible or reassigned.'];
study.stability_margin_validated = false;
end
