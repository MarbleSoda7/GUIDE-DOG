# ========================================================
# 修复发现的 3 个硬件问题
# 1. SCCB GPIO 位宽：64 → 2
# 2. DMA 传输长度：14 位(16KB) → 23 位(8MB)
# 3. 补充 CDC 约束
# ========================================================
set proj "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
open_project $proj
open_bd_design $bdfile

# === 1. 修复 PS EMIO GPIO 位宽（改为 2 位用于 SCCB）===
set_property -dict [list \
  CONFIG.PCW_GPIO_EMIO_GPIO_IO {2} \
  CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {2} \
] [get_bd_cells processing_system7_0]
puts "FIXED: PS EMIO GPIO 改为 2 位"

# === 2. 修复 AXI DMA 传输长度（改为 23 位，支持最大 8MB 传输）===
set_property -dict [list \
  CONFIG.c_sg_length_width {23} \
] [get_bd_cells axi_dma_udp_0]
puts "FIXED: AXI DMA 传输长度位宽改为 23"

# 保存并重新 validate
assign_bd_address
regenerate_bd_layout
set rc [catch {validate_bd_design} vmsg]
puts "VALIDATE_RC=$rc"
if {$rc} { 
  puts "VALIDATE_MSG=$vmsg"
  error $vmsg 
}
save_bd_design

# 重新生成 BD 输出（wrapper 会更新为 2-bit GPIO）
generate_target all [get_files *led_test.bd]
puts "BD_REGENERATED"

close_project
exit
