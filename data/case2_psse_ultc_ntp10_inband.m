function mpc = case2_psse_ultc_ntp10_inband
% case2_psse_ultc_ntp10_inband - 2-bus PSS/E ULTC fixture, in band.
%
% The transformer has RMI=0.9, RMA=1.1, NTP=10, so tap 1.0 is not one
% of the equal-spaced tap states. Since the controlled bus voltage starts
% inside [0.95, 1.03], ACTAPS should not snap the tap to the grid.

mpc = case2_psse_ultc_ntp10_fixture(0, 0);
