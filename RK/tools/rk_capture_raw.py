#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Raw stereo frame capturer for the Zynq->RK UDP stream (v1 header).

Passively sniffs eth0 (AF_PACKET, needs root), reassembles the 827-packet
frames of cam1/cam2 and writes HUD-free 800x480 PNGs.  It never binds UDP
port 1234, so the running frame_recv_stereo is unaffected.

Key tuning: the FPGA sends one whole frame (827 packets ~ 1.2 MB) as a tight
burst.  The kernel default socket buffer (~208 KB) cannot hold a burst, so
packets get dropped and no frame is ever complete.  SO_RCVBUFFORCE is used to
ask for 64 MB; --stats prints what the kernel actually granted.

Header (12 bytes): D2 C2 ver cam_id pair_be16 total_be16 idx_be16 plen_be16
Frame: 800*480*3 = 1,152,000 bytes, 1394 bytes/packet, 827 packets.
"""
import argparse
import os
import socket
import struct
import sys
import time
import zlib

W, H = 800, 480
FRAME_BYTES = W * H * 3
DATA_PER_PKT = 1394
TOTAL_PKTS = 827
MAGIC0, MAGIC1, VER = 0xD2, 0xC2, 1
SO_RCVBUFFORCE = 33


def write_png(path, rgb):
    """Minimal RGB8 PNG writer (filter 0, one IDAT)."""
    stride = W * 3
    raw = bytearray(H * (1 + stride))
    view = memoryview(raw)
    for y in range(H):
        o = y * (1 + stride)
        view[o] = 0
        view[o + 1:o + 1 + stride] = rgb[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", ihdr))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw), 3)))
        fh.write(chunk(b"IEND", b""))


def open_socket(iface, want_mb):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    got = None
    for opt in (SO_RCVBUFFORCE, socket.SO_RCVBUF):
        try:
            s.setsockopt(socket.SOL_SOCKET, opt, want_mb * 1024 * 1024)
            got = s.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)
            if got >= want_mb * 512 * 1024:
                break
        except OSError as exc:
            print("setsockopt opt=%d failed: %s" % (opt, exc), file=sys.stderr)
    s.bind((iface, 0))
    s.settimeout(2.0)
    return s, got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default="eth0")
    ap.add_argument("--port", type=int, default=1234)
    ap.add_argument("--out", default="/home/cat/calib_raw")
    ap.add_argument("--count", type=int, default=5, help="pairs to save (0 = until timeout)")
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--every", type=float, default=0.35, help="min seconds between saved pairs")
    ap.add_argument("--rcvbuf-mb", type=int, default=64)
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    s, got = open_socket(a.iface, a.rcvbuf_mb)
    print("socket up iface=%s rcvbuf=%s bytes" % (a.iface, got))

    st = {1: {}, 2: {}}
    last_save = 0.0
    saved = 0
    t0 = time.time()
    pkt = 0
    seen = 0
    while True:
        if a.count and saved >= a.count:
            break
        if time.time() - t0 > a.timeout:
            break
        try:
            data = s.recv(65535)
        except socket.timeout:
            print("no packets for 2 s", file=sys.stderr)
            continue
        seen += 1
        if len(data) < 42 or data[12:14] != b"\x08\x00":
            continue
        ihl = (data[14] & 0x0F) * 4
        if data[23] != 17:
            continue
        u = 14 + ihl
        if u + 8 + 12 > len(data):
            continue
        if struct.unpack(">H", data[u + 2:u + 4])[0] != a.port:
            continue
        p = data[u + 8:]
        if p[0] != MAGIC0 or p[1] != MAGIC1 or p[2] != VER:
            continue
        cam = p[3]
        pair = (p[4] << 8) | p[5]
        tot = (p[6] << 8) | p[7]
        idx = (p[8] << 8) | p[9]
        plen = (p[10] << 8) | p[11]
        if cam not in (1, 2) or tot != TOTAL_PKTS or idx >= TOTAL_PKTS:
            continue
        expected = min(DATA_PER_PKT, FRAME_BYTES - idx * DATA_PER_PKT)
        if plen != expected or len(p) - 12 != plen:
            continue
        pkt += 1
        slot = st[cam].get(pair)
        if slot is None:
            slot = st[cam][pair] = [bytearray(FRAME_BYTES), bytearray(TOTAL_PKTS), 0]
        if slot[1][idx]:
            continue
        slot[0][idx * DATA_PER_PKT:idx * DATA_PER_PKT + plen] = p[12:12 + plen]
        slot[1][idx] = 1
        slot[2] += 1
        if slot[2] != TOTAL_PKTS:
            continue
        now = time.time()
        pair_ok = (pair in st[1] and pair in st[2]
                   and st[1][pair][2] == TOTAL_PKTS and st[2][pair][2] == TOTAL_PKTS)
        if not pair_ok or now - last_save < a.every:
            continue
        last_save = now
        saved += 1
        base = os.path.join(a.out, "pair_%05d" % pair)
        write_png(base + "_L.png", bytes(st[1][pair][0]))
        write_png(base + "_R.png", bytes(st[2][pair][0]))
        partial = {c: len([k for k in st[c] if st[c][k][2] < TOTAL_PKTS]) for c in (1, 2)}
        print("saved %s pair=%d t=%.1f pkt=%d partial=%s"
              % (base, pair, now - t0, pkt, partial), flush=True)
        for c in (1, 2):
            for k in [k for k in st[c] if k <= pair]:
                st[c].pop(k, None)
    s.close()
    print("done saved=%d packets=%d seen=%d elapsed=%.1fs"
          % (saved, pkt, seen, time.time() - t0))
    return 0 if saved else 1


if __name__ == "__main__":
    raise SystemExit(main())
