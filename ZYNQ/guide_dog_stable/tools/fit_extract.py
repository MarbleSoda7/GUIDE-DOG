
import struct, hashlib, os, gzip
PATH = r'D:/latest_project_pl_rectify/sd_card_latest/image.ub'
d = open(PATH,'rb').read()
magic,tot,off_struct,off_str,off_rsv,ver,lastcomp,bootcpu,size_str,size_struct = struct.unpack('>10I', d[:40])
strs = d[off_str:off_str+size_str]
def name_at(o):
    e = strs.index(b'\0', o); return strs[o:e].decode()
def align4(x): return (x+3)&~3
i = off_struct; stack=[]; nodes=[]
while True:
    tok = struct.unpack('>I', d[i:i+4])[0]; i += 4
    if tok == 1:
        e=d.index(b'\0',i); nm=d[i:e].decode('latin-1'); i=align4(e+1)
        path=(stack[-1].rstrip('/')+'/'+nm).lstrip('/') if stack else nm
        stack.append(path); nodes.append({'path':path,'props':{}})
    elif tok == 2: stack.pop()
    elif tok == 3:
        ln,no=struct.unpack('>II',d[i:i+8]); i+=8
        nodes[-1]['props'][name_at(no)] = d[i:i+ln]; i=align4(i+ln)
    elif tok == 4: pass
    elif tok == 9: break
byp={n['path']:n for n in nodes}
print([k for k in byp if 'ramdisk' in k or k.count('/')<2][:12])
ram = byp['images/ramdisk-1']['props']['data']
raw = gzip.decompress(ram)
print('ramdisk gz', len(ram), 'raw', len(raw), raw[:6])
os.makedirs(r'D:/latest_project_pl_rectify/.tmp_fit', exist_ok=True)
open(r'D:/latest_project_pl_rectify/.tmp_fit/ramdisk.cpio','wb').write(raw)
entries=[]; i=0
while True:
    if raw[i:i+6] != b'070701': print('magic', raw[i:i+6]); break
    hdr=raw[i:i+110]
    f=[int(hdr[6+8*k:14+8*k],16) for k in range(13)]
    filesize=f[6]; namesize=f[11]; mtime=f[5]
    name=raw[i+110:i+110+namesize-1].decode('latin-1')
    off=(i+110+namesize+3)&~3
    data=raw[off:off+filesize]
    entries.append((name,f[1],filesize,mtime,data))
    if name=='TRAILER!!!': break
    i=(off+filesize+3)&~3
print('entries',len(entries))
hits=[e for e in entries if 'camremap' in e[0]]
for h in hits: print('  %-70s %6d %d' % (h[0],h[2],h[3]))
