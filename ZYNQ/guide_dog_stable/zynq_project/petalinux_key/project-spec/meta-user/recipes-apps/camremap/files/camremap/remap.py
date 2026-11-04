"""Runtime contract for the single PL Q10.6 remap accelerator.
Checksums bind deployed files to a manifest; they are not authentication.
"""
import hashlib
import json
import math
import struct
import time
import zlib

MAGIC = b"RMP2"
VERSION = 1
HEADER_BYTES = 96
INVALID = 0xFFFF
WIDTH = 800
HEIGHT = 480
FRAME_BYTES = 1152000
FRAC_BITS = 6
VALID_STEPS = (8, 16)
LUT_RESERVED = 0x8000

AP_CTRL = 0x00
SRC_LO = 0x10
SRC_HI = 0x14
LUT_LO = 0x1C
LUT_HI = 0x20
DST_LO = 0x28
DST_HI = 0x2C
STEP_REG = 0x34
STATUS_REG = 0x40
INVALID_REG = 0x50
CACHE_MISS_REG = 0x60
PIXEL_COUNT_REG = 0x70
CRC_REG = 0x80
GUARD_ID = 0x00
GUARD_EXPECTED_ID = 0x524D5032
GUARD_ABI = 0x1C
GUARD_EXPECTED_ABI = 1
GUARD_FLAGS = 0x04
GUARD_CLEAR = 0x14

class RemapError(RuntimeError):
    pass

class RemapFatalError(RemapError):
    """The accelerator may remain active: stop service and reconfigure PL."""
    pass

def _digest(value, label):
    try:
        if not isinstance(value, str) or len(value) != 64:
            raise ValueError()
        result = bytes.fromhex(value)
        if len(result) != 32 or not any(result):
            raise ValueError()
        return result
    except ValueError as exc:
        raise RemapError("invalid manifest %s SHA256" % label) from exc

def _overlap(a, size_a, b, size_b):
    return a < b + size_b and b < a + size_a

