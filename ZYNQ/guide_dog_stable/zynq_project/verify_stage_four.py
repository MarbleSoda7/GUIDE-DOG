from pathlib import Path
import zipfile, xml.etree.ElementTree as ET, shutil, sys
p=Path('/mnt/d/distortion_correction/success_four')
z=zipfile.ZipFile(p/'hardware.xsa')
print('XSA contents:',z.namelist())
names=[n for n in z.namelist() if n == 'led_test.hwh']
assert len(names)==1,names
data=z.read(names[0]); root=ET.fromstring(data)
mods={m.get('INSTANCE'):m for m in root.iter('MODULE')}
for i in range(2):
 m=mods['axi_vdma_'+str(i)]; ps={e.get('NAME'):e.get('VALUE') for e in m.findall('./PARAMETERS/PARAMETER')}
 print(i,ps['C_S_AXIS_S2MM_TDATA_WIDTH'],ps['C_NUM_FSTORES'])
 assert int(ps['C_S_AXIS_S2MM_TDATA_WIDTH'],0)==32 and int(ps['C_NUM_FSTORES'],0)==3
 assert 'axis_rgb24_to_32_'+str(i) in mods
for dest in [p/'petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.hwh',Path('/home/caitlyn/workdir/success_four/project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.hwh')]:
 dest.write_bytes(data)
bit=[n for n in z.namelist() if n.endswith('.bit')];assert len(bit)==1
assert z.read(bit[0])==Path('/home/caitlyn/workdir/success_four/images/linux/system.bit').read_bytes()
sys.path.insert(0,str(p/'petalinux_key/project-spec/meta-user/recipes-apps/camremap/files'))
from camremap.main import validate_hardware_contract,validate_snapshot_layout
validate_snapshot_layout();print(validate_hardware_contract(str(dest)))
print('Hardware handoff staged and bitstream matches XSA')
