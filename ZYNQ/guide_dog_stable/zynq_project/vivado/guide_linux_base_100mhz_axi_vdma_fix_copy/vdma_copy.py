"""AXI VDMA S2MM (PG020), programmed in the same order as the Xilinx driver
used by the board-verified guide_dog_main bare-metal code."""
import time

PARK_PTR = 0x28
S2MM_CR = 0x30
S2MM_SR = 0x34
S2MM_VSIZE = 0xA0
S2MM_HSIZE = 0xA4
S2MM_STRIDE = 0xA8
S2MM_ADDR0 = 0xAC          # 32-bit address map: frame stores at 0xAC/0xB0/0xB4

CR_RS = 1 << 0
CR_CIRCULAR = 1 << 1
CR_RESET = 1 << 2
SR_HALTED = 1 << 0


class VdmaS2mm:
    def __init__(self, mmio, frame_addrs, width=800, height=480, bpp=3):
        self.m = mmio
        self.addrs = [int(a) for a in frame_addrs]
        self.hsize = int(width) * int(bpp)
        self.vsize = int(height)

    def reset(self, timeout=1.0):
        self.m.write(S2MM_CR, CR_RESET)
        t0 = time.monotonic()
        while self.m.read(S2MM_CR) & CR_RESET:
            if time.monotonic() - t0 > timeout:
                raise TimeoutError("VDMA S2MM reset timeout")
            time.sleep(0.001)

    def start(self):
        """Reset once, configure all frame stores, and start circular capture."""
        self.reset()
        self.m.write(S2MM_CR, CR_CIRCULAR)
        for i, a in enumerate(self.addrs):
            self.m.write(S2MM_ADDR0 + 4 * i, a)
        self.m.write(S2MM_STRIDE, self.hsize)
        self.m.write(S2MM_HSIZE, self.hsize)
        self.resume()

    def resume(self):
        """Resume circular S2MM without resetting or changing frame ownership."""
        self.m.write(S2MM_CR, CR_CIRCULAR | CR_RS)
        self.m.write(S2MM_VSIZE, self.vsize)
        self.m.write(S2MM_SR, self.m.read(S2MM_SR))

    def stop(self):
        self.m.write(S2MM_CR, 0)

    def running(self):
        return not bool(self.m.read(S2MM_SR) & SR_HALTED)

    def writer_slot(self):
        """Return the VDMA frame store currently being written."""
        # PG020 PARK_PTR_REG WrFrmStore (active S2MM frame) occupies bits [28:24].
        return (self.m.read(PARK_PTR) >> 24) & 0x1F

    def completed_slot(self):
        writer = self.writer_slot()
        if writer >= len(self.addrs):
            raise RuntimeError("invalid VDMA writer slot %d" % writer)
        return (writer - 1) % len(self.addrs), writer

    def status(self):
        return self.m.read(S2MM_SR)
