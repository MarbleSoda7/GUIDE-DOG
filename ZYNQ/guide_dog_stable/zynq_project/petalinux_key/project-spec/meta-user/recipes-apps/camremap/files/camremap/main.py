"""Dual OV5640 capture with BOTH cameras sent through the PL UDP datapath.

Every "pair" carries camera1 and then camera2 as two consecutive DMA bursts
that share one pair_id, so the RK receiver can rebuild both eyes and show
them side by side.

Run:  python3 -m camremap              (continuous, stereo pairs to UDP)
      python3 -m camremap --frames 5   (bounded test, 5 pairs)
      python3 -m camremap --fps 5      (pairs per second)
"""
import argparse
import os
import sys
import time
import xml.etree.ElementTree as ET

from .dma import DmaMm2s
from .eth import EthStream, WIRE_BYTES
from .hw import DevMemBus, Overlay
from .vdma import VdmaS2mm, SR_ERROR_MASK, SR_HALTED
from .remap import PlRemap, RemapError

W, H, BPP = 800, 480, 3
FRAME_BYTES = W * H * BPP                  # 1,152,000
# Keep two independent three-frame capture rings in the reserved DDR region.
SLOT = FRAME_BYTES                           # 0x00119400 per 800x480 RGB888 frame

# Keep frame buffers outside the U-Boot image load window at 0x10000000.
# Must match reserved-memory "dualcam" in system-user.dtsi (no-map).
RES_BASE = 0x30000000
RES_SIZE = 0x01000000

OFF_CAP = [0 * SLOT, 1 * SLOT, 2 * SLOT]   # VDMA frame stores
OFF_CAP2 = [0x00400000 + i * SLOT for i in range(3)]
OFF_OUT = 0x00800000              # stable camera1 raw snapshot
OFF_SNAPSHOT = 0x00920000         # stable camera2 raw snapshot
OFF_LUT1 = 0x00A40000             # left Q10.6 LUT payload
OFF_LUT2 = 0x00A60000             # right Q10.6 LUT payload
LUT_RESERVED = 0x00008000
OFF_CORRECTED1 = 0x00C00000        # corrected camera1 frame
OFF_CORRECTED2 = 0x00D20000        # corrected camera2 frame
HARDWARE_CONTRACT = "dual-ov5640-independent-vdma-800x480-rgb888-stereo-pair-to-udp"

# (camera_id, VDMA attribute, capture offsets, stable raw offset, corrected offset)
STREAMS = (
    (1, "vdma", "cap_pa", OFF_CAP, OFF_OUT, OFF_CORRECTED1),
    (2, "vdma2", "cap2_pa", OFF_CAP2, OFF_SNAPSHOT, OFF_CORRECTED2),
)
# The two OV5640s free-run from independent VDMA capture paths, so their frame
# boundaries sit at a fixed but arbitrary phase offset.  A strict skew limit
# would reject every pair; this tolerance is just over one 15 fps frame period
# and only catches an eye that has stalled.
PAIR_TOL_S = 0.070    # max drain-time skew between the two eyes of one pair


