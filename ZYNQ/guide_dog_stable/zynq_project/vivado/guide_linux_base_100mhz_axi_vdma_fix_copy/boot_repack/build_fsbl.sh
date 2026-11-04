#!/bin/bash
set -e

cd /mnt/d/distortion_correction/vivado/guide_linux_base_100mhz/boot_repack

echo "=== 1. 清理旧文件 ==="
rm -rf workspace fsbl

echo ""
echo "=== 2. 使用 XSCT 生成 FSBL ==="
~/petalinux/2024.1/components/xsct/bin/xsct generate_fsbl_xsct.tcl

echo ""
echo "=== 3. 查找生成的 FSBL ==="
find . -name "*.elf" -type f

echo ""
echo "=== 4. 检查文件大小 ==="
if [ -f "fsbl/executable.elf" ]; then
  ls -lh fsbl/executable.elf
  echo "✅ FSBL 生成成功"
elif [ -f "workspace/fsbl/executable.elf" ]; then
  ls -lh workspace/fsbl/executable.elf
  echo "✅ FSBL 生成成功（在 workspace 中）"
else
  echo "❌ 未找到 FSBL"
  echo ""
  echo "目录结构："
  find . -type f | head -20
  exit 1
fi

echo ""
echo "=== 5. 复制 50MHz 的 U-Boot 和 DTB ==="
cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/u-boot.elf ./
cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/system.dtb ./
ls -lh u-boot.elf system.dtb

echo ""
echo "=== 6. 创建 BIF 配置文件 ==="
FSBL_PATH=""
if [ -f "fsbl/executable.elf" ]; then
  FSBL_PATH="fsbl/executable.elf"
elif [ -f "workspace/fsbl/executable.elf" ]; then
  FSBL_PATH="workspace/fsbl/executable.elf"
fi

cat > boot_100mhz.bif << EOF
the_ROM_image:
{
  [bootloader] $FSBL_PATH
  ../led_test_wrapper.bit
  ./u-boot.elf
  [load=0x100000] ./system.dtb
}
EOF

echo ""
cat boot_100mhz.bif

echo ""
echo "=== 7. 使用 bootgen 打包 BOOT.BIN ==="
source ~/petalinux/2024.1/settings.sh
bootgen -image boot_100mhz.bif -arch zynq -o BOOT.BIN -w

echo ""
echo "=== 8. 验证 BOOT.BIN ==="
if [ -f "BOOT.BIN" ]; then
  ls -lh BOOT.BIN
  sha256sum BOOT.BIN
  echo ""
  echo "✅ BOOT.BIN 生成成功"
else
  echo "❌ BOOT.BIN 未生成"
  exit 1
fi

echo ""
echo "完成！"
