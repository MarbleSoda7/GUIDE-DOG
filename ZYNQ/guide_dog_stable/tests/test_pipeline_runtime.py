"""Host-only ordering/failure tests; no /dev/mem and no PL build."""
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files"
sys.path.insert(0, str(RUNTIME))
from camremap import main as m
from camremap import eth, vdma


class PipelineTest(unittest.TestCase):
    def pipeline(self):
        p = m.Pipeline.__new__(m.Pipeline)
        p.args = m.parse_args(["--frames", "1"])
        p._pair_id = 0
        p._last_udp_done = 0
        p._frames_dropped = p._pair_rejected = 0
        p.mem = SimpleNamespace(pa=lambda x: m.RES_BASE + x)
        p.vdma = Mock()
        p.vdma2 = Mock()
        p.dma = Mock()
        p.eth = Mock()
        p.dma.wait.return_value = 0.01
        p.eth.wait_udp_done.side_effect = [827, 1654]
        p.streams = [dict(camera_id=i, dst=d, corrected=c) for i, d, c in
                     [(1, m.OFF_OUT, m.OFF_CORRECTED1), (2, m.OFF_SNAPSHOT, m.OFF_CORRECTED2)]]
        p.snapshot_pair = Mock(return_value=[(s, 0, 1, 0, 0) for s in p.streams])
        p.check_capture_status = Mock()
        p.remap = Mock()
        p.setup = Mock()
        return p

    def test_defaults_and_layout(self):
        a = m.parse_args([])
        self.assertEqual(a.rectify, "off")
        self.assertFalse(a.allow_synthetic_lut)
        self.assertFalse(a.verify_remap_crc)
        self.assertEqual(a.lut_manifest, "remap_manifest.json")
        self.assertEqual((m.OFF_LUT1, m.OFF_LUT2, m.LUT_RESERVED), (0xA40000, 0xA60000, 0x8000))
        m.validate_snapshot_layout()
        with patch.object(m, "OFF_LUT2", m.OFF_LUT1 + 8):
            with self.assertRaisesRegex(RuntimeError, "overlap"):
                m.validate_snapshot_layout()
        with patch.object(m, "OFF_CORRECTED2", m.OFF_CORRECTED2 + 1):
            with self.assertRaisesRegex(RuntimeError, "alignment"):
                m.validate_snapshot_layout()

    def test_snapshot_and_both_remaps_before_any_tx(self):
        p = self.pipeline()
        events = Mock()
        for name, fn in [("snapshot", p.snapshot_pair), ("remap", p.remap.process),
                         ("metadata", p.eth.set_frame_meta), ("send", p.dma.send),
                         ("dma_done", p.dma.wait), ("udp_done", p.eth.wait_udp_done)]:
            events.attach_mock(fn, name)
        p.one_pair()
        self.assertEqual([c[0] for c in events.mock_calls],
                         ["snapshot", "remap", "remap", "metadata", "send", "dma_done", "udp_done",
                          "metadata", "send", "dma_done", "udp_done"])
        self.assertEqual([c.args[0] for c in p.eth.wait_udp_done.call_args_list], [0, 827])

    def test_either_remap_failure_never_transmits(self):
        for eye in (1, 2):
            p = self.pipeline()
            p.remap.process.side_effect = [m.RemapError("fault")] if eye == 1 else [{}, m.RemapError("fault")]
            with self.assertRaises(m.RemapError):
                p.one_pair()
            p.eth.set_frame_meta.assert_not_called()
            p.dma.send.assert_not_called()

    def test_snapshot_failure_never_remaps_or_transmits(self):
        p = self.pipeline()
        p.snapshot_pair.side_effect = TimeoutError("second eye not halted")
        with self.assertRaises(TimeoutError):
            p.one_pair()
        p.remap.process.assert_not_called()
        p.eth.set_frame_meta.assert_not_called()
        p.dma.send.assert_not_called()

    def test_udp_failure_blocks_second_metadata(self):
        p = self.pipeline()
        p.eth.wait_udp_done.side_effect = TimeoutError("tail stuck")
        with self.assertRaises(m.TxFatalError):
            p.one_pair()
        self.assertEqual(p.eth.set_frame_meta.call_count, 1)
        self.assertEqual(p.dma.send.call_count, 1)

    def test_fatal_errors_exit_without_retry(self):
        for error, code in [(m.RemapError("core may write"), 2), (m.TxFatalError("tail stuck"), 3)]:
            p = self.pipeline()
            p.one_pair = Mock(side_effect=error)
            with patch.object(m.time, "sleep"), patch.object(m, "log"):
                with self.assertRaises(SystemExit) as e:
                    p.run()
            self.assertEqual(e.exception.code, code)
            p.one_pair.assert_called_once()
            p.vdma.start.assert_not_called()
            p.vdma2.start.assert_not_called()
            p.dma.start.assert_not_called()

    def test_snapshot_halts_both_before_copy_then_resumes(self):
        p = self.pipeline()
        del p.snapshot_pair
        order = []
        class Bytes:
            def __getitem__(self, key):
                order.append("read")
                return b"frame"
            def __setitem__(self, key, value):
                order.append("copy")
        p.mem.u8 = Bytes()
        for s, device in zip(p.streams, (p.vdma, p.vdma2)):
            s.update(vdma=device, capture_pa=[0, 8, 16], offsets=[0, 8, 16])
            device.graceful_stop.side_effect = lambda **kw: order.append("halt")
            device.status.return_value = vdma.SR_HALTED
            device.completed_slot.return_value = (0, 1)
            device.resume.side_effect = lambda: order.append("resume")
        p.warmup_after_resume = Mock(side_effect=lambda: order.append("warmup"))
        p.snapshot_pair()
        self.assertEqual(order, ["halt", "halt", "read", "copy", "read", "copy", "resume", "resume", "warmup"])
        order.clear()
        p.vdma2.graceful_stop.side_effect = TimeoutError("no halt")
        with self.assertRaises(TimeoutError):
            p.snapshot_pair()
        self.assertNotIn("copy", order)