def validate_snapshot_layout():
    """Fail closed if software geometry or reserved-region allocation changes."""
    if (W, H, BPP, FRAME_BYTES, SLOT) != (800, 480, 3, 1_152_000, 1_152_000):
        raise RuntimeError("dual camera capture requires fixed 800x480 RGB888 geometry")
    if len(OFF_CAP) != 3 or OFF_CAP != [0, SLOT, 2 * SLOT]:
        raise RuntimeError("camera1 requires a three-slot circular ring")
    if len(OFF_CAP2) != 3 or OFF_CAP2 != [0x00400000 + i * SLOT for i in range(3)]:
        raise RuntimeError("camera2 requires its independent three-slot ring")
    if len(STREAMS) != 2 or [s[0] for s in STREAMS] != [1, 2]:
        raise RuntimeError("stereo TX requires exactly camera1 and camera2")
    if OFF_OUT + FRAME_BYTES > OFF_SNAPSHOT:
        raise RuntimeError("camera1 and camera2 raw slots must not overlap")
    regions = ([(o, FRAME_BYTES) for o in OFF_CAP] +
               [(o, FRAME_BYTES) for o in OFF_CAP2] +
               [(OFF_OUT, FRAME_BYTES), (OFF_SNAPSHOT, FRAME_BYTES),
                (OFF_CORRECTED1, FRAME_BYTES), (OFF_CORRECTED2, FRAME_BYTES),
                (OFF_LUT1, LUT_RESERVED), (OFF_LUT2, LUT_RESERVED)])
    for i, (offset, size) in enumerate(regions):
        if (RES_BASE + offset) % 8 or size % 8:
            raise RuntimeError("capture/LUT buffers require 8-byte alignment")
        if offset < 0 or offset + size > RES_SIZE:
            raise RuntimeError("capture buffer outside reserved DDR region")
        for other, other_size in regions[:i]:
            if offset < other + other_size and other < offset + size:
                raise RuntimeError("capture buffers overlap in reserved DDR region")

def validate_hardware_contract(hwh_path, require_remap=False):
    """Require capture/UDP paths and, in PL mode, the generated remap IP."""
    try:
        root = ET.parse(hwh_path).getroot()
        modules = {m.get("INSTANCE"): m for m in root.iter("MODULE")}
        required = {"axi_vdma_0", "axi_vdma_1", "ov5640_to_lcd_0",
                    "ov5640_to_lcd_1", "v_vid_in_axi4s_0", "v_vid_in_axi4s_1",
                    "axis_rgb24_to_32_0", "axis_rgb24_to_32_1",
                    "axi_dma_udp_0", "eth_stream_0"}
        missing = required.difference(modules)
        if missing:
            raise ValueError("dual-camera hardware modules missing: %s" % sorted(missing))
        if require_remap:
            remap = modules.get("pl_remap_accel_0")
            guard = modules.get("remap_axi_guard_0")
            if remap is None or remap.get("VLNV") != "xilinx.com:hls:pl_remap_accel:1.0":
                raise ValueError("PL mode requires pl_remap_accel_0 with the generated VLNV")
            if guard is None:
                raise ValueError("PL mode requires remap_axi_guard_0")
            # HWH master MEMRANGEs can live under the processing system,
            # so inspect the whole document, as parse_hwh does.
            guard_ranges = [x for x in root.iter("MEMRANGE")
                            if x.get("INSTANCE") == "remap_axi_guard_0"
                            and x.get("MASTERBUSINTERFACE") == "M_AXI_GP0"]
            if len(guard_ranges) != 1 or int(guard_ranges[0].get("BASEVALUE", "0"), 16) != 0x40020000:
                raise ValueError("remap_axi_guard_0 must be AXI-Lite at 0x40020000")

        for camera in (1, 2):
            bridge = modules["axis_rgb24_to_32_%d" % (camera - 1)]
            if bridge.get("MODTYPE") != "axis_rgb24_to_32_node_diag":
                raise ValueError("camera%d RGB24 byte-packing bridge is incompatible" % camera)
            bridge_ports = {p.get("NAME"): p for p in bridge.findall("./PORTS/PORT")}
            for name, bits in (("s_axis_tdata", 24), ("m_axis_tdata", 32)):
                port = bridge_ports[name]
                if int(port.get("LEFT", "0")) - int(port.get("RIGHT", "0")) + 1 != bits:
                    raise ValueError("camera%d RGB bridge port width mismatch" % camera)
            if int(bridge_ports["aclk"].get("CLKFREQUENCY", "0")) != 100_000_000:
                raise ValueError("camera%d RGB bridge clock mismatch" % camera)
            links = bridge_ports["m_axis_tdata"].findall("./CONNECTIONS/CONNECTION")
            vdma = "axi_vdma_%d" % (camera - 1)
            if not any(c.get("INSTANCE") == vdma and
                       c.get("PORT") == "s_axis_s2mm_tdata" for c in links):
                raise ValueError("camera%d bridge is not connected to %s" % (camera, vdma))

        for name, width in (("axi_vdma_0", 32), ("axi_vdma_1", 32)):
            params = {p.get("NAME"): p.get("VALUE")
                      for p in modules[name].findall("./PARAMETERS/PARAMETER")}
            if int(params["C_S_AXIS_S2MM_TDATA_WIDTH"], 0) != width:
                raise ValueError("%s stream width mismatch" % name)
            if int(params["C_NUM_FSTORES"], 0) != 3:
                raise ValueError("%s must use three independent frame stores" % name)
    except (OSError, ET.ParseError, ValueError, KeyError, TypeError) as e:
        raise RuntimeError("incompatible dual-camera hardware contract: %s" % e) from e
    return HARDWARE_CONTRACT


