from pathlib import Path
import sys
sys.path.insert(0,'/mnt/d/distortion_correction/success_five/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files')
from camremap.main import validate_hardware_contract,validate_snapshot_layout,TX_CAMERA,TX_CAPTURE_OFFSETS
validate_snapshot_layout()
h='/mnt/d/distortion_correction/success_five/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.hwh'
print(validate_hardware_contract(h))
assert TX_CAMERA==2 and TX_CAPTURE_OFFSETS==[0x400000,0x400000+1152000,0x400000+2*1152000]
print('TX_CAMERA',TX_CAMERA,'TX_CAPTURE_OFFSETS',[hex(x) for x in TX_CAPTURE_OFFSETS])
