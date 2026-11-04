#!/usr/bin/env python3
"""Minimal newc cpio reader/writer used to refresh the camremap app inside
the PetaLinux initramfs (image.ub ramdisk-1).

Usage:
  cpio_tool.py list  <cpio> [prefix]
  cpio_tool.py stat  <cpio> <name>
  cpio_tool.py patch <cpio> <out> <srcdir> [<destprefix>]

patch replaces every regular file found under <srcdir> at
<destprefix>/<relpath>; missing destinations are appended as new entries.
"""
import os, sys, stat, struct

HDR = 110
MAGIC = b"070701"

class Entry:
    __slots__ = ("name", "mode", "uid", "gid", "nlink", "mtime", "devmajor",
                 "devminor", "rdevmajor", "rdevminor", "data")
    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))

def read_entries(blob):
    out = []
    i = 0
    n = len(blob)
    while i + HDR <= n:
        if blob[i:i+6] != MAGIC:
            raise ValueError("bad magic at %d: %r" % (i, blob[i:i+6]))
        f = [int(blob[i+6+8*k:i+14+8*k], 16) for k in range(13)]
        (ino, mode, uid, gid, nlink, mtime, filesize, devmajor, devminor,
         rdevmajor, rdevminor, namesize, check) = f
        name_end = i + HDR + namesize
        name = blob[i+HDR:name_end-1].decode("utf-8", "surrogateescape")
        data_start = (name_end + 3) & ~3
        data_end = data_start + filesize
        data = blob[data_start:data_end]
        nxt = (data_end + 3) & ~3
        if name == "TRAILER!!!":
            out.append(Entry(name=name, mode=mode, uid=uid, gid=gid, nlink=nlink,
                             mtime=mtime, devmajor=devmajor, devminor=devminor,
                             rdevmajor=rdevmajor, rdevminor=rdevminor, data=data))
            return out, nxt
        out.append(Entry(name=name, mode=mode, uid=uid, gid=gid, nlink=nlink,
                         mtime=mtime, devmajor=devmajor, devminor=devminor,
                         rdevmajor=rdevmajor, rdevminor=rdevminor, data=data))
        i = nxt
    raise ValueError("no TRAILER!!!")

def write_entry(e, ino):
    data = e.data or b""
    name = e.name.encode("utf-8", "surrogateescape") + b"\0"
    fields = [ino & 0xffffffff, e.mode, e.uid, e.gid, e.nlink, e.mtime,
              len(data), e.devmajor, e.devminor, e.rdevmajor, e.rdevminor,
              len(name), 0]
    hdr = MAGIC + b"".join(b"%08X" % (x & 0xffffffff) for x in fields)
    assert len(hdr) == HDR, len(hdr)
    buf = bytearray(hdr)
    buf += name
    while len(buf) % 4:
        buf += b"\0"
    buf += data
    while len(buf) % 4:
        buf += b"\0"
    return bytes(buf)

def build(entries):
    out = bytearray()
    ino = 1
    for e in entries:
        out += write_entry(e, ino)
        ino += 1
    return bytes(out)

def norm(name):
    return name.lstrip("./")

def patch(blob, srcdir, destprefix):
    entries, used = read_entries(blob)
    tail = blob[used:]
    destprefix = destprefix.strip("/")
    byname = {norm(e.name): e for e in entries if e.name != "TRAILER!!!"}
    replaced, added = [], []
    for root, _dirs, files in os.walk(srcdir):
        for fn in sorted(files):
            if fn.endswith(".pyc") or "__pycache__" in root:
                continue
            src = os.path.join(root, fn)
            rel = os.path.relpath(src, srcdir).replace(os.sep, "/")
            dest = (destprefix + "/" + rel).strip("/")
            data = open(src, "rb").read()
            if dest in byname:
                e = byname[dest]
                e.data = data
                e.mode = (e.mode & 0o777000) | (stat.S_IMODE(os.stat(src).st_mode))
                replaced.append(dest)
            else:
                now = int(os.stat(src).st_mtime)
                parent = os.path.dirname(dest)
                if parent and parent not in byname:
                    pd = parent
                    stack = []
                    while pd and pd not in byname:
                        stack.append(pd)
                        pd = os.path.dirname(pd)
                    for p in reversed(stack):
                        ne = Entry(name="./" + p, mode=0o40755, uid=0, gid=0,
                                   nlink=2, mtime=now, devmajor=0, devminor=0,
                                   rdevmajor=0, rdevminor=0, data=b"")
                        entries.insert(len(entries) - 1, ne)
                        byname[p] = ne
                ne = Entry(name="./" + dest,
                           mode=0o100000 | stat.S_IMODE(os.stat(src).st_mode),
                           uid=0, gid=0, nlink=1, mtime=now, devmajor=0,
                           devminor=0, rdevmajor=0, rdevminor=0, data=data)
                entries.insert(len(entries) - 1, ne)
                byname[dest] = ne
                added.append(dest)
    return build(entries) + tail, replaced, added

def main():
    cmd = sys.argv[1]
    if cmd == "list":
        blob = open(sys.argv[2], "rb").read()
        prefix = sys.argv[3] if len(sys.argv) > 3 else ""
        entries, _ = read_entries(blob)
        for e in entries:
            n = norm(e.name)
            if n.startswith(prefix):
                print("%9d %o %s" % (len(e.data), e.mode, n))
    elif cmd == "stat":
        blob = open(sys.argv[2], "rb").read()
        target = norm(sys.argv[3])
        entries, _ = read_entries(blob)
        for e in entries:
            if norm(e.name) == target:
                print("%s mode=%o size=%d mtime=%d" % (target, e.mode, len(e.data), e.mtime))
                return
        print("not found:", target)
        raise SystemExit(1)
    elif cmd == "patch":
        blob = open(sys.argv[2], "rb").read()
        new, rep, add = patch(blob, sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "")
        open(sys.argv[3], "wb").write(new)
        print("entry_bytes=%d replaced=%d added=%d" % (len(new), len(rep), len(add)))
        for r in rep:
            print("  R", r)
        for a in add:
            print("  A", a)
    else:
        raise SystemExit(__doc__)

if __name__ == "__main__":
    main()
