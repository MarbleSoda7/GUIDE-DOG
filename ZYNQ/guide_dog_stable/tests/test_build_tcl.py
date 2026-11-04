import pathlib
import tkinter
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class BuildTclTests(unittest.TestCase):
    def test_tcl_structure_and_roots(self):
        tcl = tkinter.Tcl()
        tcl.call('source', str(ROOT / 'tests/test_build_pl_rectify.tcl'))

    def test_direct_long_flow_is_denied(self):
        for relative in ('tools/launch_pl_rectify_build.tcl', 'zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/run_pl_remap_hls.tcl'):
            tcl = tkinter.Tcl()
            tcl.eval('unset -nocomplain ::env(PL_RECTIFY_BUILD)')
            with self.assertRaisesRegex(tkinter.TclError, 'Refusing'):
                tcl.call('source', str(ROOT / relative))

if __name__ == '__main__':
    unittest.main()
