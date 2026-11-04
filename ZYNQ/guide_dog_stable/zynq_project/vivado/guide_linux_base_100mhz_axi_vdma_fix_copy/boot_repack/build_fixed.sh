#!/bin/bash
set -e

cd /mnt/d/distortion_correction/vivado/guide_linux_base_100mhz/boot_repack

echo "=== 1. 复制 50MHz 的 FSBL、U-Boot 和 DTB ==="
cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/zynq_fsbl.elf ./
cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/u-boot.elf ./
cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/system.dtb ./

echo ""
ls -lh zynq_fsbl.elf u-boot.elf system.dtb

echo ""
echo "=== 2. 创建 BIF 文件（包含 DTB！）==="
cat > boot_100mhz_v2.bif << 'EOFBIF'
the_ROM_image:
{
  [bootloader] ./zynq_fsbl.elf
  ../guide_linux_base.runs/impl_1/led_test_wrapper.bit
  ./u-boot.elf
  [load=0x100000] ./system.dtb
}
EOFBIF

cat boot_100mhz_v2.bif

echo ""
echo "=== 3. 使用 bootgen 打包 BOOT.BIN ==="
source ~/petalinux/2024.1/settings.sh
bootgen -image boot_100mhz_v2.bif -arch zynq -o BOOT_100MHz.BIN -w

echo ""
echo "=== 4. 验证文件 ==="
if [ -f "BOOT_100MHz.BIN" ]; then
  ls -lh BOOT_100MHz.BIN
  echo ""
  echo "SHA256:"
  sha256sum BOOT_100MHz.BIN
  echo ""
  echo "✅ BOOT_100MHz.BIN 生成成功"
  
  echo ""
  echo "=== 5. 检查 SD 卡 ==="
  if [ -d "/mnt/f" ]; then
    echo "SD 卡已挂载在 /mnt/f"
    mkdir -p /mnt/f/100mhz
    cp BOOT_100MHz.BIN /mnt/f/100mhz/BOOT.BIN
    cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/image.ub /mnt/f/100mhz/ 2>/dev/null || echo "image.ub 已存在或复制失败"
    cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/boot.scr /mnt/f/100mhz/ 2>/dev/null || echo "boot.scr 已存在或复制失败"
    
    echo ""
    echo "=== 6. 验证 SD 卡文件 ==="
    ls -lh /mnt/f/100mhz/
    
    echo ""
    echo "✅ 100MHz 版本已复制到 F:/100mhz/"
  else
    echo "⚠️ SD 卡未检测到 /mnt/f"
    echo "文件已生成，请手动复制到 SD 卡"
  fi
else
  echo "❌ BOOT.BIN 未生成"
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ 完成！"
echo "════════════════════════════════════════════════════════"
