function result=g150_log(action,item)
% Storage for isolated diagnostic solver copies only.
persistent rows failures
result=[];
switch action
    case 'reset', rows={}; failures={};
    case 'append', rows{end+1}=item;
    case 'failure', failures{end+1}=item;
    case 'get', result=struct('rows',{rows},'failures',{failures});
end
end
