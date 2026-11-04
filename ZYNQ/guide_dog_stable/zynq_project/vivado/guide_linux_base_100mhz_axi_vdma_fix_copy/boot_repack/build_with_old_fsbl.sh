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
cat > boot_100mhz_v2.bif << 'EOF'
the_ROM_image:
{
  [bootloader] ./zynq_fsbl.elf
  ../guide_linux_base.runs/impl_1/led_test_wrapper.bit
  ./u-boot.elf
  [load=0x100000] ./system.dtb
}
EOF

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
  echo "=== 5. 复制到 Windows 目录 ==="
  mkdir -p /mnt/f/100mhz
  cp BOOT_100MHz.BIN /mnt/f/100mhz/BOOT.BIN
  cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/image.ub /mnt/f/100mhz/
  cp ~/workdir/plnx_prj_2024_1/camremap_plnx/images/linux/boot.scr /mnt/f/100mhz/
  
  echo ""
  echo "=== 6. 验证 SD 卡文件 ==="
  ls -lh /mnt/f/100mhz/
  
  echo ""
  echo "✅ 100MHz 版本已复制到 F:\100mhz\"
else
  echo "❌ BOOT.BIN 未生成"
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ 完成！"
echo "════════════════════════════════════════════════════════"
echo ""
echo "重要说明："
echo "  • 这个版本使用 50MHz 的 FSBL"
echo "  • 但包含了 100MHz 的比特流"
echo "  • 以及正确的 system.dtb"
echo ""
echo "理论分析："
echo "  1. FSBL 初始化 PS（DDR、MIO 等）"
echo "  2. FSBL 加载 100MHz 比特流到 PL"
echo "  3. 比特流配置 PL 的时钟为 100MHz"
echo "  4. U-Boot 使用 DTB 初始化设备"
echo ""
echo "可能的结果："
echo "  ✅ 成功启动 → PL 运行在 100MHz"
echo "  ❌ 启动失败 → 说明 PS7 配置确实不兼容"
echo ""
echo "下一步："
echo "  1. 安全弹出 SD 卡"
echo "  2. 将 F:\\100mhz\\ 下的文件复制到 SD 卡根目录"
echo "  3. 插入板子并上电测试"
