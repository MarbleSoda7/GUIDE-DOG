
import gzip, hashlib, sys, pathlib
sys.path.insert(0,'D:/latest_project_pl_rectify/tools')
import fdtlib
# NOTE: the stock image.ub also stores compression="none" while the payload is
# gzip (U-Boot sniffs the 1f 8b magic), so sniff the magic, not the property.
ub = pathlib.Path("F:/image.ub").read_bytes()
fit = fdtlib.parse(ub)
images = fit.root.child("images")
ram = images.child("ramdisk-1")
raw = ram.get("data")
cpio = gzip.decompress(raw) if raw[:2]==b"\x1f\x8b" else raw
print("ramdisk payload %d -> cpio %d" % (len(raw), len(cpio)))

o=0; entries=[]
while True:
    if cpio[o:o+6]!=b"070701": break
    f=cpio[o:o+110]
    def h(i): return int(f[6+i*8:6+(i+1)*8],16)
    filesize=h(6); namesize=h(11)
    name=cpio[o+110:o+110+namesize-1].decode()
    dataoff=o+(110+namesize+3)//4*4
    entries.append((name,filesize,dataoff))
    o=dataoff+((filesize+3)//4*4)
    if name=="TRAILER!!!": break
print("entries: %d  duplicate names: %d" % (len(entries), len(entries)-len(set(n for n,_,_ in entries))))

d={}
for n,s,do in entries:
    d[n.lstrip("./")] = (s,do)
want = ["usr/lib/python3.10/site-packages/camremap/remap.py",
        "usr/lib/python3.10/site-packages/camremap/main.py",
        "usr/share/camremap/left_remap.rmp",
        "usr/share/camremap/right_remap.rmp",
        "usr/share/camremap/remap_manifest.json",
        "usr/share/camremap/led_test_wrapper.bit",
        "usr/share/camremap/led_test_wrapper.hwh",
        "usr/share/camremap/ov5640_800x480_rgb565.json"]
for w in want:
    if w not in d:
        print("MISSING  ", w); continue
    s,do=d[w]
    print("%-54s %9d sha=%s" % (w, s, hashlib.sha256(cpio[do:do+s]).hexdigest()[:16]))

art = pathlib.Path("D:/latest_project_pl_rectify/artifacts/pl_rectify")
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
for name, key in (("led_test_wrapper.bit","usr/share/camremap/led_test_wrapper.bit"),
                  ("led_test_wrapper.hwh","usr/share/camremap/led_test_wrapper.hwh")):
    s,do=d[key]
    print("%-24s card==artifact: %s" % (name, sha(art/name)==hashlib.sha256(cpio[do:do+s]).hexdigest()))
