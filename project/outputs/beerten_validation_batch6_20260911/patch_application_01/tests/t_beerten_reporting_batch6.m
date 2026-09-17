function t_beerten_reporting_batch6(quiet)
% Public unified PF equipment tables must contain the solved external state.
if nargin<1,quiet=0;end
t_begin(15,quiet);
o=mpoption('verbose',0,'out.all',0);
for mode=1:3
 p=case5_vsc_mtdc_beerten;
 if mode==2
   p.bus=flipud(p.bus); p.gen=flipud(p.gen);
 elseif mode==3
   off=p.gen(2,:);off(8)=0;p.gen=[off;p.gen];
   o.vsc_mtdc.capability_enforce=1;
 end
 r=runpf_psse(p,o); [ok,rows]=ismember(p.bus(:,1),r.ac.bus(:,1));
 t_ok(r.success && all(ok),'full PF converges');
 t_ok(isequal(r.bus,r.ac.bus(rows,:)),'public voltages and bus modes are solved');
 t_ok(isequal(r.gen,r.ac.gen(1:size(p.gen,1),:)),'original generator powers and row order');
 t_ok(isequal(r.branch,r.ac.branch(1:size(p.branch,1),:)),'original branch flows are solved');
 t_ok(r.gen(r.gen(:,1)==1,2)>100,'slack demand is visible in public audit input');
end
t_end;
end
