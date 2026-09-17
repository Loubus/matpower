function compare_suite_current
out=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(out));
addpath(root); iniciar_proyecto;
s=load(fullfile(out,'matpower_suite.mat'));
rows=s.rows;
for k=1:numel(rows)
    [~,name]=fileparts(rows(k).case_name);
    ref=psse2mpc(fullfile(out,'psse_suite','solved_raw',[name '_solved.raw']),0,34);
    r=s.results{k};
    rows(k).max_dVM=NaN;
    rows(k).max_dVA=NaN;
    rows(k).buses_compared=0;
    if ~isempty(r)
        [~,ia,ib]=intersect(r.bus(:,1),ref.bus(:,1));
        rows(k).max_dVM=max(abs(r.bus(ia,8)-ref.bus(ib,8)));
        rows(k).max_dVA=max(abs(r.bus(ia,9)-ref.bus(ib,9)));
        rows(k).buses_compared=numel(ia);
    end
    rows(k).voltage_review=~rows(k).success || rows(k).max_dVM>0.005;
end
t=struct2table(rows,'AsArray',true);
writetable(t,fullfile(out,'suite_comparison_psse34.csv'));
fprintf('Compared %d cases. Successful MATPOWER: %d. Voltage review (>0.005 pu or failure): %d\n',height(t),sum(t.success),sum(t.voltage_review));
disp(t(t.voltage_review,{'case_name','success','max_dVM','max_dVA'}));
end