class ResumeWarmupTest(unittest.TestCase):
    def pipeline(self):
        p = m.Pipeline.__new__(m.Pipeline)
        p.check_capture_status = Mock()
        p.streams = [dict(camera_id=i, capture_pa=[0, 8, 16], vdma=Mock()) for i in (1, 2)]
        return p

    def test_waits_three_transitions_for_each_eye(self):
        p = self.pipeline()
        p.streams[0]['vdma'].writer_slot.side_effect = [0, 1, 2, 0, 0, 0]
        p.streams[1]['vdma'].writer_slot.side_effect = [0, 0, 1, 1, 2, 0]
        with patch.object(m.time, 'sleep') as sleep, patch.object(m.time, 'monotonic', return_value=0):
            p.warmup_after_resume()
        self.assertEqual(p.check_capture_status.call_count, 5)
        self.assertEqual(sleep.call_count, 5)
        for stream in p.streams:
            self.assertEqual(stream['vdma'].writer_slot.call_count, 6)

    def test_no_rotation_times_out(self):
        p = self.pipeline()
        for stream in p.streams:
            stream['vdma'].writer_slot.return_value = 0
        with patch.object(m.time, 'sleep'), patch.object(m.time, 'monotonic', side_effect=[0, 0, 2.1]):
            with self.assertRaisesRegex(TimeoutError, 'post-resume rotation'):
                p.warmup_after_resume()

    def test_invalid_resumed_writer_is_rejected(self):
        p = self.pipeline()
        p.streams[0]['vdma'].writer_slot.side_effect = [0, 3]
        p.streams[1]['vdma'].writer_slot.return_value = 0
        with self.assertRaisesRegex(RuntimeError, 'invalid camera1 resumed writer'):
            p.warmup_after_resume()


class UdpAndVdmaTest(unittest.TestCase):
    def test_udp_requires_all_packets_stable_idle_and_handles_wrap(self):
        samples = iter([1, 826, 827, 826, 827, 827, 827])
        current = 0
        reads = 0
        def read(reg):
            nonlocal current, reads
            if reg == eth.DBG_UDP_DONE:
                if reads % 2 == 0:
                    current = next(samples)
                reads += 1
                return (0xFFFFFFF0 + current) & 0xFFFFFFFF
            if reg == eth.DBG_IN_LAST:
                return 2
            return 0
        mmio = Mock(read=read)
        with patch.object(eth.time, "sleep"):
            self.assertEqual(eth.EthStream(mmio).wait_udp_done(0xFFFFFFF0), (0xFFFFFFF0 + 827) & 0xFFFFFFFF)
        self.assertEqual(reads, 14)

    def test_udp_busy_or_incomplete_times_out(self):
        for completed, live in [(1, 2), (826, 2), (827, 0x102)]:
            mmio = Mock()
            mmio.read.side_effect = lambda reg: completed if reg == eth.DBG_UDP_DONE else live if reg == eth.DBG_IN_LAST else 0
            with patch.object(eth.time, "monotonic", side_effect=[0, 0, 3]), patch.object(eth.time, "sleep"):
                with self.assertRaises(TimeoutError):
                    eth.EthStream(mmio).wait_udp_done(0)

    def test_vdma_waits_halted_and_times_out(self):
        mmio = Mock()
        mmio.read.side_effect = [0, 0, vdma.SR_HALTED, vdma.SR_HALTED]
        v = vdma.VdmaS2mm(mmio, [0, 8, 16])
        with patch.object(vdma.time, "sleep"):
            self.assertEqual(v.graceful_stop(), vdma.SR_HALTED)
        mmio.write.assert_called_once_with(vdma.S2MM_CR, vdma.CR_CIRCULAR)
        mmio.read.side_effect = None
        mmio.read.return_value = 0
        with patch.object(vdma.time, "monotonic", side_effect=[0, 1]):
            with self.assertRaises(TimeoutError):
                v.graceful_stop()


if __name__ == "__main__":
    unittest.main()
