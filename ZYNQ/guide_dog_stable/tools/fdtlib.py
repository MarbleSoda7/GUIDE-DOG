"""Minimal flattened-device-tree (DTB/FDT) reader + writer.

Enough for editing a U-Boot FIT image and writing it back byte-exactly:
reserve map, struct block and strings block are rebuilt from the tree.
"""
import struct


class Node:
    __slots__ = ("name", "props", "children")

    def __init__(self, name):
        self.name = name
        self.props = []      # list of [name, bytes]
        self.children = []

    def get(self, name, default=None):
        for k, v in self.props:
            if k == name:
                return v
        return default

    def set(self, name, value):
        for p in self.props:
            if p[0] == name:
                p[1] = value
                return
        self.props.append([name, value])

    def child(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None

    def path(self, *names):
        n = self
        for nm in names:
            n = n.child(nm)
            if n is None:
                return None
        return n

    def u32(self, name, default=None):
        v = self.get(name)
        if v is None or len(v) != 4:
            return default
        return struct.unpack(">I", v)[0]

    def set_u32(self, name, value):
        self.set(name, struct.pack(">I", value & 0xFFFFFFFF))


def _pad4(b):
    return b + b"\0" * ((4 - len(b) % 4) % 4)


def parse(blob):
    magic, totalsize, off_struct, off_strings, off_rsv, version, last_comp, \
        boot_cpu, size_strings, size_struct = struct.unpack(">10I", blob[:40])
    if magic != 0xD00DFEED:
        raise ValueError("not a DTB: magic=%08x" % magic)
    strings = blob[off_strings:off_strings + size_strings]
    rsv = []
    i = off_rsv
    while i + 16 <= len(blob):
        addr, size = struct.unpack(">QQ", blob[i:i + 16])
        if addr == 0 and size == 0:
            break
        rsv.append((addr, size))
        i += 16
    i = off_struct
    stack = []
    root = None
    while True:
        tok = struct.unpack(">I", blob[i:i + 4])[0]
        i += 4
        if tok == 1:
            e = blob.index(b"\0", i)
            name = blob[i:e].decode("utf-8", "surrogateescape")
            i = _align(i, e + 1)
            n = Node(name)
            if stack:
                stack[-1].children.append(n)
            else:
                root = n
            stack.append(n)
        elif tok == 2:
            stack.pop()
        elif tok == 3:
            ln, nameoff = struct.unpack(">II", blob[i:i + 8])
            i += 8
            val = blob[i:i + ln]
            i = _align(i, i + ln)
            e = strings.index(b"\0", nameoff)
            stack[-1].props.append([strings[nameoff:e].decode("ascii"), val])
        elif tok == 4:
            pass
        elif tok == 9:
            break
        else:
            raise ValueError("bad token %d at %d" % (tok, i))
    return Fdt(root, rsv, version, last_comp, boot_cpu)


def _align(base, pos):
    return base + ((pos - base + 3) & ~3)


class Fdt:
    def __init__(self, root, rsv, version=17, last_comp=16, boot_cpu=0):
        self.root = root
        self.rsv = rsv
        self.version = version
        self.last_comp = last_comp
        self.boot_cpu = boot_cpu

    def serialize(self):
        strings = bytearray()
        stroff = {}

        def intern(s):
            if s not in stroff:
                stroff[s] = len(strings)
                strings.extend(s.encode("ascii") + b"\0")
            return stroff[s]

        struct_blk = bytearray()

        def emit(node):
            struct_blk.extend(struct.pack(">I", 1))
            struct_blk.extend(node.name.encode("utf-8", "surrogateescape") + b"\0")
            while len(struct_blk) % 4:
                struct_blk.extend(b"\0")
            for k, v in node.props:
                no = intern(k)
                struct_blk.extend(struct.pack(">III", 3, len(v), no))
                struct_blk.extend(v)
                while len(struct_blk) % 4:
                    struct_blk.extend(b"\0")
            for c in node.children:
                emit(c)
            struct_blk.extend(struct.pack(">I", 2))

        emit(self.root)
        struct_blk.extend(struct.pack(">I", 9))

        rsv_blk = bytearray()
        for a, s in self.rsv:
            rsv_blk.extend(struct.pack(">QQ", a, s))
        rsv_blk.extend(b"\0" * 16)

        off_rsv = 40
        off_struct = off_rsv + len(rsv_blk)
        off_strings = off_struct + len(struct_blk)
        total = off_strings + len(strings)
        hdr = struct.pack(">10I", 0xD00DFEED, total, off_struct, off_strings,
                          off_rsv, self.version, self.last_comp, self.boot_cpu,
                          len(strings), len(struct_blk))
        return bytes(hdr) + bytes(rsv_blk) + bytes(struct_blk) + bytes(strings)
