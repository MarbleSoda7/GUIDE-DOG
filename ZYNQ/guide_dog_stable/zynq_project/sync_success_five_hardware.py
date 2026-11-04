from pathlib import Path
import zipfile, hashlib
p=Path('D:/distortion_correction/success_five')
z=zipfile.ZipFile(p/'hardware.xsa')
hwh=z.read('led_test.hwh'); bit=z.read('hardware.bit')
paths=[p/'petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.hwh',p/'vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/led_test_wrapper.hwh',p/'delivery/axis_rgb24_to_32_vdma32_fix_copy/led_test_wrapper.hwh']
for q in paths:q.write_bytes(hwh)
(p/'petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.bit').write_bytes(bit)
(p/'petalinux_key/project-spec/hw-description/system.xsa').write_bytes((p/'hardware.xsa').read_bytes())
print('HWH_SHA256',hashlib.sha256(hwh).hexdigest(),'BIT_SHA256',hashlib.sha256(bit).hexdigest())