class PlRemap:
    def __init__(self, mmio, region, lut_offsets, guard=None, timeout=0.25,
                 allow_synthetic=False, verify_crc=False, lut_reserved=LUT_RESERVED,
                 manifest_path=None):
        self.m, self.region, self.guard = mmio, region, guard
        self.lut_offsets = tuple(int(x) for x in lut_offsets)
        self.lut_reserved = int(lut_reserved)
        self.timeout = float(timeout)
        self.allow_synthetic = bool(allow_synthetic)
        self.verify_crc = bool(verify_crc)
        self.luts = {}
        self.poisoned = False
        if not math.isfinite(self.timeout) or self.timeout <= 0:
            raise ValueError("remap timeout must be finite and positive")
        if len(self.lut_offsets) != 2:
            raise ValueError("PL remap requires exactly two LUT offsets")
        if self.lut_reserved < 24648 or self.lut_reserved % 8:
            raise ValueError("LUT allocation must cover padded step8 payload and be 8-byte aligned")
        for offset in self.lut_offsets:
            if offset < 0 or offset % 8 or offset + self.lut_reserved > region.size:
                raise ValueError("LUT allocation is unaligned or outside reserved DDR")
        if _overlap(self.lut_offsets[0], self.lut_reserved, self.lut_offsets[1], self.lut_reserved):
            raise ValueError("left/right LUT allocations overlap")
        if not manifest_path:
            raise RemapError("remap_manifest.json is required to bind the two LUT files")
        try:
            with open(manifest_path, encoding="utf-8-sig") as f:
                manifest = json.load(f)
            if (manifest["schema"], manifest["format"], manifest["width"],
                manifest["height"], manifest["frac_bits"]) != (
                    "pl-remap-manifest-v1", "RMP2-v1", WIDTH, HEIGHT, FRAC_BITS):
                raise ValueError("manifest schema/geometry mismatch")
            if type(manifest["step"]) is not int or manifest["step"] not in VALID_STEPS:
                raise ValueError("manifest step must be 8 or 16")
            if type(manifest["calibration_valid"]) is not bool:
                raise ValueError("manifest calibration_valid must be boolean")
            self.config_hash = _digest(manifest["calibration_config_sha256"], "config")
            for name in ("left", "right"):
                _digest(manifest["eyes"][name]["file_sha256"], name + " file")
                _digest(manifest["eyes"][name]["sha256"], name + " payload")
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise RemapError("invalid remap manifest: %s" % exc) from exc
        self.manifest = manifest
        if not manifest["calibration_valid"] and not self.allow_synthetic:
            raise RemapError("LUT calibration_valid=false; pass --allow-synthetic-lut only for smoke tests")

    @staticmethod
    def _geometry(step):
        if step not in VALID_STEPS:
            raise RemapError("unsupported LUT step %d" % step)
        cols, rows = WIDTH // step + 1, HEIGHT // step + 1
        return cols, rows, cols * rows * 4

    def _check_blob(self, blob, expected_eye):
        if len(blob) < HEADER_BYTES or blob[:4] != MAGIC:
            raise RemapError("bad LUT magic or truncated header")
        fields = struct.unpack_from("<HHHHHHHHHHIII", blob, 4)
        version, header, width, height, step, frac, eye, flags, cols, rows, nodes, payload_len, payload_crc = fields
        ec, er, ep = self._geometry(step)
        expected = (VERSION, HEADER_BYTES, WIDTH, HEIGHT, FRAC_BITS, expected_eye, ec, er, ec * er, ep)
        actual = (version, header, width, height, frac, eye, cols, rows, nodes, payload_len)
        if actual != expected:
            raise RemapError("LUT geometry/version/eye contract mismatch")
        if len(blob) != HEADER_BYTES + payload_len:
            raise RemapError("LUT size mismatch")
        if flags & ~1 or bool(flags & 1) != self.manifest["calibration_valid"]:
            raise RemapError("LUT flags do not match manifest")
        if step != self.manifest["step"] or blob[72:96] != self.config_hash[:24]:
            raise RemapError("LUT step/config hash does not match manifest")
        if zlib.crc32(blob[:36]) & 0xffffffff != struct.unpack_from("<I", blob, 36)[0]:
            raise RemapError("LUT header CRC mismatch")
        payload = blob[HEADER_BYTES:]
        if zlib.crc32(payload) & 0xffffffff != payload_crc:
            raise RemapError("LUT payload CRC mismatch")
        if hashlib.sha256(payload).digest() != blob[40:72]:
            raise RemapError("LUT payload SHA256 mismatch")
        record = self.manifest["eyes"]["left" if expected_eye == 1 else "right"]
        if (record.get("grid_cols"), record.get("grid_rows"), record.get("node_count"), record.get("payload_bytes")) != (ec, er, ec * er, ep):
            raise RemapError("LUT manifest eye geometry mismatch")
        if hashlib.sha256(blob).digest() != _digest(record["file_sha256"], "file"):
            raise RemapError("LUT full file SHA256 does not match manifest")
        if blob[40:72] != _digest(record["sha256"], "payload"):
            raise RemapError("LUT payload SHA256 does not match manifest")
        return {"payload": payload, "step": step, "flags": flags, "config_hash": blob[72:96], "sha256": blob[40:72]}

    def upload_lut(self, path, eye):
        if self.poisoned:
            raise RemapFatalError("remap is fault-latched; reconfigure PL before reuse")
        if eye not in (1, 2):
            raise ValueError("eye must be 1 or 2")
        with open(path, "rb") as f:
            blob = f.read()
        meta = self._check_blob(blob, eye)
        off, payload = self.lut_offsets[eye - 1], meta["payload"]
        padded = (len(payload) + 7) & ~7
        if padded > self.lut_reserved:
            raise RemapError("LUT exceeds reserved DDR allocation")
        self.region.u8[off:off + self.lut_reserved] = 0
        # memoryview assigns individual uint8 values to a NumPy u8 slice.
        self.region.u8[off:off + len(payload)] = memoryview(payload)
        if bytes(self.region.u8[off:off + padded]) != payload + bytes(padded - len(payload)):
            raise RemapError("LUT DDR upload read-back mismatch")
        meta["path"] = str(path)
        self.luts[eye] = meta
        return len(payload)

    def validate_pair(self):
        if set(self.luts) != {1, 2}:
            raise RemapError("both left and right LUTs are required")
        left, right = self.luts[1], self.luts[2]
        if left["step"] != right["step"] or left["config_hash"] != right["config_hash"]:
            raise RemapError("left/right LUT geometry or calibration hash mismatch")
        return left["step"]

    def _write_ptr(self, lo, hi, value):
        value = int(value)
        if value < 0 or value > 0xffffffff or value & 7:
            raise ValueError("remap DDR pointers must be aligned 32-bit Zynq physical addresses")
        self.m.write(lo, value & 0xffffffff)
        self.m.write(hi, 0)

    def _frame_offset(self, address):
        address = int(address)
        offset = address - self.region.pa(0)
        if address < 0 or address > 0xffffffff or address % 8 or offset < 0 or offset + FRAME_BYTES > self.region.size:
            raise ValueError("remap frame outside reserved DDR or unaligned")
        for lut in self.lut_offsets:
            if _overlap(offset, FRAME_BYTES, lut, self.lut_reserved):
                raise ValueError("remap frame overlaps LUT allocation")
        return offset

    def _fatal(self, message):
        self.poisoned = True
        raise RemapFatalError(message)

    def process(self, src_pa, eye, dst_pa):
        if self.poisoned:
            raise RemapFatalError("remap is fault-latched; reconfigure PL before reuse")
        if eye not in (1, 2):
            raise ValueError("eye must be 1 or 2")
        self.validate_pair()
        src_off, dst_off = self._frame_offset(src_pa), self._frame_offset(dst_pa)
        if _overlap(src_off, FRAME_BYTES, dst_off, FRAME_BYTES):
            raise ValueError("remap source and destination must not overlap")
        if self.guard is None:
            self._fatal("PL remap requires the AXI response guard")
        if (self.guard.read(GUARD_ID) != GUARD_EXPECTED_ID or
                self.guard.read(GUARD_ABI) != GUARD_EXPECTED_ABI):
            self._fatal('PL remap guard identity/ABI mismatch; verify bit/HWH pair')
        # Never clear an unhandled fault or overwrite an active command.
        if self.guard.read(GUARD_FLAGS) & 0x3:
            self._fatal("PL remap guard reports a prior AXI response fault")
        if not self.m.read(AP_CTRL) & 0x4:
            self._fatal("PL remap is not idle before start")
        self._write_ptr(SRC_LO, SRC_HI, src_pa)
        self._write_ptr(LUT_LO, LUT_HI, self.region.pa(self.lut_offsets[eye - 1]))
        self._write_ptr(DST_LO, DST_HI, dst_pa)
        self.m.write(STEP_REG, self.luts[eye]["step"])
        self.guard.write(GUARD_CLEAR, 0x3)
        self.m.write(AP_CTRL, 1)
        deadline = time.monotonic() + self.timeout
        while True:
            ctrl = self.m.read(AP_CTRL)
            guard_flags = self.guard.read(GUARD_FLAGS)
            if guard_flags & 0x3:
                self._fatal("PL remap AXI response fault, guard=0x%08X" % guard_flags)
            if ctrl & 0x2:
                code = self.m.read(STATUS_REG)
                if code:
                    self._fatal("PL remap error status=0x%08X" % code)
                result = {"ctrl": ctrl, "status": code, "invalid": self.m.read(INVALID_REG), "cache_miss": self.m.read(CACHE_MISS_REG), "pixels": self.m.read(PIXEL_COUNT_REG), "crc": self.m.read(CRC_REG)}
                if result["pixels"] != WIDTH * HEIGHT or result["invalid"] > WIDTH * HEIGHT:
                    self._fatal("PL remap incomplete/invalid pixel count")
                if self.verify_crc:
                    # Zero is a legal CRC. Compare all output bytes, not nonzero-ness.
                    actual_crc = zlib.crc32(memoryview(self.region.u8[dst_off:dst_off + FRAME_BYTES])) & 0xffffffff
                    if actual_crc != result["crc"]:
                        self._fatal("PL remap output CRC mismatch: CPU=%08X PL=%08X" % (actual_crc, result["crc"]))
                return result
            if time.monotonic() >= deadline:
                self._fatal("PL remap timeout, AP_CTRL=0x%08X; reconfigure PL" % ctrl)
            time.sleep(0.0005)
