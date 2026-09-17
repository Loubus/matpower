function verify_reference_and_phasors(project_root)
out=fileparts(mfilename('fullpath'));
c=idx_vsc;
s=load(fullfile(project_root,'outputs','beerten_reference_comparison_20260916','comparison.mat'));
f=s.translated_case;
ibase=100/(sqrt(3)*345);
% Follow the explicit sign branches of archived MatACDC 1.0, not its labels.
f.vsc_loss=struct('c_positive',2.885*ibase^2,'c_negative',4.371*ibase^2);
o=s.opt;
r=runpf_vsc_mtdc(f,o);
assert(r.success);
err=max(abs(r.vsc(:,[c.PAC c.QAC c.PCONV c.QCONV c.PDC c.PLOSS])- ...
    s.translated_result.vsc(:,[c.PAC c.QAC c.PCONV c.QCONV c.PDC c.PLOSS])),[],'all');
assert(err<1e-8,'Dynamic selection must match the previously fixed base coefficients.');
savecase(fullfile(out,'case5_matacdc_directional.m'),f);

% Probe default sequential budget and report it separately from a longer run.
os=o; os.vsc_mtdc.method='sequential';
rs_default=runpf_vsc_mtdc(f,os);
rs=rs_default;
if ~rs_default.success
    os.vsc_mtdc.max_it=100; % documented test budget, no tolerance change
    rs=runpf_vsc_mtdc(f,os);
end
assert(rs.success,'Translated author sequential PF failed at documented budget.');
seqerr=max(abs(r.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS])-rs.vsc(:,[c.PAC c.QAC c.PDC c.PLOSS])),[],'all');
assert(seqerr<2e-5);

% Rotate PCC phasor to 1+j0. P/Q fixed: -60 MW/-40 MVAr on 100 MVA.
us=1; is=conj(complex(-60,-40)/100/us);
rows=[s.local_case.vsc(1,:); f.vsc(1,:)];
no_filter=f.vsc(1,:); no_filter(c.FILTER_B)=0;
rows=[rows; no_filter];
phasors=struct('name',{},'Us',{},'Is_real',{},'Is_imag',{},'Uf_real',{}, ...
    'Uf_imag',{},'Uf_abs',{},'Ic_real',{},'Ic_imag',{},'Uc_real',{},'Uc_imag',{},'Uc_abs',{});
names={'Local reconstruction','Author station','Author impedances without filter'};
for k=1:size(rows,1)
    row=rows(k,:);
    zt=complex(row(c.TR_R),row(c.TR_X)); zr=complex(row(c.REACTOR_R),row(c.REACTOR_X));
    yf=complex(row(c.FILTER_G),row(c.FILTER_B));
    uf=us+zt*is; ic=is+yf*uf; uc=uf+zr*ic;
    phasors(k)=struct('name',names{k},'Us',us,'Is_real',real(is),'Is_imag',imag(is), ...
        'Uf_real',real(uf),'Uf_imag',imag(uf),'Uf_abs',abs(uf),'Ic_real',real(ic), ...
        'Ic_imag',imag(ic),'Uc_real',real(uc),'Uc_imag',imag(uc),'Uc_abs',abs(uc));
end
assert(abs(phasors(1).Uc_abs-s.local_result.vsc(1,c.VAC_INTERNAL))<1e-10);
assert(abs(phasors(2).Uc_abs-r.vsc(1,c.VAC_INTERNAL))<1e-10);
details=struct('unified_success',r.success,'unified_iterations',r.iterations, ...
    'fixed_vs_dynamic_max_MW_MVAr',err,'sequential_default_success',rs_default.success, ...
    'sequential_default_iterations',rs_default.iterations,'sequential_success',rs.success, ...
    'sequential_iterations',rs.iterations,'sequential_max_MW_MVAr_difference',seqerr, ...
    'phasors',phasors,'loss_model',f.vsc_loss);
fid=fopen(fullfile(out,'reference_and_phasors.json'),'w');
fprintf(fid,'%s',jsonencode(details,PrettyPrint=true)); fclose(fid);
save(fullfile(out,'reference_and_phasors.mat'),'details','f','r','rs','rs_default');
disp(jsonencode(details,PrettyPrint=true));
end
