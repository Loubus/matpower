function out=b17_journal(action,value)
persistent rows
if nargin<2, value=[]; end
switch action
    case 'reset', rows={}; out=[];
    case 'append', rows{end+1}=value; out=[];
    case 'get', out=rows;
    otherwise, error('Unknown journal action');
end
end
