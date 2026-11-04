"""eth_stream_stage3_diag AXI-Lite (guide_dog_main eth_rtl/eth_stream.v).

Network identity is fixed in RTL: board 10.212.211.3 -> PC 10.212.211.2,
destination MAC broadcast, UDP 1234 -> 1234.  The packetizer frames every
1,152,000 DMA bytes (one full 800x480 RGB888 image) into 827 UDP packets.
Packets 0..825 carry 1394 image bytes; the last packet carries only the
remaining 556 image bytes, so its UDP payload is 568 bytes (12 + 556).
The RK receiver rejects any packet whose payload length differs from the
expected value, which is why the tail must stay short instead of padded.

Wire format v1 (12-byte metadata header, then raw RGB888):
  [D2][C2][ver=01][camera_id][pair_id BE16][total=827 BE16]
  [packet_index BE16][payload_len BE16][image bytes]
The header exists only on the wire; the DDR image stays 1,152,000 bytes.
"""
import math
import time

STATUS = 0x00
CTRL = 0x04
DBG_IN_BEATS = 0x18
DBG_IN_LAST = 0x1C
DBG_PKT_START = 0x2C
DBG_UDP_DONE = 0x34
DBG_STATE = 0x38
DBG_ETH = 0x3C

PAYLOAD_BYTES = 1394
TOTAL_PACKETS = 827
FRAME_BYTES = 800 * 480 * 3                       # 1,152,000
WIRE_BYTES = FRAME_BYTES                          # tail packet is short, not padded
STATUS_LOCKED = 1 << 4
STATUS_META = 1 << 5

# Packet protocol v1 magic/version, mirrored by dma_udp_packetizer.v.
PKT_MAGIC = b"\xD2\xC2"
PKT_VERSION = 1
HDR_BYTES = 12


class EthStream:
    def __init__(self, mmio):
        self.m = mmio

    def start(self, timeout=2.0):
        """Select the packetizer (sweep mode 0) and TXC phase 0, as in guide_dog."""
        self.m.write(CTRL, 0)
        t0 = time.monotonic()
        while True:
            s = self.m.read(STATUS)
            if s & STATUS_LOCKED and ((s >> 2) & 3) == 0:
                return s
            if time.monotonic() - t0 > timeout:
                return s
            time.sleep(0.001)

    def verify_protocol(self, timeout=0.2):
        """Prove the stereo metadata handshake exists in the loaded bitstream.

        There is no room for a read-only PROTO register: the AXI-Lite address
        port is 6 bits wide and every one of the 16 slots is already used, so
        an address of 0x40 would alias STATUS.  Instead, commit a harmless
        metadata value (camera 1, pair 0) and require STATUS bit5 to toggle.
        Only the v1 stereo RTL implements that handshake.
        """
        self.set_frame_meta(1, 0, timeout=timeout)
        return True

    def set_frame_meta(self, camera_id, pair_id, timeout=0.2):
        """Commit camera_id/pair_id for the next DMA burst.

        CTRL bit31 commits, bit6:5 carry camera_id, bit22:7 carry pair_id.
        The other CTRL fields keep their current values so a metadata write
        never disturbs sweep mode or TXC sampling phase.
        """
        if camera_id not in (1, 2):
            raise ValueError("camera_id must be 1 or 2")
        value = ((int(pair_id) & 0xFFFF) << 7) | ((camera_id & 0x3) << 5) | (1 << 31)
        before = self.m.read(STATUS) & STATUS_META
        self.m.write(CTRL, value)
        t0 = time.monotonic()
        while time.monotonic() - t0 < timeout:
            if (self.m.read(STATUS) & STATUS_META) != before:
                return True
            time.sleep(0.0002)
        raise TimeoutError("ethernet metadata was not applied (STATUS bit5)")

    def wait_udp_done(self, previous, timeout=2.0, packets=TOTAL_PACKETS):
        """Wait for exactly one frame's 827 packet completions, modulo 2**32.

        dma_udp_packetizer.v ST_WAIT increments DBG_UDP_DONE per UDP packet.
        Its diagnostic buses use two-stage CDC, not an atomic frame handshake:
        require three spaced equal reads with ST_FILL, no held/input AXIS beat,
        and ready asserted. This assumes clocks run and CDC settles within the
        0.5 ms sample interval; it is not a formal CDC/ownership guarantee.
        Only a single sender may use this packetizer. Timeout must stop TX.
        packets=0 verifies a known idle baseline without sending another frame.
        """
        timeout = float(timeout)
        if not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("UDP completion timeout must be finite and positive")
        if packets not in (0, TOTAL_PACKETS):
            raise ValueError("UDP wait must cover zero or one fixed-size frame")
        previous = int(previous) & 0xFFFFFFFF
        deadline = time.monotonic() + timeout
        stable = 0
        while time.monotonic() < deadline:
            current = self.m.read(DBG_UDP_DONE) & 0xFFFFFFFF
            state = self.m.read(DBG_STATE) >> 30
            live = self.m.read(DBG_IN_LAST) & 0xFFFF
            confirm = self.m.read(DBG_UDP_DONE) & 0xFFFFFFFF
            # Live bits: beat_valid=8, state=4:3, tvalid=2, tready=1.
            idle = state == 0 and (live & 0x11E) == 2
            if current == confirm and ((current - previous) & 0xFFFFFFFF) == packets and idle:
                stable += 1
                if stable == 3:
                    return current
            else:
                stable = 0
            time.sleep(0.0005)
        raise TimeoutError("UDP packetizer completion counter timeout")

    def counters(self):
        return {"status": self.m.read(STATUS),
                "dma_tlasts": self.m.read(DBG_IN_LAST) >> 16,
                "pkt_start": self.m.read(DBG_PKT_START),
                "udp_done": self.m.read(DBG_UDP_DONE),
                "eth": self.m.read(DBG_ETH)}
