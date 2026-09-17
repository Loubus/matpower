function calculate_evidence
% Read-only model evaluation. All new evidence stays beside this script.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
out=fileparts(mfilename('fullpath')); cd(root); iniciar_proyecto;
diary(fullfile(out,'verification','matlab.log')); cleanup=onCleanup(@()diary('off'));
[base,target,options,study]=beerten_constant_pq_nonslack_dispatch;
lastwarn(''); pf=runpf_psse(base,options); [warning_message,warning_id]=lastwarn;
fresh=struct('name','New dispatch base, lambda=0','lambda',0,'bus',pf.ac.bus, ...
 'branch',pf.ac.branch,'gen',pf.ac.gen,'vsc',pf.vsc,'busdc',pf.busdc, ...
 'branchdc',pf.branchdc,'success',pf.success,'convergence',pf.convergence);
five=runpf_psse('case5_vsc_mtdc_beerten',mpoption('verbose',0,'out.all',0));
fivepack=struct('name','Local five-bus case','lambda',0,'bus',five.ac.bus, ...
 'branch',five.ac.branch,'gen',five.ac.gen,'vsc',five.vsc,'busdc',five.busdc,'branchdc',five.branchdc,'success',five.success,'convergence',five.convergence);
hist=jsondecode(fileread(fullfile(root,'outputs','beerten_validation_batch6_20260911','final_04','capability_step_100.json')));
author=jsondecode(fileread(fullfile(root,'outputs','beerten_validation_batch6_20260911','author_reference.json')));
cv=author.dc.convdc;zt=complex(cv(:,7),cv(:,8));zr=complex(cv(:,10),cv(:,11));
ss=complex(cv(:,4),cv(:,5))/100;us=author.ac.bus([2 3 5],8);
is=conj(ss)./us;uf=us+zt.*is;ic=is+1j*cv(:,9).*uf;uc=uf+zr.*ic;
ar=struct('Ps',real(ss)*100,'Qs',imag(ss)*100,'Pc',cv(:,27),'Qc',cv(:,28), ...
 'Us',us,'Uf',abs(uf),'Uc',abs(uc),'Is',abs(is),'Ic',abs(ic),'Ploss',cv(:,29), ...
 'Qfilter_consumed',-100*cv(:,9).*abs(uf).^2,'Ptr',100*real(zt).*abs(is).^2, ...
 'Pr',100*real(zr).*abs(ic).^2,'Qtr',100*imag(zt).*abs(is).^2,'Qr',100*imag(zr).*abs(ic).^2);
writejson(fullfile(out,'reference_station.json'),ar);
rows=struct([]); trace=struct([]);
for n=1:numel(hist.points)
 p=hist.points(n); rr=station_rows(p.vsc,p.ac_bus,p.ac_branch,100);
 trace(n).lambda=p.lambda;trace(n).station=rr;
