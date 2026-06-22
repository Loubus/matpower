function Smax = gen_capability_default_smax(mpc, g)
%GEN_CAPABILITY_DEFAULT_SMAX Default conventional generator capability Smax.

[~, ~, ~, ~, ~, ~, MBASE] = idx_gen;
Smax = mpc.gen(g, MBASE);
if ~isfinite(Smax) || Smax <= 0
    Smax = mpc.baseMVA;
end
