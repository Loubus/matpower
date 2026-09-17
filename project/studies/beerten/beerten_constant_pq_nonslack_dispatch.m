function [base,target,options,study] = beerten_constant_pq_nonslack_dispatch
%BEERTEN_CONSTANT_PQ_NONSLACK_DISPATCH User-declared study, 2026-09-14.
% Retains the batch-6 demand direction and supported capability settings.
% The non-slack generator follows the schedule until its capability clamps it;
% the current active-set implementation then leaves the AC slack balancing.
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
% User-requested 150 MW maximum (2026-09-16). The generic thermal curve has
% Pmax=0.8*Snom, so its capability base is 187.5 MVA, not 150 MVA.
% This scales the entire thermal P/Q curve (Q=112.5 MVAr at Pmax).
% Explicit capability metadata leaves the electrical MBASE/box data intact.
base.gen_capability.Snom = base.gen(:,MBASE);
base.gen_capability.Snom(participant) = 150/0.8;
target.gen_capability = base.gen_capability;
delta_demand = sum(target.bus(:,PD)) - sum(base.bus(:,PD));
target.gen(participant,PG) = base.gen(participant,PG) + delta_demand;
target.gen(slack,PG) = base.gen(slack,PG);

study.name = 'beerten_constant_pq_nonslack_dispatch';
study.parent_scenario = 'beerten_constant_pq_supported_capabilities';
study.slack_mbase_MVA = 1000;
study.slack_bus = base.gen(slack,GEN_BUS);
study.dispatch_bus = base.gen(participant,GEN_BUS);
study.dispatch_pmax_MW = 150;
study.dispatch_capability_base_MVA = 150/0.8;
study.dispatch_q_at_pmax_MVAr = 0.6*study.dispatch_capability_base_MVA;
study.gen_dispatch = ['Requested P2=40+240*lambda MW until capability saturation. ' ...
    'The implemented active set clamps P2 at 150 MW and the AC slack ' ...
    'then supplies the remaining demand and losses.'];
study.limit_scope = ['Generic thermal capability explicitly scaled to 187.5 MVA ' ...
    '(150 MW maximum, 112.5 MVAr upper corner). Original matrix PMAX/Q boxes ' ...
    'and electrical MBASE retained; capability metadata takes precedence. ' ...
    'Generic slack capability exemption is unchanged.'];
study.stability_margin_validated = false;
end