end
rows(1).name=fresh.name;rows(1).station=station_rows(fresh.vsc,fresh.bus,fresh.branch,100);
rows(2).name=fivepack.name;rows(2).station=station_rows(fivepack.vsc,fivepack.bus,fivepack.branch,100);
rows(3).name='Historical batch 6 endpoint';rows(3).station=trace(end).station;
% Full filter-aware boundaries, fixed PCC voltage: parameterize physical
% current and internal-voltage circles and map both power measurement ports.
theta=linspace(-pi,pi,1441); boundaries=struct([]);
for n=1:3
 if n==1, v=fresh.vsc; u=v(:,34); tag='project_base';
 elseif n==2, v=hist.points(end).vsc; u=v(:,34); tag='project_endpoint';
 else, v=[];u=author.ac.bus([2 3 5],8);tag='archive_reference';end
 for k=1:3
  if n<3
   zt=complex(v(k,15),v(k,16));zr=complex(v(k,24),v(k,25));yf=complex(v(k,22),v(k,23));imax=1.5;umax=1.15;umin=0;
  else
   cv=author.dc.convdc(k,:);zt=complex(cv(7),cv(8));zr=complex(cv(10),cv(11));yf=1j*cv(9);imax=cv(15);umax=cv(13);umin=cv(14);
  end
  a=1+yf*zt;d=1+zr*yf;e=zt+zr*a;
  ic=imax*exp(1j*theta);is=(ic-yf*u(k))/a;uf=u(k)+zt*is;uc=uf+zr*ic;
  b=struct('name',tag,'converter',k,'u',u(k),'imax',imax,'umax',umax,'umin',umin, ...
    'zt',[real(zt),imag(zt)],'zr',[real(zr),imag(zr)],'yf',[real(yf),imag(yf)]);
  b.current_pcc=[real(u(k)*conj(is(:))),imag(u(k)*conj(is(:)))]*100;
  b.current_internal=[real(uc(:).*conj(ic(:))),imag(uc(:).*conj(ic(:)))]*100;
  uc=umax*exp(1j*theta);is=(uc-d*u(k))/e;uf=u(k)+zt*is;ic=a*is+yf*u(k);
  b.voltage_pcc=[real(u(k)*conj(is(:))),imag(u(k)*conj(is(:)))]*100;
  b.voltage_internal=[real(uc(:).*conj(ic(:))),imag(uc(:).*conj(ic(:)))]*100;
  if umin>0
   uc=umin*exp(1j*theta);is=(uc-d*u(k))/e;ic=a*is+yf*u(k);
   b.min_voltage_pcc=[real(u(k)*conj(is(:))),imag(u(k)*conj(is(:)))]*100;
  else,b.min_voltage_pcc=[];end
  if isempty(boundaries),boundaries=b;else,boundaries(end+1)=b;end %#ok<AGROW>
 end
end
evidence=struct('study',study,'fresh',fresh,'five',fivepack,'rows',rows,'trace',trace, ...
 'boundaries',boundaries,'historical_termination',hist.summary.termination, ...
 'warning_message',warning_message,'warning_id',warning_id,'base',base,'target',target,'options',options);
writejson(fullfile(out,'evidence.json'),evidence);
save(fullfile(out,'evidence.mat'),'evidence','pf','five','base','target','options','study');
fprintf('FRESH_BASE_SUCCESS=%d MAX_MISMATCH=%.12g\n',pf.success,pf.convergence.max_mismatch);
fprintf('FIVE_BUS_SUCCESS=%d MAX_MISMATCH=%.12g\n',five.success,five.convergence.max_mismatch);
fprintf('STATION_BALANCE_MAX_MVA=%.12g\n',max(arrayfun(@(x)max([x.station.balance_error_MVA]),rows)));
assert(pf.success && five.success,'Fresh PF failed');
assert(max(arrayfun(@(x)max([x.station.balance_error_MVA]),rows))<1e-6,'Station balance check failed');
max_trace_balance=max(arrayfun(@(t)max([t.station.balance_error_MVA]),trace));
assert(max_trace_balance<1e-6,'Historical terminal reconstruction failed');
boundary_current_error=0;boundary_voltage_error=0;
for k=1:numel(boundaries)
 b=boundaries(k);zt=complex(b.zt(1),b.zt(2));zr=complex(b.zr(1),b.zr(2));yf=complex(b.yf(1),b.yf(2));
 ss=complex(b.current_pcc(:,1),b.current_pcc(:,2))/100;is=conj(ss)/b.u;uf=b.u+zt*is;ic=is+yf*uf;
 boundary_current_error=max(boundary_current_error,max(abs(abs(ic)-b.imax)));
 ss=complex(b.voltage_pcc(:,1),b.voltage_pcc(:,2))/100;is=conj(ss)/b.u;uf=b.u+zt*is;ic=is+yf*uf;uc=uf+zr*ic;
 boundary_voltage_error=max(boundary_voltage_error,max(abs(abs(uc)-b.umax)));
