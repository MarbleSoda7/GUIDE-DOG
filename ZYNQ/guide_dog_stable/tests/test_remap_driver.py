"""Fast, hardware-free driver regressions. Run: python -B tests/test_remap_driver.py -v.
Only this test file is created; manifests/LUTs use in-memory open mocks.
Tests exercise the real driver and generator blob/config-hash helpers.
"""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
import unittest
from unittest import mock
import zlib

import numpy as np

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DRIVER_PATH = ROOT / 'zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/camremap/remap.py'
GENERATOR_PATH = ROOT / 'tools/generate_remap_lut.py'


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


driver = load_module('driver_under_test', DRIVER_PATH)
generator = load_module('generator_for_driver_test', GENERATOR_PATH)
BASE = 0x30000000
SIZE = 0x400000
SRC = 0
DST = 0x140000
LUTS = (0x300000, 0x308000)


class Region:
    def __init__(self):
        self.size = SIZE
        self.u8 = np.full(SIZE, 0xa5, dtype=np.uint8)

    def pa(self, offset):
        return BASE + offset


class MMIO:
    def __init__(self, timeline):
        self.timeline = timeline
        self.writes, self.reads = [], []
        self.started = False
        self.before_start = 4
        self.after_start = 2
        self.ctrl_queue = []
        self.regs = {driver.STATUS_REG: 0, driver.INVALID_REG: 17,
                     driver.CACHE_MISS_REG: 9000, driver.PIXEL_COUNT_REG: 384000,
                     driver.CRC_REG: 0}

    def write(self, offset, value):
        self.writes.append((offset, value))
        self.timeline.append(('mmio', offset, value))
        if offset == driver.AP_CTRL and value == 1:
            self.started = True

    def read(self, offset):
        self.reads.append(offset)
        if offset == driver.AP_CTRL:
            if not self.started:
                return self.before_start
            return self.ctrl_queue.pop(0) if self.ctrl_queue else self.after_start
        return self.regs.get(offset, 0)


class Guard:
    def __init__(self, mmio, timeline):
        self.mmio, self.timeline = mmio, timeline
        self.writes, self.reads = [], []
        self.prior_flags = 0
        self.running_flags = 0
        self.identity = driver.GUARD_EXPECTED_ID
        self.abi = driver.GUARD_EXPECTED_ABI

    def write(self, offset, value):
        self.writes.append((offset, value))
        self.timeline.append(('guard', offset, value))

    def read(self, offset):
        self.reads.append(offset)
        if offset == driver.GUARD_ID:
            return self.identity
        if offset == driver.GUARD_ABI:
            return self.abi
        if offset != driver.GUARD_FLAGS:
            raise AssertionError('unexpected guard register')
        return self.running_flags if self.mmio.started else self.prior_flags


def products(step, calibrated=True):
    config = {'width': 800, 'height': 480, 'grid_step': step, 'frac_bits': 6,
              'calibration_valid': calibrated, 'test_identity_lut': True}
    digest = generator.calibration_config_sha256(config)
    cols, rows = generator.geometry(800, 480, step, 6)
    payload = b''.join(struct.pack('<HH', x * 64, y * 64)
                       for y in generator.grid_axis(480, step)
                       for x in generator.grid_axis(800, step))
    manifest = {'schema': 'pl-remap-manifest-v1', 'format': 'RMP2-v1',
                'width': 800, 'height': 480, 'step': step, 'frac_bits': 6,
                'calibration_valid': calibrated,
                'calibration_config_sha256': digest.hex(), 'eyes': {}}
    files = {}
    for eye, name in ((1, 'left'), (2, 'right')):
        data = generator.blob(800, 480, step, 6, eye, cols, rows, payload, calibrated, digest)
        files[name + '.rmp'] = data
        manifest['eyes'][name] = {'file': name + '.rmp', 'grid_cols': cols,
                                 'grid_rows': rows, 'node_count': cols * rows,
                                 'payload_bytes': len(payload),
                                 'sha256': hashlib.sha256(payload).hexdigest(),
                                 'file_sha256': hashlib.sha256(data).hexdigest()}
    return manifest, files


class DriverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = {(step, flag): products(step, flag) for step in (8, 16) for flag in (True, False)}

    def setUp(self):
        self.region = Region()
        self.timeline = []
        self.mmio = MMIO(self.timeline)
        self.guard = Guard(self.mmio, self.timeline)
        self.manifest, self.files = copy.deepcopy(self.fixtures[(16, True)])
        self.open_patch = mock.patch.object(driver, 'open', side_effect=self.fake_open, create=True)
        self.open_patch.start()
        self.addCleanup(self.open_patch.stop)

    def fake_open(self, path, mode='r', **kwargs):
        name = str(path)
        if name == 'manifest.json':
            return io.StringIO(json.dumps(self.manifest))
        if name not in self.files:
            raise FileNotFoundError(name)
        if mode != 'rb':
            raise AssertionError('LUT must be opened binary')
        return io.BytesIO(self.files[name])

    def make_driver(self, **overrides):
        args = dict(mmio=self.mmio, region=self.region, lut_offsets=LUTS,
                    guard=self.guard, timeout=0.25, allow_synthetic=False,
                    verify_crc=False, lut_reserved=0x8000, manifest_path='manifest.json')
        args.update(overrides)
        return driver.PlRemap(**args)

    def ready(self, **kwargs):
        remap = self.make_driver(**kwargs)
        remap.upload_lut('left.rmp', 1)
        remap.upload_lut('right.rmp', 2)
        self.assertEqual(remap.validate_pair(), self.manifest['step'])
        return remap

    def assert_no_io(self):
        self.assertEqual(self.timeline, [])
        self.assertEqual(self.mmio.reads, [])
        self.assertEqual(self.guard.reads, [])

    def assert_poisoned(self, remap):
        self.assertTrue(remap.poisoned)
        before = (list(self.mmio.writes), list(self.guard.writes),
                  list(self.mmio.reads), list(self.guard.reads))
        ram_hash = hashlib.sha256(self.region.u8).digest()
        for _ in range(2):
            with self.assertRaisesRegex(driver.RemapFatalError, 'fault-latched'):
                remap.process(BASE + SRC, 1, BASE + DST)
        with self.assertRaisesRegex(driver.RemapFatalError, 'fault-latched'):
            remap.upload_lut('left.rmp', 1)
        self.assertEqual(before, (self.mmio.writes, self.guard.writes, self.mmio.reads, self.guard.reads))
        self.assertEqual(ram_hash, hashlib.sha256(self.region.u8).digest())

    def test_constructor_kwargs_and_no_mmio(self):
        remap = self.make_driver(timeout=0.125, verify_crc=True, lut_reserved=24648)
        self.assertIs(remap.m, self.mmio)
        self.assertIs(remap.region, self.region)
        self.assertIs(remap.guard, self.guard)
        self.assertEqual(remap.lut_offsets, LUTS)
        self.assertEqual(remap.lut_reserved, 24648)
        self.assertEqual(remap.timeout, 0.125)
        self.assertTrue(remap.verify_crc)
        self.assertFalse(remap.allow_synthetic)
        self.assertFalse(remap.poisoned)
        self.assert_no_io()

    def test_constructor_rejects_bad_allocations_and_timeouts(self):
        cases = [{'timeout': value} for value in (0, -1, float('inf'), float('nan'))]
        cases += [{'lut_offsets': value} for value in ((LUTS[0],), (LUTS[0], LUTS[0]),
                  (LUTS[0], LUTS[0] + 8), (-8, LUTS[1]), (LUTS[0] + 1, LUTS[1]),
                  (SIZE, LUTS[1]))]
        cases += [{'lut_reserved': value} for value in (0x2000, 24644, 24649)]
        for kwargs in cases:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                self.make_driver(**kwargs)
        with self.assertRaisesRegex(driver.RemapError, 'required'):
            self.make_driver(manifest_path=None)
        self.assert_no_io()

    def test_synthetic_requires_explicit_opt_in(self):
        self.manifest, self.files = copy.deepcopy(self.fixtures[(16, False)])
        with self.assertRaisesRegex(driver.RemapError, 'calibration_valid=false'):
            self.make_driver()
        remap = self.ready(allow_synthetic=True)
        self.assertTrue(remap.allow_synthetic)
        self.assert_no_io()

    def test_step8_and_step16_upload_padding_and_guard_bytes(self):
        for step, expected_len in ((8, 24644), (16, 6324)):
            with self.subTest(step=step):
                self.manifest, self.files = copy.deepcopy(self.fixtures[(step, True)])
                self.region.u8.fill(0xa5)
                remap = self.make_driver()
                for eye, name, offset in ((1, 'left', LUTS[0]), (2, 'right', LUTS[1])):
                    payload = self.files[name + '.rmp'][96:]
                    self.assertEqual(remap.upload_lut(name + '.rmp', eye), expected_len)
                    self.assertEqual(bytes(self.region.u8[offset:offset + expected_len]), payload)
                    self.assertEqual(bytes(self.region.u8[offset + expected_len:offset + expected_len + 4]), bytes(4))
                    self.assertTrue(np.all(self.region.u8[offset + expected_len:offset + 0x8000] == 0))
                self.assertEqual(remap.validate_pair(), step)
                self.assertEqual(int(self.region.u8[LUTS[0] - 1]), 0xa5)
                self.assertEqual(int(self.region.u8[LUTS[1] + 0x8000]), 0xa5)
                self.assertTrue(np.all(self.region.u8[:LUTS[0]] == 0xa5))
        self.assert_no_io()

    def test_manifest_config_payload_and_full_file_hash_binding(self):
        original_manifest, original_files = copy.deepcopy(self.fixtures[(16, True)])
        cases = ('config', 'payload_hash', 'file_hash', 'eye_geometry', 'step', 'flags', 'header_crc_corruption', 'payload_corruption')
        for case in cases:
            with self.subTest(case=case):
                self.manifest, self.files = copy.deepcopy((original_manifest, original_files))
                if case == 'config': self.manifest['calibration_config_sha256'] = '11' * 32
                if case == 'payload_hash': self.manifest['eyes']['left']['sha256'] = '22' * 32
                if case == 'file_hash': self.manifest['eyes']['left']['file_sha256'] = '33' * 32
                if case == 'eye_geometry': self.manifest['eyes']['left']['node_count'] += 1
                if case == 'step': self.manifest['step'] = 8
                if case == 'flags': self.manifest['calibration_valid'] = False
                if case in ('header_crc_corruption', 'payload_corruption'):
                    damaged = bytearray(self.files['left.rmp'])
                    damaged[39 if case == 'header_crc_corruption' else 100] ^= 1
                    self.files['left.rmp'] = bytes(damaged)
                remap = self.make_driver(allow_synthetic=True)
                before = hashlib.sha256(self.region.u8).digest()
                with self.assertRaises(driver.RemapError): remap.upload_lut('left.rmp', 1)
                self.assertEqual(remap.luts, {})
                self.assertEqual(before, hashlib.sha256(self.region.u8).digest())
        self.assert_no_io()

    def test_manifest_rejects_invalid_digest_and_missing_eye(self):
        for digest in ('00' * 32, 'z' * 64, 'abc', None):
            with self.subTest(digest=digest):
                self.manifest['calibration_config_sha256'] = digest
                with self.assertRaises(driver.RemapError): self.make_driver()
        self.manifest = copy.deepcopy(self.fixtures[(16, True)][0])
        del self.manifest['eyes']['right']
        with self.assertRaises(driver.RemapError): self.make_driver()
        self.assert_no_io()

    def test_missing_and_wrong_eye_rejected_without_register_io(self):
        remap = self.make_driver()
        for uploaded in (False, True):
            if uploaded: remap.upload_lut('left.rmp', 1)
            with self.assertRaisesRegex(driver.RemapError, 'both left and right'):
                remap.process(BASE + SRC, 1, BASE + DST)
        with self.assertRaises(driver.RemapError): remap.upload_lut('right.rmp', 1)
        with self.assertRaises(ValueError): remap.upload_lut('left.rmp', 0)
        with self.assertRaises(ValueError): remap.process(BASE + SRC, 3, BASE + DST)
        self.assertFalse(remap.poisoned)
        self.assert_no_io()

    def test_frame_overlap_and_bad_addresses_rejected_before_io(self):
        remap = self.ready()
        pairs = [(BASE, BASE), (BASE, BASE + 8),
                 (BASE, BASE + driver.FRAME_BYTES - 8),
                 (BASE + LUTS[0], BASE + DST), (BASE, BASE + LUTS[1]),
                 (BASE - 8, BASE + DST), (BASE + 1, BASE + DST),
                 (BASE, BASE + SIZE - driver.FRAME_BYTES + 8),
                 (0x100000000, BASE + DST), (BASE, BASE + DST + 1)]
        for src, dst in pairs:
            with self.subTest(src=src, dst=dst), self.assertRaises(ValueError):
                remap.process(src, 1, dst)
        self.assertFalse(remap.poisoned)
        self.assert_no_io()

    def test_done_pixel_count_crc_and_exact_register_sequence(self):
        for step in (8, 16):
            for eye in (1, 2):
                with self.subTest(step=step, eye=eye):
                    self.timeline.clear(); self.mmio.writes.clear(); self.guard.writes.clear()
                    self.mmio.started = False
                    self.manifest, self.files = copy.deepcopy(self.fixtures[(step, True)])
                    remap = self.ready(verify_crc=True)
                    self.region.u8[DST:DST + driver.FRAME_BYTES] = np.arange(driver.FRAME_BYTES, dtype=np.uint8)
                    crc = zlib.crc32(self.region.u8[DST:DST + driver.FRAME_BYTES]) & 0xffffffff
                    self.mmio.regs[driver.CRC_REG] = crc
                    result = remap.process(BASE + SRC, eye, BASE + DST)
                    self.assertEqual(result, {'ctrl': 2, 'status': 0, 'invalid': 17, 'cache_miss': 9000, 'pixels': 384000, 'crc': crc})
                    self.assertFalse(remap.poisoned)
                    expected = [(driver.SRC_LO, BASE + SRC), (driver.SRC_HI, 0),
                                (driver.LUT_LO, BASE + LUTS[eye - 1]), (driver.LUT_HI, 0),
                                (driver.DST_LO, BASE + DST), (driver.DST_HI, 0),
                                (driver.STEP_REG, step), (driver.AP_CTRL, 1)]
                    self.assertEqual(self.mmio.writes, expected)
                    self.assertEqual(self.guard.writes, [(driver.GUARD_CLEAR, 3)])
                    self.assertEqual(self.timeline[-2:], [('guard', driver.GUARD_CLEAR, 3), ('mmio', driver.AP_CTRL, 1)])

    def test_zero_crc_is_legal_when_cpu_matches(self):
        remap = self.ready(verify_crc=True)
        self.mmio.regs[driver.CRC_REG] = 0
        with mock.patch.object(driver.zlib, 'crc32', return_value=0) as crc_mock:
            result = remap.process(BASE + SRC, 1, BASE + DST)
            self.assertEqual(result['crc'], 0)
            self.assertEqual(crc_mock.call_count, 1)
            self.assertEqual(len(crc_mock.call_args.args[0]), driver.FRAME_BYTES)
        self.assertFalse(remap.poisoned)

    def test_guard_fault_after_start_latches(self):
        remap = self.ready()
        self.guard.running_flags = 2
        with self.assertRaisesRegex(driver.RemapFatalError, 'AXI response fault'):
            remap.process(BASE + SRC, 1, BASE + DST)
        self.assertTrue(self.mmio.started)
        self.assert_poisoned(remap)

    def test_prior_guard_fault_prevents_any_writes(self):
        remap = self.ready()
        self.guard.prior_flags = 1
        with self.assertRaisesRegex(driver.RemapFatalError, 'prior AXI'):
            remap.process(BASE + SRC, 1, BASE + DST)
        self.assertEqual(self.timeline, [])
        self.assert_poisoned(remap)

    def test_missing_guard_and_busy_core_fail_before_writes(self):
        for missing_guard in (True, False):
            with self.subTest(missing_guard=missing_guard):
                remap = self.ready(guard=None if missing_guard else self.guard)
                self.mmio.before_start = 0
                with self.assertRaises(driver.RemapFatalError):
                    remap.process(BASE + SRC, 1, BASE + DST)
                self.assertEqual(self.timeline, [])
                self.assert_poisoned(remap)

    def test_wrong_guard_identity_or_abi_prevents_commands(self):
        for attribute in ('identity', 'abi'):
            with self.subTest(attribute=attribute):
                self.guard.identity = driver.GUARD_EXPECTED_ID
                self.guard.abi = driver.GUARD_EXPECTED_ABI
                setattr(self.guard, attribute, 0)
                remap = self.ready()
                with self.assertRaisesRegex(driver.RemapFatalError, 'identity/ABI mismatch'):
                    remap.process(BASE + SRC, 1, BASE + DST)
                self.assertEqual(self.timeline, [])
                self.assertEqual(self.mmio.reads, [])
                self.assert_poisoned(remap)

    def test_nonzero_status_latches(self):
        remap = self.ready()
        self.mmio.regs[driver.STATUS_REG] = 1
        with self.assertRaisesRegex(driver.RemapFatalError, 'error status'):
            remap.process(BASE + SRC, 1, BASE + DST)
        self.assert_poisoned(remap)

    def test_timeout_latches_without_real_wait(self):
        remap = self.ready(timeout=0.1)
        self.mmio.after_start = 0
        with mock.patch.object(driver.time, 'monotonic', side_effect=[100.0, 100.05, 100.2]), mock.patch.object(driver.time, 'sleep') as sleep:
            with self.assertRaisesRegex(driver.RemapFatalError, 'timeout'):
                remap.process(BASE + SRC, 1, BASE + DST)
            sleep.assert_called_once_with(0.0005)
        self.assert_poisoned(remap)

    def test_bad_pixel_counters_and_crc_latch(self):
        for register, value, verify in ((driver.PIXEL_COUNT_REG, 383999, False),
                                         (driver.INVALID_REG, 384001, False),
                                         (driver.CRC_REG, 123, True)):
            with self.subTest(register=register):
                self.mmio.started = False
                self.mmio.regs.update({driver.PIXEL_COUNT_REG: 384000, driver.INVALID_REG: 17, driver.CRC_REG: 0})
                self.mmio.regs[register] = value
                remap = self.ready(verify_crc=verify)
                if verify:
                    self.assertNotEqual(zlib.crc32(self.region.u8[DST:DST + driver.FRAME_BYTES]) & 0xffffffff, value)
                with self.assertRaises(driver.RemapFatalError):
                    remap.process(BASE + SRC, 1, BASE + DST)
                self.assert_poisoned(remap)


if __name__ == '__main__':
    unittest.main()
