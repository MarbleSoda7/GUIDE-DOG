"""PYNQ-style hardware access: MMIO, physical buffer region, Overlay(.hwh)."""
import mmap
import os
import re

import numpy as np


def _map(base, length):
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    try:
        return mmap.mmap(fd, length, mmap.MAP_SHARED,
                         mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
    finally:
        os.close(fd)


class MMIO:
    """32-bit register window, same read/write API as pynq.MMIO."""

    def __init__(self, base, length=0x10000):
        self.base = int(base)
        self.length = int(length)
        self._mm = _map(self.base, self.length)
        self.array = np.frombuffer(self._mm, dtype=np.uint32)

    def read(self, offset=0):
        return int(self.array[offset >> 2])

    def write(self, offset, value):
        self.array[offset >> 2] = np.uint32(int(value) & 0xFFFFFFFF)


class PhysRegion:
    """Physically contiguous DDR window reserved in the device tree.

    Mapped with O_SYNC, which controls CPU mapping/cache attributes. This does
    not prove that a PL write has completed or establish frame ownership;
    callers still require VDMA and packetizer completion protocols.
    """

    def __init__(self, base, size):
        self.base = int(base)
        self.size = int(size)
        self._mm = _map(self.base, self.size)
        self.u8 = np.frombuffer(self._mm, dtype=np.uint8)

    def view(self, offset, nbytes, dtype=np.uint8):
        return self.u8[offset:offset + nbytes].view(dtype)

    def pa(self, offset):
        return self.base + int(offset)


class DevMemBus:
    """Real hardware bus. Tests inject a simulator with the same two methods."""

    def mmio(self, base, length=0x10000):
        return MMIO(base, length)

    def region(self, base, size):
        return PhysRegion(base, size)


_ATTR = re.compile(r'(\w+)="([^"]*)"')


def parse_hwh(path, master="M_AXI_GP0"):
    """Return {instance: {phys_addr, addr_range, vlnv}} from a Vivado .hwh."""
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    vlnv = {}
    for m in re.finditer(r"<MODULE\b[^>]*>", text):
        a = dict(_ATTR.findall(m.group(0)))
        if "INSTANCE" in a and "VLNV" in a:
            vlnv[a["INSTANCE"]] = a["VLNV"]
    ips = {}
    for m in re.finditer(r"<MEMRANGE\b[^>]*>", text):
        a = dict(_ATTR.findall(m.group(0)))
        if a.get("MASTERBUSINTERFACE") != master or "INSTANCE" not in a:
            continue
        lo = int(a["BASEVALUE"], 16)
        hi = int(a["HIGHVALUE"], 16)
        ips[a["INSTANCE"]] = {"phys_addr": lo, "addr_range": hi - lo + 1,
                              "vlnv": vlnv.get(a["INSTANCE"], "")}
    return ips


class Overlay:
    """Minimal pynq.Overlay equivalent.

    The bitstream is loaded by the FSBL at boot (BOOT.BIN), so this class only
    reads the .hwh and exposes every AXI-Lite IP as an MMIO attribute:
        ol = Overlay("led_test_wrapper.hwh"); ol.axi_vdma_0.read(0x34)
    """

    def __init__(self, hwh_path, bus=None):
        self.hwh_path = hwh_path
        self.ip_dict = parse_hwh(hwh_path)
        self._bus = bus or DevMemBus()
        self._cache = {}

    def __getattr__(self, name):
        ip = self.__dict__.get("ip_dict", {}).get(name)
        if ip is None:
            raise AttributeError(name)
        if name not in self._cache:
            self._cache[name] = self._bus.mmio(ip["phys_addr"], ip["addr_range"])
        return self._cache[name]

    def __dir__(self):
        return list(self.ip_dict) + ["ip_dict"]
