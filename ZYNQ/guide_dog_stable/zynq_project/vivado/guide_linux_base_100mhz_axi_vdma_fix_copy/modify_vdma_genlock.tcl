# 修改 VDMA Genlock 配置脚本
# 目的：启用 Genlock 同步机制，防止读写冲突

puts "打开工程..."
open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr

puts "打开 Block Design..."
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}

puts "查找 VDMA IP..."
set vdma_cell [get_bd_cells -filter {VLNV =~ "*axi_vdma*"}]
puts "找到 VDMA: $vdma_cell"

puts ""
puts "修改 VDMA Genlock 配置..."
puts "  1. 启用内部 Genlock..."
set_property CONFIG.c_include_internal_genlock {1} $vdma_cell

puts "  2. 设置 S2MM Genlock 模式为 2 (Master)..."
set_property CONFIG.c_s2mm_genlock_mode {2} $vdma_cell

puts "  3. 设置 MM2S Genlock 模式为 3 (Slave)..."
set_property CONFIG.c_mm2s_genlock_mode {3} $vdma_cell

puts ""
puts "验证配置..."
puts "  c_include_internal_genlock = [get_property CONFIG.c_include_internal_genlock $vdma_cell]"
puts "  c_s2mm_genlock_mode = [get_property CONFIG.c_s2mm_genlock_mode $vdma_cell]"
puts "  c_mm2s_genlock_mode = [get_property CONFIG.c_mm2s_genlock_mode $vdma_cell]"
puts "  c_num_fstores = [get_property CONFIG.c_num_fstores $vdma_cell]"
puts "  c_s2mm_genlock_repeat_en = [get_property CONFIG.c_s2mm_genlock_repeat_en $vdma_cell]"
puts "  c_mm2s_genlock_repeat_en = [get_property CONFIG.c_mm2s_genlock_repeat_en $vdma_cell]"

puts ""
puts "验证并保存 BD..."
validate_bd_design
save_bd_design

puts ""
puts "重新生成输出产品..."
generate_target all [get_files D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd]

puts ""
puts "✅ VDMA Genlock 配置修改完成！"
puts ""
puts "关键改动："
puts "  - c_include_internal_genlock: 0 → 1"
puts "  - c_s2mm_genlock_mode: 0 → 2 (Master)"
puts "  - c_mm2s_genlock_mode: 0 → 3 (Slave)"
puts ""
puts "预期效果："
puts "  ✓ 防止 S2MM 和 MM2S 同时访问同一帧缓冲"
puts "  ✓ 消除画面撕裂"
puts "  ✓ LINES counter 稳定"
puts "  ✓ 无白屏和随机崩溃"
puts ""

close_project
exit
