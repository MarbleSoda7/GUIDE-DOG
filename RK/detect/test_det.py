#!/usr/bin/env python3
"""Offline single-frame test for the yolov5n RKNN model.

Feeds one image (PPM/PNG/JPG) through the same Detector used by rk_detect.py,
prints every box and the NPU time, and repeats it N times so you can see
whether the result is stable run to run.

    sudo python3 test_det.py frame.ppm
    python3 test_det.py frame.ppm --model /path/to/other.rknn --runs 5

No camera, no network, no FPGA -- this isolates the model from the link.
The image may be any size; it is resized to 800x480 first, because the
detector clamps boxes against those constants.
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rk_detect as R  # noqa: E402

W, H = 800, 480


def read_ppm(path):
    import numpy as np
    data = open(path, 'rb').read()
    head, rest = data.split(b'\n', 1)
    while head.startswith(b'#'):
        head, rest = rest.split(b'\n', 1)
    parts = head.split()
    assert parts[0] == b'P6', 'not a P6 PPM: %r' % parts[0]
    w, h = int(parts[1]), int(parts[2])
    return np.frombuffer(rest, dtype=np.uint8)[:w * h * 3].reshape(h, w, 3).copy()


def load(path):
    import numpy as np
    ext = os.path.splitext(path)[1].lower()
    if ext == '.ppm':
        img = read_ppm(path)
    else:
        from PIL import Image
        img = np.asarray(Image.open(path).convert('RGB'))
    if img.shape[1] != W or img.shape[0] != H:
        from PIL import Image
        # detector clamps against 800x480, so normalise here instead
        img = np.asarray(Image.fromarray(img).resize((W, H), Image.BILINEAR))
        print('resized %s -> %dx%d' % (path, W, H))
    return img[:, :, ::-1].copy()  # RGB file -> BGR, what the pipeline delivers


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image', nargs='?', help='test image; omit to just load the model')
    ap.add_argument('--model', default='/home/cat/guide_rknn_test/models/yolov5n_int8.rknn')
    ap.add_argument('--anchors', default='/home/cat/guide_rknn_test/anchors_yolov5.txt')
    ap.add_argument('--runs', type=int, default=3)
    a = ap.parse_args()

    t0 = time.time()
    det = R.Detector(a.model, a.anchors)
    print('load %.0f ms' % ((time.time() - t0) * 1e3))
    if not a.image:
        return 0

    img = load(a.image)
    print('IMG %s shape=%s mean=%.1f' % (a.image, img.shape, float(img.mean())))

    sig = None
    for i in range(a.runs):
        t = time.time()
        res, ms = det.run(img)
        total = (time.time() - t) * 1e3
        cur = tuple((c, round(s, 4), x0, y0, x1, y1) for c, s, x0, y0, x1, y1 in res)
        if sig is None:
            sig = cur
        elif cur != sig:
            print('WARN run %d differs from run 0 (non-deterministic!)' % i)
        print('run %d: %2d det  infer=%5.1f ms  total=%5.1f ms' % (i, len(res), ms, total))
        for c, s, x0, y0, x1, y1 in res[:10]:
            print('   %-12s %.2f (%d,%d)-(%d,%d)' % (R.label(c), s, x0, y0, x1, y1))
        if not res:
            print('   (no detection)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
