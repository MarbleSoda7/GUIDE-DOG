import pathlib
import re
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_pl_rectify


class BuildPlRectifyTests(unittest.TestCase):
    def test_default_powershell_forwards_checker_argument(self):
        ps = (ROOT / 'BUILD_PL_RECTIFY.ps1').read_text(encoding='utf-8')
        self.assertIn('[string[]]$ArgumentList', ps)
        self.assertIn('Invoke-Checked -File $py.Source -ArgumentList @($Check)', ps)
        self.assertNotIn('[string[]]$Args', ps)
        self.assertNotIn('GuardSim', ps)

    def test_static_contract(self):
        self.assertEqual(build_pl_rectify.main(), 0)

    def test_forbidden_boundaries_do_not_match_copy_root_or_vlnv(self):
        self.assertIsNone(build_pl_rectify.forbidden_match("D:/latest_project_pl_rectify/file.v"))
        self.assertIsNone(build_pl_rectify.forbidden_match("xilinx.com:hls:pl_remap_accel:1.0"))
        self.assertIsNotNone(build_pl_rectify.forbidden_match("D:/latest_project/file.v"))
        self.assertIsNotNone(build_pl_rectify.forbidden_match("xilinx.com:hls:remap_accel:1.0"))

    def test_launcher_uses_canonical_same_round_outputs(self):
        launcher = (ROOT / "tools/launch_pl_rectify_build.tcl").read_text(encoding="utf-8")
        for token in (
            "led_test_wrapper.bit", "led_test_wrapper.hwh", "led_test_wrapper.xsa",
            "guide_linux_base.gen sources_1 bd led_test hw_handoff led_test.hwh",
            "open_run $impl",
        ):
            self.assertIn(token, launcher)
        self.assertNotIn("write_hwdef", launcher)

    def test_integration_is_not_a_build_launcher(self):
        integration = (ROOT / "zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/integrate_pl_remap.tcl").read_text(encoding="utf-8")
        self.assertNotRegex(integration, re.compile(r"(?i)\b(csynth_design|synth_design|launch_runs)\b"))


if __name__ == "__main__":
    unittest.main()

