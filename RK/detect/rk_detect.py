#!/usr/bin/env python3
"""RK3568 side of the guide-dog loop.

Receives the camera1 frame that the Zynq PL streams over UDP, runs the YOLOv5
RKNN detector on it, and sends the detection boxes back to the FPGA.  Every
packet the FPGA sends carries {ack_fid, want_fid} in its first four bytes:

    ack_fid   the frame id whose result the FPGA has already accepted (0xFFFF
              when nothing has been accepted yet)
    want_fid  the frame id the FPGA is still missing and would like re-sent
              (0xFFFF when it is not waiting for anything)

So a lost reply is repaired by the FPGA asking again, and we never have to
fire the same answer three times.

Packet layout from the PL (see rtl/dma_udp_packetizer.v):
    [ack BE2][want BE2][fid BE2][total BE2][idx BE2][1394 raw bytes]
Total 827 packets per 800x480 RGB888 frame.

Reply layout to the FPGA (UDP -> 10.212.211.3:1235, big endian):
    [4B magic "GRD1"][2B fid][1B n][1B reserved]
    n x 16B { 1B class, 1B score*100, 2B x1, 2B y1, 2B x2, 2B y2, 6B reserved }

Run (needs root for the AF_PACKET socket):
    sudo -n python3 rk_detect.py \
        --model /home/cat/guide_rknn_test/models/yolov5n_int8.rknn \
        --anchors /home/cat/guide_rknn_test/anchors_yolov5.txt
"""
import argparse
import mmap
import os
import socket
import struct
import subprocess
import sys
import time

import numpy as np
from PIL import Image

FPGA_MAC = bytes.fromhex('123456789abc')
FPGA_MAC_STR = ':'.join('%02x' % b for b in FPGA_MAC)
BOARD_IP = '10.212.211.3'
REPLY_PORT = 1235

W, H = 800, 480
FRAME_BYTES = W * H * 3
DATA_PER_PKT = 1394
TOTAL_PKTS = 827
HDR = 10                      # ack/want/fid/total/idx before the pixels

MAGIC = 0x47524431            # "GRD1"
MAX_BOXES = 20
NO_WANT = 0xFFFF

IMG_SIZE = (640, 640)

CLASSES = ("person", "bicycle", "car", "motorbike", "aeroplane", "bus", "train",
           "truck", "boat", "traffic light", "fire hydrant", "stop sign",
           "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep",
           "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
           "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard",
           "sports ball", "kite", "baseball bat", "baseball glove", "skateboard",
           "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork",
           "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
           "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
           "sofa", "pottedplant", "bed", "diningtable", "toilet", "tvmonitor",
           "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave",
           "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase",
           "scissors", "teddy bear", "hair drier", "toothbrush")

# Chinese labels for the classes a guide dog actually cares about.
ZH = {"person": "\u4eba", "bicycle": "\u81ea\u884c\u8f66", "car": "\u6c7d\u8f66",
      "motorbike": "\u6469\u6258\u8f66", "bus": "\u516c\u4ea4\u8f66", "train": "\u706b\u8f66",
      "truck": "\u5361\u8f66", "chair": "\u6905\u5b50", "dog": "\u72d7",
      "cat": "\u732b", "bottle": "\u74f6\u5b50", "cup": "\u676f\u5b50",
      "diningtable": "\u684c\u5b50", "sofa": "\u6c99\u53d1", "book": "\u4e66",
      "laptop": "\u7b14\u8bb0\u672c", "cell phone": "\u624b\u673a",
      "stop sign": "\u505c\u8f66\u724c", "pottedplant": "\u76c6\u683d"}


def label(cls_id):
    name = CLASSES[cls_id] if 0 <= cls_id < len(CLASSES) else str(cls_id)
    return ZH.get(name, name)


