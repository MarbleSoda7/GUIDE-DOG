# ============================================================
# 采集链路接入 v2 (修正版)
# 修正: v_vid_in_axi4s:5.0 (2024.1实际版本) + vid_io_in_reset (正确引脚名)
#        + axis_enable 常量 + PS EMIO GPIO 接 SCCB (照抄 guide_dog)
# ============================================================
set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
open_project $proj
open_bd_design $bdfile

# 1. PS 开启 EMIO GPIO 2位, 给 OV5640 SCCB (照抄 guide_dog)
set_property -dict [list \
  CONFIG.PCW_EN_EMIO_GPIO {1} \
  CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
  CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {2} \
] [get_bd_cells processing_system7_0]

# 2. OV5640 采集 IP (ip_repo 已有, 照抄 guide_dog)
create_bd_cell -type ip -vlnv xilinx.com:user:ov5640_to_lcd:1.0 ov5640_to_lcd_0

# 3. 视频桥 5.0 + 异步跨时钟 (摄像头PCLK域 -> FCLK域)
create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:5.0 v_vid_in_axi4s_0
set_property -dict [list CONFIG.C_HAS_ASYNC_CLK {1}] [get_bd_cells v_vid_in_axi4s_0]

# 4. axis_enable 常量
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_axis_en
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_axis_en]

# 5. VDMA S2MM only, 3 fstores (照抄 guide_dog)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0
set_property -dict [list \
  CONFIG.c_include_mm2s {0} CONFIG.c_include_s2mm {1} \
  CONFIG.c_num_fstores {3} CONFIG.c_s2mm_genlock_mode {0} \
  CONFIG.c_include_internal_genlock {0} \
  CONFIG.c_s2mm_linebuffer_depth {2048} \
  CONFIG.c_s2mm_max_burst_length {64} \
] [get_bd_cells axi_vdma_0]

# 6. HP SmartConnect 扩到 5 路 SI (照 guide_dog axi_smc 汇流先例)
set_property CONFIG.NUM_SI {5} [get_bd_cells remap_hp_smc]

# 7. 采集IP -> 视频桥 (摄像头PCLK域)
connect_bd_net [get_bd_pins ov5640_to_lcd_0/tft_clk]  [get_bd_pins v_vid_in_axi4s_0/vid_io_in_clk]
connect_bd_net [get_bd_pins ov5640_to_lcd_0/tft_ce]   [get_bd_pins v_vid_in_axi4s_0/vid_io_in_ce]
connect_bd_net [get_bd_pins ov5640_to_lcd_0/tft_de]   [get_bd_pins v_vid_in_axi4s_0/vid_active_video]
connect_bd_net [get_bd_pins ov5640_to_lcd_0/tft_data] [get_bd_pins v_vid_in_axi4s_0/vid_data]
connect_bd_net [get_bd_pins ov5640_to_lcd_0/vsync]    [get_bd_pins v_vid_in_axi4s_0/vid_vsync]
connect_bd_net [get_bd_pins const_axis_en/dout]       [get_bd_pins v_vid_in_axi4s_0/axis_enable]

# 8. 视频桥 AXIS -> VDMA S2MM
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_0/video_out] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]

# 9. VDMA 数据 -> SmartConnect 第5路 -> HP0 -> DDR
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins remap_hp_smc/S04_AXI]

# 10. FCLK0 域时钟
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins v_vid_in_axi4s_0/aclk] \
  [get_bd_pins axi_vdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk] \
  [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk]

# 11. 复位 (vid_io_in_reset 是高有效, 优先用 peripheral_reset)
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] \
  [get_bd_pins v_vid_in_axi4s_0/aresetn] \
  [get_bd_pins axi_vdma_0/axi_resetn]
if {[llength [get_bd_pins -quiet rst_ps7_0_50M/peripheral_reset]] > 0} {
  connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_reset] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_reset]
  puts "RESET_PATH=peripheral_reset"
} else {
  connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_reset]
  puts "RESET_PATH=peripheral_aresetn"
}

# 12. VDMA 控制 -> M02
set_property CONFIG.NUM_MI {4} [get_bd_cells ps7_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins ps7_0_axi_periph/M02_ACLK]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M02_ARESETN]

# 13. 采集IP控制 -> M03
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] [get_bd_intf_pins ov5640_to_lcd_0/S00_AXI]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins ps7_0_axi_periph/M03_ACLK] [get_bd_pins ov5640_to_lcd_0/s00_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M03_ARESETN] [get_bd_pins ov5640_to_lcd_0/s00_axi_aresetn] [get_bd_pins ov5640_to_lcd_0/sys_rst_n]

# 14. 摄像头外部引脚 (名字与 XDC 一致)
create_bd_port -dir I -type clk ov5640_pclk
connect_bd_net [get_bd_ports ov5640_pclk] [get_bd_pins ov5640_to_lcd_0/ov5640_pclk]
create_bd_port -dir I ov5640_href
connect_bd_net [get_bd_ports ov5640_href] [get_bd_pins ov5640_to_lcd_0/ov5640_href]
create_bd_port -dir I ov5640_vsync
connect_bd_net [get_bd_ports ov5640_vsync] [get_bd_pins ov5640_to_lcd_0/ov5640_vsync]
create_bd_port -dir I -from 7 -to 0 ov5640_data
connect_bd_net [get_bd_ports ov5640_data] [get_bd_pins ov5640_to_lcd_0/ov5640_data]
create_bd_port -dir O cam_rst_n
connect_bd_net [get_bd_ports cam_rst_n] [get_bd_pins ov5640_to_lcd_0/cam_rst_n]
create_bd_port -dir O cam_pdn_0
connect_bd_net [get_bd_ports cam_pdn_0] [get_bd_pins ov5640_to_lcd_0/cam_pdn]
create_bd_port -dir O cam_xclk_0
connect_bd_net [get_bd_ports cam_xclk_0] [get_bd_pins ov5640_to_lcd_0/cam_xclk]

# 15. SCCB 外部端口 -> PS EMIO GPIO (照抄 guide_dog)
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 cam_sccb
connect_bd_intf_net [get_bd_intf_ports cam_sccb] [get_bd_intf_pins processing_system7_0/GPIO_0]

assign_bd_address
set rc [catch {validate_bd_design} vmsg]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VALIDATE_MSG=$vmsg"; error $vmsg }
save_bd_design
puts "CAPTURE_CHAIN_V2_OK"
close_project
exit
