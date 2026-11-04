import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / 'zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy'
KERNEL = DIR / 'pl_remap_accel.cpp'
HOST = DIR / 'pl_remap_accel_host_test.cpp'

class KernelStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = KERNEL.read_text(encoding='utf-8')

    def test_explicit_axi_abi(self):
        offsets = {'src':'0x10', 'lut':'0x1c', 'dst':'0x28', 'step':'0x34',
                   'status':'0x40', 'invalid_count':'0x50', 'cache_miss_count':'0x60',
                   'pixel_count':'0x70', 'crc':'0x80'}
        for port, offset in offsets.items():
            self.assertIn('#pragma HLS INTERFACE s_axilite port='+port+' bundle=control offset='+offset, self.code)
        axi = [line for line in self.code.splitlines() if line.startswith('#pragma HLS INTERFACE m_axi ')]
        self.assertEqual(len(axi), 3)
        self.assertTrue(all('bundle=gmem ' in line for line in axi))
        self.assertIn('port=lut offset=slave bundle=gmem depth=3081', self.code)

    def test_runtime_register_agreement(self):
        import ast
        runtime=ROOT / 'zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/camremap/remap.py'
        constants={}
        for item in ast.parse(runtime.read_text(encoding='utf-8')).body:
            if isinstance(item, ast.Assign) and isinstance(item.value, ast.Constant):
                for target in item.targets:
                    if isinstance(target, ast.Name):
                        constants[target.id]=item.value.value
        expected={'SRC_LO':0x10,'SRC_HI':0x14,'LUT_LO':0x1c,'LUT_HI':0x20,
                  'DST_LO':0x28,'DST_HI':0x2c,'STEP_REG':0x34,'STATUS_REG':0x40,
                  'INVALID_REG':0x50,'CACHE_MISS_REG':0x60,'PIXEL_COUNT_REG':0x70,'CRC_REG':0x80}
        for name,value in expected.items():
            self.assertEqual(constants.get(name),value,name)
        self.assertGreaterEqual(constants.get('LUT_RESERVED',0),24648)

    def test_cache_and_memory_sites(self):
        self.assertIn('CACHE_LINES = 64, CACHE_LINE_BYTES = 128', self.code)
        self.assertIn('cache[slot][i] = src[base_word + i];', self.code)
        self.assertEqual(self.code.count('src['), 1)
        self.assertEqual(self.code.count('lut['), 1)
        self.assertEqual(self.code.count('dst['), 1)
        self.assertIn('dst[output_base + i] = row_words[i];', self.code)
        self.assertIn('valid[i] = false;', self.code)
        self.assertIn('MAX_LUT_NODES = 6161', self.code)
        self.assertIn('if (2 * i + 1 < count)', self.code)

    def test_boundary_cell_coverage(self):
        for step in (8,16):
            count=(800//step+1)*(480//step+1)
            self.assertLessEqual(count,6161)
            self.assertEqual((count+1)//2,3081 if step==8 else 791)
            for dim in (800,480):
                covered=[]
                for g in range(dim//step):
                    start=g*step
                    end=min(start+step,dim-1)
                    span=end-start
                    size=span+1 if g==dim//step-1 else span
                    self.assertGreater(span,0)
                    for d in range(size):
                        self.assertEqual((start*64*(span-d)+end*64*d)//span,(start+d)*64)
                        covered.append(start+d)
                self.assertEqual(covered,list(range(dim)))
                self.assertEqual(span,step-1)
        self.assertIn('const unsigned span_x = x1 - x0;',self.code)
        self.assertIn('const unsigned span_y = y1 - y0;',self.code)
        prefetch=self.code.index('const node_t a = nodes[i], b = nodes[i + 1];')
        self.assertLess(prefetch,self.code.index('for (unsigned dy = 0;'))
        # Horizontal numerators advance only by signed deltas inside the pixel loop.
        self.assertNotIn('grid_interp(',self.code)
        self.assertNotIn('/ span',self.code)
        for span in (8,16,7,15):
            self.assertIn('if (span == %d) return numerator / %du;' % (span,span),self.code)
        pixel_loop=self.code.index('for (unsigned dx = 0;')
        pixel_end=self.code.index('// Separate contiguous output loop',pixel_loop)
        pixel_code=self.code[pixel_loop:pixel_end]
        for name in ('sx_top','sx_bot','sy_top','sy_bot'):
            self.assertLess(self.code.index('int32_t '+name+'_num ='),pixel_loop)
            self.assertLess(self.code.index('const int32_t '+name+'_delta ='),pixel_loop)
            self.assertIn(name+'_num += '+name+'_delta;',pixel_code)
        self.assertNotIn('node_x(',pixel_code)
        self.assertNotIn('node_y(',pixel_code)
        self.assertIn('const unsigned top = divide_span((unsigned)top_num, span_x);',self.code)
        self.assertIn('const unsigned bot = divide_span((unsigned)bot_num, span_x);',self.code)
        self.assertIn('return divide_span(top * (span_y - dy) + bot * dy, span_y);',self.code)

    def test_host_and_crc_contract(self):
        self.assertIn('#ifdef PL_REMAP_HOST',self.code)
        self.assertIn('typedef uint64_t word_t;',self.code)
        self.assertIn('typedef ap_uint<64> word_t;',self.code)
        self.assertIn('0xedb88320u',self.code)
        self.assertIn('crc = running_crc ^ 0xffffffffu;',self.code)
        self.assertIn('step != 8 && step != 16',self.code)
        self.assertTrue(HOST.is_file())

    def test_host_reference(self):
        compiler=os.environ.get('CXX') or shutil.which('g++') or shutil.which('clang++')
        if not compiler:
            self.skipTest('No g++/clang++ on PATH; host source and README provided. Set CXX to run.')
        with tempfile.TemporaryDirectory(prefix='test_pl_kernel_') as tmp:
            exe=Path(tmp)/('test_pl_kernel.exe' if os.name=='nt' else 'test_pl_kernel')
            subprocess.run([compiler,'-std=c++14','-O2','-Wall','-Wextra','-Werror','-Wno-unknown-pragmas',str(HOST),'-o',str(exe)],check=True,timeout=60)
            run=subprocess.run([str(exe)],check=True,timeout=60,text=True,capture_output=True)
            self.assertIn('PASS: 16 full-frame references',run.stdout)
            print(run.stdout,end='')

if __name__ == '__main__':
    unittest.main()
