import sys
sys.path.insert(0, '/home/caitlyn/workdir/plnx_prj_2024_1/camremap_plnx_100mhz_axi_vdma_fix_copy/project-spec/meta-user/recipes-apps/camremap/files/camremap')
from vdma import VdmaS2mm, PARK_PTR
class MMIO:
    def __init__(self, value): self.value=value
    def read(self, offset):
        assert offset == PARK_PTR
        return self.value
for writer in range(3):
    mm=MMIO(writer << 24)
    vd=VdmaS2mm(mm,[0x30000000,0x30119400,0x30232800])
    assert vd.writer_slot()==writer,(writer,vd.writer_slot())
    assert vd.completed_slot()==((writer-1)%3,writer)
print('PASS: PARK_PTR WrFrmStore bits[28:24] decode slots 0,1,2 and completed ring correctly')