end
assert(boundary_current_error<1e-10 && boundary_voltage_error<1e-10,'Boundary reconstruction failed');
checks=struct('fresh_base_success',pf.success,'fresh_base_residual_pu',pf.convergence.max_mismatch, ...
 'fresh_five_success',five.success,'fresh_five_residual_pu',five.convergence.max_mismatch, ...
 'quoted_station_balance_error_MVA',max(arrayfun(@(x)max([x.station.balance_error_MVA]),rows)), ...
 'all_26_historical_station_balance_error_MVA',max_trace_balance, ...
 'boundary_current_error_pu',boundary_current_error,'boundary_voltage_error_pu',boundary_voltage_error, ...
 'warning_message',warning_message,'warning_id',warning_id,'assertions_passed',true);
writejson(fullfile(out,'verification','calculation_checks.json'),checks);
end

function rr=station_rows(v,bus,branch,base)
c=idx_vsc;rr=struct([]);
for k=1:size(v,1)
 [~,ix]=ismember(v(k,[c.VSC_BUS c.FILTER_BUS c.INTERNAL_BUS]),bus(:,1));
 vv=bus(ix,8).*exp(1j*pi/180*bus(ix,9));us=vv(1);uf=vv(2);uc=vv(3);
 zt=complex(v(k,15),v(k,16));zr=complex(v(k,24),v(k,25));yf=complex(v(k,22),v(k,23));
 is=(uf-us)/zt;ic=(uc-uf)/zr;sf=yf'*abs(uf)^2*base;
 ss=us*conj(is)*base;sc=uc*conj(ic)*base;
 [~,~,~,~,ci]=vsc_capability_curve(v(k,30),v(k,31),[],abs(us),v(k,:),[],1.15,base);
 r=struct('converter',k,'pcc',v(k,1),'filter_bus',v(k,41),'internal_bus',v(k,42), ...
 'Ps',real(ss),'Qs',imag(ss),'Pc',v(k,30),'Qc',v(k,31),'Pdc',v(k,32),'Ploss',v(k,37), ...
 'Us',abs(us),'Uf',abs(uf),'Uc',abs(uc),'delta_s',angle(us)*180/pi,'delta_f',angle(uf)*180/pi,'delta_c',angle(uc)*180/pi, ...
 'Is',abs(is),'Ic',abs(ic),'I_surrogate',hypot(v(k,30),v(k,31))/(base*abs(us)), ...
 'U_surrogate',hypot(abs(us)^2+abs(zt+zr)*v(k,31)/base,abs(zt+zr)*v(k,30)/base)/abs(us), ...
 'Ptr',real(zt)*abs(is)^2*base,'Qtr',imag(zt)*abs(is)^2*base, ...
 'Pr',real(zr)*abs(ic)^2*base,'Qr',imag(zr)*abs(ic)^2*base,'Pf',real(sf),'Qf',imag(sf), ...
 'I_ratio',abs(ic)/1.5,'I_surrogate_ratio',hypot(v(k,30),v(k,31))/(150*abs(us)), ...
 'capability_margin_MVA',ci.margin,'mode',v(k,4),'reported_Ptr',v(k,38),'reported_Pr',v(k,39), ...
 'balance_error_MVA',max([abs(sc-(ss+zt*abs(is)^2*base+zr*abs(ic)^2*base+sf)),abs(sc-complex(v(k,30),v(k,31)))]), ...
 'Pcc_branch_error',abs(real(ss)+branch(v(k,43),14)),'Qcc_branch_error',abs(imag(ss)+branch(v(k,43),15)));
 if k==1,rr=r;else
  try,rr(k)=r;catch me,disp(k);disp(fieldnames(rr));disp(fieldnames(r));rethrow(me);end
 end
end
end
function writejson(path,v)
fid=fopen(path,'w');cl=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(v));
end
