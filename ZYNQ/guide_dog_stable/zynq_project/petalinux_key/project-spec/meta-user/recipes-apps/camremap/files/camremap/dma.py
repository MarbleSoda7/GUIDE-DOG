"""AXI DMA MM2S, simple (direct register) mode, 23-bit length (PG021)."""
import time

MM2S_CR = 0x00
MM2S_SR = 0x04
MM2S_SA = 0x18
MM2S_LENGTH = 0x28

CR_RS = 1 << 0
CR_RESET = 1 << 2
SR_HALTED = 1 << 0
SR_IDLE = 1 << 1
SR_ERR = 0x70
SR_IOC = 1 << 12
SR_IRQ_ALL = 0x7000


class DmaMm2s:
    def __init__(self, mmio):
        self.m = mmio

    def start(self, timeout=1.0):
        self.m.write(MM2S_CR, CR_RESET)
        t0 = time.monotonic()
        while self.m.read(MM2S_CR) & CR_RESET:
            if time.monotonic() - t0 > timeout:
                raise TimeoutError("DMA reset timeout")
            time.sleep(0.001)
        self.m.write(MM2S_CR, CR_RS)
        while self.m.read(MM2S_SR) & SR_HALTED:
            if time.monotonic() - t0 > timeout:
                raise TimeoutError("DMA did not leave halted state")
            time.sleep(0.001)

    def send(self, pa, nbytes):
        if pa & 7:
            raise ValueError("MM2S source must be 8-byte aligned (no DRE)")
        self.m.write(MM2S_SR, SR_IRQ_ALL)
        self.m.write(MM2S_SA, pa & 0xFFFFFFFF)
        self.m.write(MM2S_LENGTH, int(nbytes))      # length write starts transfer

    def wait(self, timeout=1.0):
        t0 = time.monotonic()
        while True:
            s = self.m.read(MM2S_SR)
            if s & SR_ERR:
                raise RuntimeError("DMA error, MM2S_SR=0x%08X" % s)
            if s & (SR_IOC | SR_IDLE):
                return time.monotonic() - t0
            if time.monotonic() - t0 > timeout:
                raise TimeoutError("DMA timeout, MM2S_SR=0x%08X" % s)
            time.sleep(0.0005)

    def status(self):
        return self.m.read(MM2S_SR)
