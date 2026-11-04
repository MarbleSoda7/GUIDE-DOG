
import struct, sys

class FDT:
    def __init__(self, blob):
        self.d = blob
        (self.magic,self.totalsize,self.off_struct,self.off_strings,self.off_rsv,
         self.version,self.last_comp,self.boot_cpu,self.size_strings,self.size_struct) = struct.unpack('>10I', blob[:40])
        assert self.magic == 0xd00dfeed
        self.strings = blob[self.off_strings:self.off_strings+self.size_strings]
    def name_at(self,o):
        e=self.strings.index(b'\0',o); return self.strings[o:e].decode()
    def parse(self):
        i=self.off_struct; stack=[]; nodes=[]
        while True:
            tok=struct.unpack('>I',self.d[i:i+4])[0]; i+=4
            if tok==1:
                e=self.d.index(b'\0',i); nm=self.d[i:e].decode('latin-1'); i=(e+1+3)&~3
                path=(stack[-1]+'/'+nm) if stack else nm
                stack.append(path); nodes.append({'path':path,'props':[]})
            elif tok==2: stack.pop()
            elif tok==3:
                ln,no=struct.unpack('>II',self.d[i:i+8]); i+=8
                self_dummy=None
                val=self.d[i:i+ln]; i=(i+ln+3)&~3
                nodes[-1]['props'].append((self.name_at(no), val))
            elif tok==4: pass
            elif tok==9: break
            else: raise ValueError('tok %d at %d'%(tok,i))
        return nodes

def show(blob, path, maxlen=80):
    f=FDT(blob); nodes=f.parse()
    print('== %s size=%d ver=%d rsv=%d' % (path, f.totalsize, f.version, f.off_rsv))
    for n in nodes:
        print('NODE', n['path'])
        for k,v in n['props']:
            if len(v)>maxlen:
                print('   ', k, len(v), v[:32].hex())
            else:
                print('   ', k, repr(v))

for p in sys.argv[1:]:
    show(open(p,'rb').read(), p)
