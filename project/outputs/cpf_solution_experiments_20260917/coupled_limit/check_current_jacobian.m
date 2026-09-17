function check_current_jacobian
out=fileparts(mfilename('fullpath'));
data=load(fullfile(out,'step_100.mat')); p=data.r; o=data.o;
p.exa_current_ilim=zeros(size(p.vsc,1),1);p.exa_current_ilim(2)=1.5;
c=idx_vsc;p.vsc(2,c.AC_MODE)=c.VSC_AC_Q;
ctx=exa_pf('__setup',p,o); x=ctx.x0;
[~,e]=exa_pf('__mismatch',ctx,x,[]); J=exa_pf('__jacobian',ctx,e,[]);
row=length(ctx.model.nonref)+find(ctx.model.qeq==ctx.model.map.internal(2));
hs=[1e-5 1e-6 1e-7]; err=zeros(size(hs)); fd=zeros(numel(hs),numel(x));
for hidx=1:numel(hs)
    for j=1:numel(x)
        h=hs(hidx)*max(1,abs(x(j))); xp=x;xm=x;xp(j)=xp(j)+h;xm(j)=xm(j)-h;
        fp=exa_pf('__mismatch',ctx,xp,[]);fm=exa_pf('__mismatch',ctx,xm,[]);
        fd(hidx,j)=(fp(row)-fm(row))/(2*h);
    end
    err(hidx)=max(abs(full(J(row,:))-fd(hidx,:)))/max(1,max(abs(full(J(row,:)))));
end
validation=struct('step_sizes',hs,'relative_inf_error',err,'max_analytic_derivative',max(abs(full(J(row,:)))), ...
    'row',row,'analytic',full(J(row,:)),'finite_difference',fd);
save(fullfile(out,'jacobian_validation.mat'),'validation');
fid=fopen(fullfile(out,'jacobian_validation.json'),'w');fprintf(fid,'%s',jsonencode(validation,PrettyPrint=true));fclose(fid);
disp(validation.relative_inf_error);
end
