from pathlib import Path
root=Path('/home/caitlyn/workdir/success_five')
changes={
 'project-spec/configs/config': [('CONFIG_SUBSYSTEM_HOSTNAME="success_third"','CONFIG_SUBSYSTEM_HOSTNAME="success_five"'),('CONFIG_SUBSYSTEM_PRODUCT="success_third"','CONFIG_SUBSYSTEM_PRODUCT="success_five"')],
 'build/conf/plnxtool.conf': [('hostname:pn-base-files = "success_third"','hostname:pn-base-files = "success_five"'),('PETALINUX_PRODUCT:pn-base-files-plnx = "success_third"','PETALINUX_PRODUCT:pn-base-files-plnx = "success_five"'),('/home/caitlyn/workdir/success_four/project-spec/configs/config:config /home/caitlyn/workdir/success_four/project-spec/hw-description/hardware.bit:system.bit','/home/caitlyn/workdir/success_five/project-spec/configs/config:config /home/caitlyn/workdir/success_five/project-spec/hw-description/hardware.bit:system.bit'),('SYSCONFIG_DIR = "/home/caitlyn/workdir/success_four/project-spec/configs"','SYSCONFIG_DIR = "/home/caitlyn/workdir/success_five/project-spec/configs"')],
 'build/conf/machine/zynq-generic-7z020.conf': [('HDF_PATH = "/home/caitlyn/workdir/success_four/project-spec/hw-description/system.xsa"','HDF_PATH = "/home/caitlyn/workdir/success_five/project-spec/hw-description/system.xsa"')]
}
for rel,pairs in changes.items():
 f=root/rel;s=f.read_text();
 for old,new in pairs:
  assert old in s,(rel,old);s=s.replace(old,new)
 f.write_text(s)
print('success_five project metadata paths and hostname updated')
