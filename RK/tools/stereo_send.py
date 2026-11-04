#!/usr/bin/env python3
"""Synthetic stereo sender: exercises the RK receiver without the FPGA.

Reads a JPEG, scales it to 800x480 RGB888, and emits packet-v1 UDP datagrams
([D2][C2][01][camera_id][pair_id BE16][total BE16][idx BE16][plen BE16] + data)
for both eyes on a shared pair_id, exactly like the new camremap pipeline.
"""
import socket, struct, sys, time
from PIL import Image

W, H = 800, 480
FRAME_BYTES = W * H * 3
DATA = 1394
TOTAL = 827

def load(path, flip):
    im = Image.open(path).convert("RGB").resize((W, H), Image.BILINEAR)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im.tobytes()

def packets(buf, cam, pair):
    for idx in range(TOTAL):
        off = idx * DATA
        chunk = buf[off:off + DATA]
        hdr = struct.pack(">BBBBHHHH", 0xD2, 0xC2, 1, cam, pair, TOTAL, idx, len(chunk))
        yield hdr + chunk

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/home/cat/guide-dog/test/bus.jpg"
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
    secs = float(sys.argv[4]) if len(sys.argv) > 4 else 20.0
    left = load(path, False)
    right = load(path, True)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 << 20)
    dst = (host, 1234)
    t0 = time.time()
    pair = 1
    sent = 0
    while time.time() - t0 < secs:
        start = time.time()
        for cam, buf in ((1, left), (2, right)):
            for p in packets(buf, cam, pair):
                s.sendto(p, dst)
                sent += 1
        print("pair %d sent %d datagrams (%.1f fps)" % (pair, sent, pair / (time.time() - t0)))
        sys.stdout.flush()
        pair = (pair + 1) & 0xFFFF
        dt = 1.0 / fps - (time.time() - start)
        if dt > 0:
            time.sleep(dt)
    print("DONE %d pairs" % (pair - 1))

main()