# ------------------------------------------------------------------ detection
def letterbox(im, new_shape=IMG_SIZE):
    h, w = im.shape[:2]
    r = min(new_shape[0] / float(h), new_shape[1] / float(w))
    nw, nh = int(round(w * r)), int(round(h * r))
    if (w, h) != (nw, nh):
        im = np.asarray(Image.fromarray(im).resize((nw, nh), Image.BILINEAR))
    dw, dh = (new_shape[1] - nw) // 2, (new_shape[0] - nh) // 2
    out = np.zeros((new_shape[0], new_shape[1], im.shape[2]), dtype=np.uint8)
    out[dh:dh + nh, dw:dw + nw] = im
    return out, r, dw, dh


def box_process(position, anchors):
    grid_h, grid_w = position.shape[2:4]
    col, row = np.meshgrid(np.arange(grid_w), np.arange(grid_h))
    col = col.reshape(1, 1, grid_h, grid_w)
    row = row.reshape(1, 1, grid_h, grid_w)
    grid = np.concatenate((col, row), axis=1)
    stride = np.array([IMG_SIZE[1] // grid_h, IMG_SIZE[0] // grid_w]).reshape(1, 2, 1, 1)
    col = col.repeat(len(anchors), axis=0)
    row = row.repeat(len(anchors), axis=0)
    anchors = np.array(anchors).reshape(*np.array(anchors).shape, 1, 1)
    box_xy = position[:, :2, :, :] * 2 - 0.5
    box_wh = pow(position[:, 2:4, :, :] * 2, 2) * anchors
    box_xy += grid
    box_xy *= stride
    box = np.concatenate((box_xy, box_wh), axis=1)
    xyxy = np.copy(box)
    xyxy[:, 0] = box[:, 0] - box[:, 2] / 2
    xyxy[:, 1] = box[:, 1] - box[:, 3] / 2
    xyxy[:, 2] = box[:, 0] + box[:, 2] / 2
    xyxy[:, 3] = box[:, 1] + box[:, 3] / 2
    return xyxy


def nms_boxes(boxes, scores, thresh):
    x, y = boxes[:, 0], boxes[:, 1]
    w, h = boxes[:, 2] - boxes[:, 0], boxes[:, 3] - boxes[:, 1]
    areas = w * h
    order = scores.argsort()[::-1]
    keep = []
    while order.size > 0:
        i = order[0]
        keep.append(i)
        xx1 = np.maximum(x[i], x[order[1:]])
        yy1 = np.maximum(y[i], y[order[1:]])
        xx2 = np.minimum(x[i] + w[i], x[order[1:]] + w[order[1:]])
        yy2 = np.minimum(y[i] + h[i], y[order[1:]] + h[order[1:]])
        w1 = np.maximum(0.0, xx2 - xx1)
        h1 = np.maximum(0.0, yy2 - yy1)
        inter = w1 * h1
        ovr = inter / (areas[i] + areas[order[1:]] - inter)
        order = order[np.where(ovr <= thresh)[0] + 1]
    return np.array(keep, dtype=np.int64)


def post_process(outputs, anchors, obj_thresh, nms_thresh):
    boxes, scores, classes_conf = [], [], []
    outs = [_in.reshape([len(anchors[0]), -1] + list(_in.shape[-2:])) for _in in outputs]
    for i in range(len(outs)):
        boxes.append(box_process(outs[i][:, :4], anchors[i]))
        scores.append(outs[i][:, 4:5])
        classes_conf.append(outs[i][:, 5:])

    def flat(a):
        ch = a.shape[1]
        return a.transpose(0, 2, 3, 1).reshape(-1, ch)

    boxes = np.concatenate([flat(v) for v in boxes])
    classes_conf = np.concatenate([flat(v) for v in classes_conf])
    scores = np.concatenate([flat(v) for v in scores])
    class_max = np.max(classes_conf, axis=-1)
    classes = np.argmax(classes_conf, axis=-1)
    prod = class_max * scores.reshape(-1)
    pos = np.where(prod >= obj_thresh)[0]
    if pos.size == 0:
        return []
    boxes, classes, scores = boxes[pos], classes[pos], prod[pos]
    out = []
    for c in set(classes.tolist()):
        idx = np.where(classes == c)[0]
        keep = nms_boxes(boxes[idx], scores[idx], nms_thresh)
        for k in keep:
            out.append((int(classes[idx[k]]), float(scores[idx[k]]), boxes[idx[k]]))
    out.sort(key=lambda t: -t[1])
    return out[:MAX_BOXES]


class Detector(object):
    def __init__(self, model, anchors_path):
        from rknnlite.api import RKNNLite
        vals = [float(v) for v in open(anchors_path).read().split()]
        self.anchors = np.array(vals).reshape(3, -1, 2).tolist()
        self.rknn = RKNNLite(verbose=False)
        if self.rknn.load_rknn(model) != 0:
            raise SystemExit('load_rknn failed: ' + model)
        if self.rknn.init_runtime() != 0:
            raise SystemExit('init_runtime failed')
        print('MODEL %s anchors %s' % (model, np.array(self.anchors).shape), flush=True)

    def run(self, bgr):
        img, ratio, dw, dh = letterbox(bgr)
        rgb = img[:, :, ::-1]
        t0 = time.time()
        outs = self.rknn.inference(inputs=[np.expand_dims(rgb, 0)], data_format='nhwc')
        ms = (time.time() - t0) * 1000.0
        dets = post_process(outs, self.anchors, 0.25, 0.45)
        res = []
        for cls, score, box in dets:
            x0 = (box[0] - dw) / ratio
            x1 = (box[2] - dw) / ratio
            y0 = (box[1] - dh) / ratio
            y1 = (box[3] - dh) / ratio
            x0 = int(max(0, min(W - 1, x0)))
            x1 = int(max(0, min(W - 1, x1)))
            y0 = int(max(0, min(H - 1, y0)))
            y1 = int(max(0, min(H - 1, y1)))
            if x1 - x0 < 8 or y1 - y0 < 8:
                continue
            res.append((cls, score, x0, y0, x1, y1))
        return res, ms


# ------------------------------------------------------------------ transport
def build_reply(fid, boxes):
    buf = bytearray(struct.pack('>IHBB', MAGIC, fid & 0xFFFF, len(boxes) & 0xFF, 0))
    for cls, score, x0, y0, x1, y1 in boxes:
        buf += struct.pack('>BBHHHH6x', cls & 0xFF,
                           int(round(score * 100)) & 0xFF,
                           x0, y0, x1, y1)
    return bytes(buf)


class Receiver(object):
    def __init__(self, ifname):
        self.sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        self.sock.bind((ifname, 0))
        try:
            open('/proc/sys/net/core/rmem_max', 'w').write('33554432')
        except Exception:
            pass
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32 * 1024 * 1024)
        self.sock.settimeout(0.10)
        # One reusable landing buffer for every packet: recv_into + memoryview
        # keeps the hot path allocation-free (see drain()).
        self._buf = bytearray(2048)
        self._mv = memoryview(self._buf)
        self.frames = {}
        self.ack = NO_WANT
        self.want = NO_WANT
        self.pkts = 0
        # Rejection counters.  Without them the program is silent both when
        # nothing arrives and when everything arrives but never assembles,
        # which is impossible to tell apart from the terminal.
        self.raw = 0
        self.bad_mac = 0
        self.bad_ip = 0
        self.bad_len = 0
        self.bad_total = 0
        self.partial_best = 0
        self.last_fid = None

    def drain(self, max_pkts=0):
        """Consume the socket queue; return the ids of frames that completed.

        This is the hot path: 827 packets per frame at ~15 fps means ~12.7k
        calls per second, so nothing here is allowed to allocate per packet.
        The naive version made four copies per packet -- recv() -> new bytes,
        r[6:12], r[14:34], p = r[42:42+plen], then chunk[:n] -- which at this
        rate costs more than the inference itself.  Here recv_into fills one
        reusable buffer and every field is read straight out of a memoryview.

        max_pkts=0 drains everything currently queued.  The old fixed cap of
        6000 (7.2 frames) left a standing backlog, and since only max(done)
        is ever inferred, every other completed frame in the batch was thrown
        away -- that is why the fid jumped ~29 per printed line.
        """
        done = []
        buf = self._buf
        mv = self._mv
        cap = len(buf)
        n = 0
        while max_pkts <= 0 or n < max_pkts:
            try:
                ln = self.sock.recv_into(buf)
            except socket.timeout:
                break
            except OSError:
                break
            n += 1
            self.raw += 1
            if ln < 42 or ln >= cap:
                self.bad_len += 1
                continue
            if mv[6:12] != FPGA_MAC:
                self.bad_mac += 1
                continue
            if mv[23] != 17:                     # IP protocol == UDP
                self.bad_ip += 1
                continue
            plen = ((mv[16] << 8) | mv[17]) - 28
            if plen < HDR or 42 + plen > ln:
                self.bad_len += 1
                continue
            p = mv[42:42 + plen]
            self.pkts += 1
            self.ack = (p[0] << 8) | p[1]
            self.want = (p[2] << 8) | p[3]
            fid = (p[4] << 8) | p[5]
            total = (p[6] << 8) | p[7]
            idx = (p[8] << 8) | p[9]
            self.last_fid = fid
            if total != TOTAL_PKTS or idx >= TOTAL_PKTS:
                self.bad_total += 1
                continue
            slot = self.frames.get(fid)
            if slot is None:
                slot = {'n': 0, 'got': bytearray(TOTAL_PKTS), 'data': bytearray(FRAME_BYTES)}
                self.frames[fid] = slot
                # keep the cache small
                if len(self.frames) > 12:
                    for old in sorted(self.frames)[:-8]:
                        self.frames.pop(old, None)
            if slot['got'][idx]:
                continue
            off = idx * DATA_PER_PKT
            chunk = p[HDR:]
            cnt = len(chunk)
            room = FRAME_BYTES - off
            if cnt > room:
                cnt = room
            slot['data'][off:off + cnt] = chunk[:cnt]
            slot['got'][idx] = 1
            slot['n'] += 1
            if slot['n'] > self.partial_best:
                self.partial_best = slot['n']
            if slot['n'] == TOTAL_PKTS:
                done.append(fid)
        return done

    def take(self, fid):
        slot = self.frames.pop(fid, None)
        if slot is None or slot['n'] != TOTAL_PKTS:
            return None
        # No bytes() copy: the slot is popped, so nothing else can alias it.
        return np.frombuffer(slot['data'], dtype=np.uint8).reshape(H, W, 3)


class FastReceiver(object):
    """Reader for the C reassembler (rxfast.c) via /dev/shm/rxfast.

    The C side does the 12.7k packets/s of recvmmsg + memcpy; this class only
    copies the newest completed frame out of the mapped slot (~0.2 ms) and
    hands it to the detector.  Same interface as Receiver so main() does not
    care which one is in use.

    Layout must match struct shm_hdr in rxfast.c.
    """
    MAGIC = 0x52584654
    OFF_SEQ, OFF_CUR, OFF_ACK, OFF_WANT = 4, 8, 12, 14
    OFF_PKTS, OFF_FRAMES, OFF_RAW = 16, 20, 24
    OFF_BADMAC, OFF_BADLEN, OFF_BADTOTAL = 28, 32, 36
    OFF_FID = 56
    OFF_DATA = 64

    def __init__(self, path='/dev/shm/rxfast'):
        self.path = path
        fd = os.open(path, os.O_RDWR)
        size = os.fstat(fd).st_size
        self._mm = mmap.mmap(fd, size, mmap.MAP_SHARED,
                             mmap.PROT_READ | mmap.PROT_WRITE)
        os.close(fd)
        if struct.unpack_from('<I', self._mm, 0)[0] != self.MAGIC:
            raise RuntimeError('%s: bad magic (rxfast not running?)' % path)
        if struct.unpack_from('<II', self._mm, 40) != (TOTAL_PKTS, FRAME_BYTES):
            raise RuntimeError('%s: geometry mismatch (rebuild rxfast)' % path)
        self._seq = 0
        self._fid = None
        self._frame = None
        self.pkts = self.frames = self.raw = 0
        self.bad_mac = self.bad_ip = self.bad_len = self.bad_total = 0
        self.partial_best = 0
        self.last_fid = None
        self.ack = NO_WANT
        self.want = NO_WANT

    @classmethod
    def alive(cls, path='/dev/shm/rxfast', wait=1.0):
        """True if the daemon is running and actually moving counters."""
        try:
            r = cls(path)
        except Exception:
            return False
        a = struct.unpack_from('<I', r._mm, r.OFF_RAW)[0]
        t0 = time.time()
        while time.time() - t0 < wait:
            time.sleep(0.05)
            if struct.unpack_from('<I', r._mm, r.OFF_RAW)[0] != a:
                return True
        return False

    def drain(self):
        mm = self._mm
        s1 = struct.unpack_from('<I', mm, self.OFF_SEQ)[0]
        if s1 & 1 or s1 == self._seq:
            return []                       # producer mid-write / nothing new
        idx = struct.unpack_from('<I', mm, self.OFF_CUR)[0]
        if idx >= 2:
            return []
        fid = struct.unpack_from('<I', mm, self.OFF_FID + 4 * idx)[0]
        frame = np.frombuffer(mm, np.uint8, FRAME_BYTES,
                              self.OFF_DATA + idx * FRAME_BYTES).reshape(H, W, 3).copy()
        if struct.unpack_from('<I', mm, self.OFF_SEQ)[0] != s1:
            return []                       # torn read, retry next poll
        self._seq = s1
        self._fid = fid
        self._frame = frame
        self.last_fid = fid
        self.partial_best = TOTAL_PKTS
        self.ack, self.want = struct.unpack_from('<HH', mm, self.OFF_ACK)
        self.pkts, self.frames, self.raw = struct.unpack_from('<III', mm, self.OFF_PKTS)
        self.bad_mac, self.bad_len, self.bad_total = struct.unpack_from(
            '<III', mm, self.OFF_BADMAC)
        return [fid]

    def take(self, fid):
        if fid != self._fid:
            return None
        frame, self._frame = self._frame, None
        return frame


def ensure_neigh(iface, ip, mac):
    """Pin the FPGA's MAC into the neighbour table before the first reply.

    The PL's udp_rx only *accepts* frames; it never answers ARP (see
    0x3C's `done` counter: ARP arrives, fails the EtherType check, and is
    dropped).  So the moment this entry is missing -- a fresh RK boot, or
    the entry ageing out -- the kernel parks every reply in an unreachable
    neighbour queue:

        sendto() returns success   -> no exception, the loop looks healthy
        TX packets ticks up ~1/s    -> but those are ARP requests only
        tcpdump 'ip dst <FPGA>'     -> 0 packets captured
        FPGA RES_SEQ                -> stays 0 forever

    Installing a permanent entry makes the return path independent of the
    reboot order of the two boards.
    """
    cmd = ['ip', 'neigh', 'replace', ip, 'lladdr', mac,
           'dev', iface, 'nud', 'permanent']
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except Exception as exc:
        print('WARN: neighbour install raised %s (run as root?)' % exc, flush=True)
        return False
    if r.returncode != 0:
        detail = (r.stderr or r.stdout or '').strip()
        print('WARN: neighbour install failed: %s' % detail, flush=True)
        return False
    print('neighbour %s -> %s pinned permanent on %s' % (ip, mac, iface), flush=True)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', default='/home/cat/guide_rknn_test/models/yolov5n_int8.rknn')
    ap.add_argument('--anchors', default='/home/cat/guide_rknn_test/anchors_yolov5.txt')
    ap.add_argument('--iface', default='eth0')
    ap.add_argument('--seconds', type=float, default=0.0, help='0 = run forever')
    ap.add_argument('--min-interval', type=float, default=0.0,
                    help='skip inference faster than this (s)')
    ap.add_argument('--dump', default='', help='write the last frame here as PPM')
    ap.add_argument('--hb', type=float, default=2.0,
                    help='heartbeat interval in s while no frame completes (0=off)')
    ap.add_argument('--rx', default='auto', choices=('auto', 'c', 'py'),
                    help='packet reassembler: the C daemon via /dev/shm/rxfast, '
                         'pure Python, or auto (C when it is running)')
    a = ap.parse_args()

    det = Detector(a.model, a.anchors)
    ensure_neigh(a.iface, BOARD_IP, FPGA_MAC_STR)
    rx = None
    if a.rx in ('auto', 'c'):
        if FastReceiver.alive():
            rx = FastReceiver()
            print('RX path: C reassembler (/dev/shm/rxfast)', flush=True)
        elif a.rx == 'c':
            raise SystemExit('/dev/shm/rxfast is not moving; start ./rxfast first')
        else:
            print('RX path: pure Python (rxfast not running)', flush=True)
    if rx is None:
        rx = Receiver(a.iface)
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    results = {}
    t_start = time.time()
    t_prev = time.time()
    last_run = 0.0
    done_frames = 0
    answered = {}
    print('LISTENING on %s -> reply to %s:%d' % (a.iface, BOARD_IP, REPLY_PORT), flush=True)
    hb = time.time()

    while a.seconds <= 0 or time.time() - t_start < a.seconds:
        # 0. heartbeat: silence used to mean "no frame completed", which covers
        #    four very different faults (nothing on the wire / wrong MAC /
        #    rejected header / lost packets).  Print the numbers instead.
        if a.hb and time.time() - hb >= a.hb:
            hb = time.time()
            print('RX raw=%d pkts=%d frames=%d best=%d/%d '
                  'rej[mac=%d ip=%d len=%d total=%d] fid=%s ack=%04x want=%04x'
                  % (rx.raw, rx.pkts, done_frames, rx.partial_best, TOTAL_PKTS,
                     rx.bad_mac, rx.bad_ip, rx.bad_len, rx.bad_total,
                     '-' if rx.last_fid is None else rx.last_fid,
                     rx.ack, rx.want), flush=True)
            rx.partial_best = 0
        # 1. send back anything the FPGA is explicitly asking for
        if rx.want != NO_WANT and rx.want in results:
            tx.sendto(build_reply(rx.want, results[rx.want]), (BOARD_IP, REPLY_PORT))
            answered[rx.want] = answered.get(rx.want, 0) + 1
            if answered[rx.want] == 1:
                print('RESEND fid=%d (want) boxes=%d' % (rx.want, len(results[rx.want])), flush=True)

        # 2. drain the socket, find the newest complete frame
        t0 = time.time()
        done = rx.drain()
        t1 = time.time()
        drain_ms = (t1 - t0) * 1000.0
        if not done:
            # The C path returns instantly when nothing new was published, so
            # yield here instead of spinning at 100% CPU.
            time.sleep(0.002)
            continue
        fid = max(done)

        # 3. run the detector on the newest frame only
        if a.min_interval and time.time() - last_run < a.min_interval:
            continue
        bgr = rx.take(fid)
        if bgr is None:
            continue
        last_run = time.time()
        dets, ms = det.run(bgr)
        boxes = [(c, s, x0, y0, x1, y1) for (c, s, x0, y0, x1, y1) in dets]
        results[fid] = boxes
        if len(results) > 8:
            for old in sorted(results)[:-8]:
                results.pop(old, None)
        done_frames += 1

        tx.sendto(build_reply(fid, boxes), (BOARD_IP, REPLY_PORT))
        answered[fid] = answered.get(fid, 0) + 1

        desc = ', '.join('%s %.2f (%d,%d)-(%d,%d)' % (label(c), s, x0, y0, x1, y1)
                         for c, s, x0, y0, x1, y1 in boxes[:6])
        print('fid=%-6d pkts=%-7d det=%-2d infer=%.1fms drain=%.1fms loop=%.1fms %s'
              % (fid, rx.pkts, len(boxes), ms, drain_ms, (time.time() - t_prev) * 1000.0,
                 desc if desc else '(none)'), flush=True)
        t_prev = time.time()

        if a.dump:
            with open(a.dump, 'wb') as f:
                f.write(b'P6 %d %d 255\n' % (W, H))
                f.write(bytes(bgr))

    print('DONE frames=%d pkts=%d raw=%d rej[mac=%d ip=%d len=%d total=%d]'
          % (done_frames, rx.pkts, rx.raw, rx.bad_mac, rx.bad_ip,
             rx.bad_len, rx.bad_total), flush=True)


if __name__ == '__main__':
    main()