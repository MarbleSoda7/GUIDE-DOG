#!/usr/bin/env python3
"""Repack the PetaLinux FIT image (image.ub) with a refreshed initramfs.

The board boots image.ub from the SD card; its ramdisk-1 carries the camremap
application.  Patching it in place keeps kernel/DTB untouched and avoids a
PetaLinux rebuild.

Usage:
  pack_sd_image.py --ub image.ub --out image.ub.new
                   [--app <site-packages/camremap dir>] [--prefix usr/lib/python3.10/site-packages/camremap]
                   [--data <share/camremap dir>]   [--data-prefix usr/share/camremap]
                   [--dtb <system.dtb>] [--keep-size]
"""
import argparse
import gzip
import hashlib
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fdtlib
import cpio_tool


def hash_of(node):
    h = node.child("hash-1")
    return None if h is None else h.get("value")


def set_hash(node, data):
    h = node.child("hash-1")
    if h is None:
        raise SystemExit("image node %s has no hash-1" % node.name)
    h.set("value", hashlib.sha256(data).digest())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ub", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--app")
    ap.add_argument("--prefix", default="usr/lib/python3.10/site-packages/camremap")
    ap.add_argument("--data")
    ap.add_argument("--data-prefix", default="usr/share/camremap")
    ap.add_argument("--dtb")
    ap.add_argument("--keep-size", action="store_true")
    args = ap.parse_args()

    blob = pathlib.Path(args.ub).read_bytes()
    fit = fdtlib.parse(blob)
    images = fit.root.child("images")
    if images is None:
        raise SystemExit("no /images node")
    ram = images.child("ramdisk-1")
    if ram is None:
        raise SystemExit("no ramdisk-1")

    if args.app or args.data:
        raw = ram.get("data")
        if raw[:2] != b"\x1f\x8b":
            raise SystemExit("ramdisk-1 is not gzip; unexpected")
        cpio = gzip.decompress(raw)
        print("cpio in=%d" % len(cpio))
        for srcdir, prefix in ((args.app, args.prefix), (args.data, args.data_prefix)):
            if not srcdir:
                continue
            cpio, rep, add = cpio_tool.patch(cpio, srcdir, prefix)
            print("%s -> replaced=%d added=%d" % (prefix, len(rep), len(add)))
            for r in rep:
                print("   R", r)
            for a in add:
                print("   A", a)
        packed = gzip.compress(cpio, 6, mtime=0)
        print("cpio out=%d gz=%d (was %d)" % (len(cpio), len(packed), len(raw)))
        ram.set("data", packed)
        set_hash(ram, packed)

    if args.dtb:
        dtb = pathlib.Path(args.dtb).read_bytes()
        node = images.child("fdt-system-top.dtb")
        if node is None:
            raise SystemExit("no fdt-system-top.dtb")
        if node.get("data") != dtb:
            node.set("data", dtb)
            set_hash(node, dtb)
            print("dtb replaced: %d bytes" % len(dtb))
        else:
            print("dtb unchanged: %d bytes" % len(dtb))

    out = fit.serialize()
    if args.keep_size:
        if len(out) > len(blob):
            raise SystemExit("repacked FIT larger than original (%d > %d)" % (len(out), len(blob)))
        out = out + b"\0" * (len(blob) - len(out))
    pathlib.Path(args.out).write_bytes(out)
    print("wrote %s: %d bytes (was %d)" % (args.out, len(out), len(blob)))

    # verify: re-parse and re-check every hash-1
    check = fdtlib.parse(pathlib.Path(args.out).read_bytes())
    bad = 0
    for node in check.root.path("images").children:
        h = hash_of(node)
        if h is None:
            continue
        if h != hashlib.sha256(node.get("data")).digest():
            print("HASH MISMATCH", node.name)
            bad += 1
    print("hash check: %d image node(s) verified, %d bad" % (len(check.root.path("images").children), bad))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
