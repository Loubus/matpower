"""Read-only MAT-v5 scalar option inspection while the MCP solver is busy.
No numerical solver or scenario changes are performed by this script.
"""
from pathlib import Path
import struct,zlib,json
def element(buf,pos):
    tag=struct.unpack_from('<I',buf,pos)[0];small=tag>>16
    if small:
        return tag&65535,buf[pos+4:pos+4+small],pos+8
    size=struct.unpack_from('<I',buf,pos+4)[0]
    return tag,buf[pos+8:pos+8+size],pos+8+size+(0 if tag==15 else (-size)%8)
def matrix(buf):
    _,flags,pos=element(buf,0);cls=flags[0]
    _,dims,pos=element(buf,pos)
    _,name,pos=element(buf,pos);name=name.decode('utf-8')
    if cls==2:
        _,length,pos=element(buf,pos);length=struct.unpack('<I',length)[0]
        _,fields,pos=element(buf,pos)
        fields=[fields[i:i+length].split(b'\0')[0].decode() for i in range(0,len(fields),length)]
        result={}
        for field in fields:
            _,data,pos=element(buf,pos);result[field]=matrix(data)[1]
        return name,result
    if cls==4:
        typ,data,pos=element(buf,pos)
        return name,data.decode('utf-16-le' if typ in (4,17) else 'utf-8')
    if cls==1:return name,'<cell>'
    if pos>=len(buf):return name,[]
    typ,data,pos=element(buf,pos)
    formats={1:'b',2:'B',3:'h',4:'H',5:'i',6:'I',7:'f',9:'d',12:'q',13:'Q'}
    fmt=formats.get(typ)
    if not fmt:return name,'<non-scalar>'
    vals=list(struct.unpack('<'+fmt*(len(data)//struct.calcsize(fmt)),data))
    return name,vals[0] if len(vals)==1 else vals
p=Path('outputs/algorithm_cleanup_batch4_20260911/beerten_probe.mat')
buf=p.read_bytes();pos=128
while pos<len(buf):
    typ,data,pos=element(buf,pos)
    if typ==15:_,data,_=element(zlib.decompress(data),0)
    _,_,at=element(data,0);_,_,at=element(data,at);_,rawname,_=element(data,at)
    if rawname==b'b4o':
        _,opt=matrix(data)
        out=Path(__file__).resolve().parent
        (out/'fixture_options_readonly.json').write_text(json.dumps(opt,indent=2))
        print(json.dumps({k:opt[k] for k in ['cpf','vsc_mtdc']},indent=2))
        break
