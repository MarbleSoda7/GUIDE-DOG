#!/bin/bash
# Run only after final Vivado build/timing acceptance; no SD writes here.
set -eo pipefail
project=/home/caitlyn/workdir/plnx_prj_2024_1/camremap_plnx_100mhz_axi_vdma_fix_copy
hardware=/mnt/d/distortion_correction/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy
source /home/caitlyn/petalinux/2024.1/settings.sh
cd "$project"
# Extract both files from the same final XSA, rather than stale standalone HWH.
python3 "$hardware/verify_artifacts.py" "$hardware/led_test_wrapper.xsa" --extract "$project/final-hw"
cp "$hardware/led_test_wrapper.xsa" "$project/final-hw/system.xsa"
petalinux-config --get-hw-description "$project/final-hw/system.xsa" --silentconfig
cp "$project/final-hw/led_test_wrapper.hwh" "$project/project-spec/meta-user/recipes-apps/camremap/files/data/led_test_wrapper.hwh"
cp "$project/final-hw/led_test_wrapper.bit" "$project/project-spec/hw-description/led_test_wrapper.bit"
# Fail if the generator selected original hardware inputs again.
python3 - <<'PY'
from pathlib import Path
project=Path.cwd()
old='/home/caitlyn/workdir/plnx_prj_2024_1/camremap_plnx_100mhz/'
for rel in ['build/conf/bblayers.conf','build/conf/machine/zynq-generic-7z020.conf']:
    assert old not in (project/rel).read_text(), rel
for line in (project/'build/conf/plnxtool.conf').read_text().splitlines():
    if any(x in line for x in ['HDF_PATH','EXTRA_FILESLIST','SYSCONFIG_DIR']):
        assert old not in line, line
assert 'CONFIG_SUBSYSTEM_COPY_TO_TFTPBOOT=y' not in (project/'project-spec/configs/config').read_text()
PY
petalinux-build
python3 "$hardware/verify_artifacts.py" "$hardware/led_test_wrapper.xsa" --project "$project"
petalinux-package --boot --fsbl images/linux/zynq_fsbl.elf --fpga images/linux/system.bit --u-boot images/linux/u-boot.elf --force
sha256sum images/linux/BOOT.BIN images/linux/image.ub images/linux/boot.scr images/linux/system.bit