DATA_DIRS = ["/media/sd-mmcblk0p1/camremap", "/run/media/mmcblk0p1/camremap",
             "/usr/share/camremap"]


def find_file(name, override=None):
    if override:
        return override
    for d in DATA_DIRS:
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    raise FileNotFoundError("%s not found in %s" % (name, DATA_DIRS))


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, flush=True)


class FrameOverrun(RuntimeError):
    """The circular writer caught the slot selected for processing."""


class TxFatalError(RuntimeError):
    """Packetizer may retain a partial frame; require PL reset before reuse."""


class Pipeline:
    def __init__(self, args, bus=None):
        validate_snapshot_layout()
        self.args = args
        self.bus = bus or DevMemBus()
        hwh_path = find_file("led_test_wrapper.hwh", args.hwh)
        validate_hardware_contract(hwh_path, require_remap=(args.rectify == "pl"))
        self.ol = Overlay(hwh_path, bus=self.bus)
        need = ["axi_vdma_0", "axi_vdma_1", "axi_dma_udp_0", "eth_stream_0"]
        if args.rectify == "pl":
            need.extend(["pl_remap_accel_0", "remap_axi_guard_0"])
        missing = [n for n in need if n not in self.ol.ip_dict]
        if missing:
            raise RuntimeError("hwh lacks IP: %s" % missing)
        self.mem = self.bus.region(RES_BASE, RES_SIZE)
        self.remap = None
        if args.rectify == "pl":
            self.remap = PlRemap(
                self.ol.pl_remap_accel_0, self.mem, (OFF_LUT1, OFF_LUT2),
                guard=self.ol.remap_axi_guard_0, lut_reserved=LUT_RESERVED,
                allow_synthetic=args.allow_synthetic_lut,
                verify_crc=args.verify_remap_crc,
                manifest_path=find_file(args.lut_manifest))
            self.remap.upload_lut(find_file(args.lut_left), 1)
            self.remap.upload_lut(find_file(args.lut_right), 2)
            self.remap.validate_pair()
            log("PL remap LUTs validated and uploaded")
        self.cap_pa = [self.mem.pa(o) for o in OFF_CAP]
        self.cap2_pa = [self.mem.pa(o) for o in OFF_CAP2]
        self.vdma = VdmaS2mm(self.ol.axi_vdma_0, self.cap_pa, W, H, BPP)
        self.vdma2 = VdmaS2mm(self.ol.axi_vdma_1, self.cap2_pa, W, H, BPP)
        # Both rings are Ethernet sources; each keeps its own stability buffer.
        self.streams = []
        for camera_id, vdma_attr, pa_attr, offsets, dst, corrected in STREAMS:
            vdma = getattr(self, vdma_attr)
            capture_pa = getattr(self, pa_attr)
            if capture_pa != [self.mem.pa(o) for o in offsets]:
                raise RuntimeError("camera%d Ethernet ring does not match TX offsets" % camera_id)
            self.streams.append({"camera_id": camera_id, "vdma": vdma,
                                 "capture_pa": capture_pa, "offsets": list(offsets),
                                 "dst": dst, "corrected": corrected, "last_writer": None})
        self.dma = DmaMm2s(self.ol.axi_dma_udp_0)
        self.eth = EthStream(self.ol.eth_stream_0)
        # Both VDMAs halt during each snapshot, then resume circular capture.
        self._frames_dropped = 0
        self._pair_rejected = 0
        self._pair_id = 0
        self._last_udp_done = None

    def init_camera(self):
        if self.args.skip_camera:
            log("camera init skipped")
            return
        from .gpio import open_sccb_lines
        from .ov5640 import OV5640, Sccb
        table = find_file("ov5640_800x480_rgb565.json", self.args.ov_table)
        for camera in (1, 2):
            scl, sda = open_sccb_lines(camera=camera)
            try:
                log("initializing OV5640 camera%d" % camera)
                OV5640(Sccb(scl, sda)).configure(table, log=log)
            finally:
                scl.close()
                sda.close()

    def setup(self):
        log("snapshot hardware contract: " + HARDWARE_CONTRACT)
        try:
            self.eth.verify_protocol()
        except TimeoutError as exc:
            raise RuntimeError("the loaded bitstream has no stereo metadata "
                               "handshake (%s); flash the stereo bitstream "
                               "first" % exc)
        log("ethernet stereo metadata handshake verified (packet v1)")
        for s in self.streams:
            log("Ethernet frame source: camera%d ring at 0x%08X -> raw 0x%08X%s"
                % (s["camera_id"], RES_BASE + s["offsets"][0], RES_BASE + s["dst"],
                   " -> corrected 0x%08X" % (RES_BASE + s["corrected"]) if self.remap else ""))
        # The RK packetizer sends a short final UDP packet; clear the output
        # slots once so no stale bytes can be exposed by a later hardware change.
        for offset in (OFF_OUT, OFF_SNAPSHOT, OFF_CORRECTED1, OFF_CORRECTED2):
            self.mem.u8[offset:offset + SLOT] = 0
        self.init_camera()
        st = self.eth.start()
        log("eth_stream status=0x%08X (bit4 TXC locked)" % st)
        self.dma.start()
        baseline = self.eth.counters()["udp_done"]
        self._last_udp_done = self.eth.wait_udp_done(baseline, packets=0)
        for s in self.streams:
            s["last_writer"] = None
        self.vdma.start()
        self.vdma2.start()
        self.vdma.validate_geometry(W, H, BPP)
        self.vdma2.validate_geometry(W, H, BPP)
        self.wait_camera1_frame()
        for s in self.streams:
            log("camera%d VDMA ring (Ethernet source): %s"
                % (s["camera_id"], ", ".join("0x%08X" % a for a in s["capture_pa"])))

    def check_capture_status(self):
        """Reject halted capture and sticky frame, line, or bus errors."""
        status0 = self.vdma.status()
        status1 = self.vdma2.status()
        if status0 & (SR_ERROR_MASK | SR_HALTED):
            for s in self.streams:
                s["last_writer"] = None
            raise RuntimeError("camera1 VDMA error 0x%08X" % status0)
        if status1 & (SR_ERROR_MASK | SR_HALTED):
            raise RuntimeError("camera2 VDMA error 0x%08X" % status1)
        return status0, status1

    def wait_camera1_frame(self, timeout=2.0):
        """Warm both three-slot rings; the legacy method name is retained.

        Writer transitions establish initialization only, never exposure sync
        or source ownership. Copying still requires both channels HALTED.
        """
        previous = [s["vdma"].writer_slot() for s in self.streams]
        advances = [0, 0]
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.check_capture_status()
            for i, stream in enumerate(self.streams):
                current = stream["vdma"].writer_slot()
                if not 0 <= current < 3:
                    raise RuntimeError("invalid capture writer slot")
                if current != previous[i]:
                    advances[i] += 1
                    previous[i] = current
            if min(advances) >= 3:
                return
            time.sleep(0.0005)
        raise TimeoutError("both VDMA rings did not complete startup warmup")

    def warmup_after_resume(self, timeout=2.0):
        """Let each resumed three-slot ring complete a full rotation.

        HALTED after RS=0 only means current VDMA operations are complete; it
        does not prove that a frame interrupted at the stop boundary is whole.
        After resume, wait for three writer transitions before the next
        snapshot so writer-1 cannot select that potentially partial slot.
        This strict bound may reduce throughput; exposure sync and frame rate
        remain unmeasured.
        """
        transitions = [0, 0]
        previous = [s["vdma"].writer_slot() for s in self.streams]
        deadline = time.monotonic() + float(timeout)
        while min(transitions) < 3:
            self.check_capture_status()
            for i, stream in enumerate(self.streams):
                current = stream["vdma"].writer_slot()
                if not 0 <= current < len(stream["capture_pa"]):
                    raise RuntimeError("invalid camera%d resumed writer slot %d" % (stream["camera_id"], current))
                if current != previous[i]:
                    transitions[i] += 1
                    previous[i] = current
            if time.monotonic() >= deadline:
                raise TimeoutError("VDMA ring did not complete post-resume rotation")
            time.sleep(0.0005)

    def snapshot_pair(self):
        """Freeze BOTH circular writers before copying completed slots.

        Running PARK_PTR sampling is not ownership and can suffer ABA.  PG020
        RS=0 graceful stop is used only with HALTED confirmation; a timeout
        aborts without claiming a frame. Each channel has a 250 ms stop bound.
        Both free-running sensors remain unsynchronized; fps is unmeasured.
        This intentionally lowers throughput; a future owner protocol can
        avoid stop/copy/resume without relying on repeated writer samples.
        """
        stopped = []
        try:
            for stream in self.streams:
                stream["vdma"].graceful_stop(timeout=0.25)
                stopped.append(stream["vdma"])
            for stream in self.streams:
                status = stream["vdma"].status()
                if not status & SR_HALTED or status & SR_ERROR_MASK:
                    raise RuntimeError("camera%d VDMA error 0x%08X" % (stream["camera_id"], status))
            now = time.monotonic()
            picks = []
            for stream in self.streams:
                slot, writer = stream["vdma"].completed_slot()
                if not 0 <= slot < len(stream["capture_pa"]):
                    raise RuntimeError("invalid camera%d completed slot %d" % (stream["camera_id"], slot))
                start, dst = stream["offsets"][slot], stream["dst"]
                self.mem.u8[dst:dst + FRAME_BYTES] = self.mem.u8[start:start + FRAME_BYTES]
                stream["last_writer"] = writer
                picks.append((stream, stream["capture_pa"][slot], writer, slot, now))
            return picks
        finally:
            # Only a pair for which BOTH channels reached HALTED is eligible
            # for the full post-resume rotation. If the second stop failed,
            # resume only what was stopped and propagate that failure; do not
            # claim the partial pair is safe.
            if len(stopped) == len(self.streams):
                for vdma in stopped:
                    vdma.resume()
                self.warmup_after_resume()
            else:
                for vdma in stopped:
                    vdma.resume()

    def one_pair(self):
        """Send one stereo pair: camera1 burst then camera2 burst, same pair_id."""
        self._pair_id = (self._pair_id + 1) & 0xFFFF
        pair_id = self._pair_id

        # Freeze and copy both eyes before touching remap or Ethernet.
        # Capture synchronization/frame rate remain unmeasured by this path.
        picks = self.snapshot_pair()
        self.check_capture_status()

        # Phase 1: both remaps must complete before any metadata/TX.
        prepared = []
        for stream, _src, _writer, _slot, _t in picks:
            tx_offset = stream["dst"]
            if self.remap:
                self.remap.process(self.mem.pa(stream["dst"]), stream["camera_id"],
                                   self.mem.pa(stream["corrected"]))
                tx_offset = stream["corrected"]
            prepared.append((stream, tx_offset))

        # Phase 2: wait for packetizer completion before changing metadata.
        timings = []
        try:
            for stream, tx_offset in prepared:
                # Baseline was confirmed idle at setup / previous frame end.
                before = self._last_udp_done
                if before is None:
                    raise RuntimeError("packetizer idle baseline is not established")
                self.eth.set_frame_meta(stream["camera_id"], pair_id)
                self.dma.send(self.mem.pa(tx_offset), WIRE_BYTES)
                timings.append(self.dma.wait(timeout=2.0))
                self._last_udp_done = self.eth.wait_udp_done(before, timeout=2.0)
        except (TimeoutError, RuntimeError, ValueError) as exc:
            raise TxFatalError("TX failed; packetizer may retain frame data; PL reset required: %s" % exc) from exc

        return pair_id, picks, timings

    def run(self):
        self.setup()
        time.sleep(0.1)
        n = 0
        t_last = time.monotonic()
        period = 1.0 / self.args.fps if self.args.fps > 0 else 0.0
        while self.args.frames <= 0 or n < self.args.frames:
            t0 = time.monotonic()
            try:
                pair_id, picks, timings = self.one_pair()
            except FrameOverrun as e:
                self._frames_dropped += 1
                log("pair %d dropped: %s" % (n, e))
                continue
            except RemapError as e:
                # A remap timeout/AXI fault may leave the HLS core writing DDR;
                # never retry it by merely restarting VDMA.  PL reconfiguration
                # is required before another process can safely use this path.
                log("pair %d fatal remap error: %s; PL reconfiguration required" % (n, e))
                raise SystemExit(2) from e
            except TxFatalError as e:
                log("pair %d fatal TX error: %s" % (n, e))
                raise SystemExit(3) from e
            except (TimeoutError, RuntimeError) as e:
                log("pair %d capture hardware error: %s; restarting VDMA only" % (n, e))
                # Capture recovery only; remap and TX errors never reach here.
                self.vdma.start()
                self.vdma2.start()
                self.wait_camera1_frame()
                for s in self.streams:
                    s["last_writer"] = None
                time.sleep(0.05)
                continue
            n += 1
            if n == 1 or time.monotonic() - t_last >= 5.0:
                c = self.eth.counters()
                log("pair %d id=%d cam1 slot=%d dma=%.1fms cam2 slot=%d dma=%.1fms "
                    "udp_done=%d rejected=%d vdma1=0x%08X vdma2=0x%08X"
                    % (n, pair_id, picks[0][3], timings[0] * 1e3,
                       picks[1][3], timings[1] * 1e3, c["udp_done"],
                       self._pair_rejected, self.vdma.status(), self.vdma2.status()))
                t_last = time.monotonic()
            if period:
                dt = period - (time.monotonic() - t0)
                if dt > 0:
                    time.sleep(dt)
        log("done, %d pairs" % n)


