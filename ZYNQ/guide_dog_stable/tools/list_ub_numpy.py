import gzip, struct, sys
P = r"D:/latest_project/sd_card_latest/image.ub"
buf = open(P, "rb").read()
def be32(b,o): return struct.unpack_from(">I",b,o)[0]
magic,total,off_struct,off_strings,off_rsv,ver,lcv,cpu,sz_str,sz_struct = struct.unpack(">10I", buf[:40])
strings = buf[off_strings:off_strings+sz_str]
def name_at(o):
    e = strings.index(b"\0",o); return strings[o:e].decode()
stack,p,props = [],off_struct,[]
while True:
    tok = be32(buf,p); p += 4
    if tok == 1:
        e = buf.index(b"\0",p); stack.append(buf[p:e].decode()); p = (e+4)&~3
    elif tok == 2: stack.pop()
    elif tok == 3:
        ln,nm = be32(buf,p),be32(buf,p+4); p += 8
        props.append(("/"+"/".join(x for x in stack if x), name_at(nm), p, ln)); p = (p+ln+3)&~3
    elif tok == 4: pass
    elif tok == 9: break
node,off,ln = [(n,o,l) for (n,pn,o,l) in props if n.startswith("/images/ramdisk-") and pn=="data"][0]
cpio = gzip.decompress(buf[off:off+ln])
def entries(blob):
    out,p = [],0
    while True:
        f=[int(blob[p+6+i*8:p+14+i*8],16) for i in range(13)]
        ns,fs=f[11],f[6]; nstart=p+110
        n=blob[nstart:nstart+ns-1].decode(); ds=(nstart+ns+3)&~3
        out.append((n,ds,ds+fs)); p=(ds+fs+3)&~3
        if n=="TRAILER!!!": return out
e = entries(cpio)
print("total entries", len(e))
nump = [x for x in e if "numpy" in x[0]]
print("numpy entries", len(nump))
for x in nump[:6]: print("   ", x[0], x[2]-x[1])
for x in e:
    if x[0].startswith("usr/bin/python") or x[0] in ("usr/bin/python3","usr/bin/python3.10"):
        print("py", x[0], x[2]-x[1])
print("--- site-packages top ---")
tops = sorted({x[0].split("/")[5] if len(x[0].split("/"))>5 else "" for x in e if x[0].startswith("usr/lib/python3.10/site-packages/")})
print([t for t in tops if t][:40])
