"""Verify final XSA pairing and Linux input isolation; never publish stale copies."""
import argparse, hashlib, json, pathlib, zipfile, xml.etree.ElementTree as ET

def digest(data): return hashlib.sha256(data).hexdigest()
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('xsa',type=pathlib.Path)
    ap.add_argument('--project',type=pathlib.Path)
    ap.add_argument('--extract',type=pathlib.Path)
    args=ap.parse_args()
    with zipfile.ZipFile(args.xsa) as z:
        # XSA can include subordinate block handoffs; select the top-level design.
        hwh=[n for n in z.namelist() if pathlib.PurePosixPath(n).name == 'led_test.hwh']
        bits=[n for n in z.namelist() if n.endswith('.bit')]
        assert len(hwh)==1 and len(bits)==1,(hwh,bits)
        hd=z.read(hwh[0]); bd=z.read(bits[0])
    root=ET.fromstring(hd)
    mods={m.get('INSTANCE'):m for m in root.iter('MODULE')}
    cv=mods['axis_rgb24_to_32_0']; vd=mods['axi_vdma_0']
    ports={p.get('NAME'):p for p in cv.findall('./PORTS/PORT')}
    assert cv.get('MODTYPE')=='axis_rgb24_to_32_node_diag'
    assert ports['aclk'].get('CLKFREQUENCY')=='100000000'
    for name,width in [('s_axis_tdata',24),('m_axis_tdata',32)]:
        assert int(ports[name].get('LEFT','0'))-int(ports[name].get('RIGHT','0'))+1==width
    vp={p.get('NAME'):p.get('VALUE') for p in vd.findall('./PARAMETERS/PARAMETER')}
    assert vp['C_S_AXIS_S2MM_TDATA_WIDTH']=='32'
    report={'xsa_sha256':digest(args.xsa.read_bytes()),'hwh_sha256':digest(hd),'bit_sha256':digest(bd),'entries':[hwh[0],bits[0]],'clock_hz':100000000,'stream_bits':32,'frame_bytes':1152000,'stride':2400}
    if args.project:
        project=args.project.resolve(); old='/home/caitlyn/workdir/plnx_prj_2024_1/camremap_plnx_100mhz/'
        for rel in ['build/conf/bblayers.conf','build/conf/machine/zynq-generic-7z020.conf']:
            assert old not in (project/rel).read_text(),rel
        conf=(project/'build/conf/plnxtool.conf').read_text()
        for line in conf.splitlines():
            if any(x in line for x in ['HDF_PATH','EXTRA_FILESLIST','SYSCONFIG_DIR']): assert old not in line,line
        assert (project/'project-spec/hw-description/system.xsa').read_bytes()==args.xsa.read_bytes(),'Linux XSA not paired'
        for rel in ['project-spec/hw-description/led_test_wrapper.bit','images/linux/system.bit']:
            assert (project/rel).read_bytes()==bd,'bit mismatch: '+rel
        packaged=project/'project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.hwh'
        assert packaged.read_bytes()==hd,'App HWH not from final XSA'
        report['linux_input_pairing']='pass'
    if args.extract:
        args.extract.mkdir(parents=True,exist_ok=True)
        (args.extract/'led_test_wrapper.hwh').write_bytes(hd)
        (args.extract/'led_test_wrapper.bit').write_bytes(bd)
        (args.extract/'pairing.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__': main()