def parse_args(argv=None):
    p = argparse.ArgumentParser(prog="dualcam")
    p.add_argument("--frames", type=int, default=0, help="0 = run forever")
    p.add_argument("--fps", type=float, default=15.0,
                   help="stereo PAIRS per second, 0 = max")
    # Accepted for backward compatibility with SD-card camremap/args files
    # written for the single-camera build ("--export-pair"); both eyes are
    # always exported now, so the flag has no effect.
    p.add_argument("--export-pair", action="store_true",
                   help=argparse.SUPPRESS)
    p.add_argument("--skip-camera", action="store_true", help="do not program OV5640")
    p.add_argument("--rectify", choices=("pl", "off"), default="off",
                   help="use PL remap or raw capture (default: off; old bitstreams stay raw)")
    p.add_argument("--allow-synthetic-lut", action="store_true",
                   help="allow calibration_valid=false LUTs for explicit smoke tests")
    p.add_argument("--verify-remap-crc", action="store_true",
                   help="CPU-read remap output and compare its CRC")
    p.add_argument("--lut-manifest", default="remap_manifest.json")
    p.add_argument("--lut-left", default="left_remap.rmp")
    p.add_argument("--lut-right", default="right_remap.rmp")
    p.add_argument("--hwh")
    p.add_argument("--ov-table")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if not os.path.exists("/dev/mem"):
        sys.exit("/dev/mem missing")
    Pipeline(args).run()


if __name__ == "__main__":
    main()
