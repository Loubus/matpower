function mpc = case2_psse_ultc_ntp10_lowv
% case2_psse_ultc_ntp10_lowv - 2-bus PSS/E ULTC fixture, below band.
%
% Uses the same off-grid initial tap and NTP=10 grid as the in-band case,
% but the load depresses the regulated voltage enough to require tap action.

mpc = case2_psse_ultc_ntp10_fixture(100, 50);
