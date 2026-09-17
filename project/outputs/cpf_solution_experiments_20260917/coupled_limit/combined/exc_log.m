function out=exc_log(op,value)
persistent entries
if isempty(entries), entries={}; end
switch op
    case 'reset', entries={};
    case 'append', entries{end+1}=value;
end
out=entries;
end
