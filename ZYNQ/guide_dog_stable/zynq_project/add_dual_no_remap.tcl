set proj "D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr"
open_project $proj
open_bd_design "D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
set bd [current_bd_design]
# Preserve the known-good design inside the isolated copy.
write_bd_tcl -force "D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/success_base_before_dual.tcl"
# Remove the Remap accelerator and its DDR SmartConnect inputs; keep the SmartConnect for capture/UDP DDR masters.
foreach c {remap_accel_0} {if {[llength [get_bd_cells -quiet $c]]} {foreach n [get_bd_intf_nets -quiet -of_objects [get_bd_cells $c]] {catch {disconnect_bd_intf_net $n}}; foreach n [get_bd_nets -quiet -of_objects [get_bd_cells $c]] {catch {disconnect_bd_net $n}}; delete_bd_objs [get_bd_cells $c]}}
set smc [get_bd_cells remap_hp_smc]
foreach pin {S00_AXI S01_AXI S02_AXI S03_AXI S04_AXI S05_AXI} {foreach n [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins $smc/$pin]] {catch {disconnect_bd_intf_net $n}}}
set_property CONFIG.NUM_SI {3} $smc
# Keep original VDMA and UDP DMA, then add a second independent capture path.
create_bd_cell -type ip -vlnv xilinx.com:user:ov5640_to_lcd:1.0 ov5640_to_lcd_1
create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:5.0 v_vid_in_axi4s_1
set_property -dict [list CONFIG.C_HAS_ASYNC_CLK {1}] [get_bd_cells v_vid_in_axi4s_1]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_1
set_property -dict [list CONFIG.c_include_mm2s {0} CONFIG.c_include_s2mm {1} CONFIG.c_num_fstores {3} CONFIG.c_s2mm_genlock_mode {0} CONFIG.c_include_internal_genlock {0} CONFIG.c_s2mm_linebuffer_depth {2048} CONFIG.c_s2mm_max_burst_length {64}] [get_bd_cells axi_vdma_1]
# Expand PS AXI interconnect for second camera IP and VDMA control.
set_property CONFIG.NUM_MI {8} [get_bd_cells ps7_0_axi_periph]
# Expand PS EMIO GPIO: cam_sccb[1:0] is camera1, [3:2] is camera2.
set_property -dict [list CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {4}] [get_bd_cells processing_system7_0]
# Add camera2 video ports.
foreach spec {{I 7 0 cam2_data} {I 0 0 cam2_pclk} {I 0 0 cam2_vsync} {I 0 0 cam2_href} {O 0 0 cam2_rst_n} {O 0 0 cam2_pdn} {O 0 0 cam2_xclk}} {
  lassign $spec dir left right name
  if {$left != 0 || $right != 0} {create_bd_port -dir $dir -from $left -to $right $name} else {create_bd_port -dir $dir $name}
}
# Camera2 clock/control constants. Both sensors use the same generated XCLK.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_cam2_rst
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells const_cam2_rst]
set_property CONFIG.CONST_VAL {1} [get_bd_cells const_cam2_rst]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_cam2_pdn
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells const_cam2_pdn]
set_property CONFIG.CONST_VAL {0} [get_bd_cells const_cam2_pdn]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/cam_rst_n] [get_bd_ports cam2_rst_n]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/cam_pdn] [get_bd_ports cam2_pdn]
connect_bd_net [get_bd_pins cam_xclk_wiz/clk_out1] [get_bd_ports cam2_xclk]
# Camera2 video input into its own VDMA.
connect_bd_net [get_bd_ports cam2_pclk] [get_bd_pins ov5640_to_lcd_1/ov5640_pclk]
connect_bd_net [get_bd_ports cam2_vsync] [get_bd_pins ov5640_to_lcd_1/ov5640_vsync]
connect_bd_net [get_bd_ports cam2_href] [get_bd_pins ov5640_to_lcd_1/ov5640_href]
connect_bd_net [get_bd_ports cam2_data] [get_bd_pins ov5640_to_lcd_1/ov5640_data]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/tft_clk] [get_bd_pins v_vid_in_axi4s_1/vid_io_in_clk]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/tft_ce] [get_bd_pins v_vid_in_axi4s_1/vid_io_in_ce]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/tft_de] [get_bd_pins v_vid_in_axi4s_1/vid_active_video]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/tft_data] [get_bd_pins v_vid_in_axi4s_1/vid_data]
connect_bd_net [get_bd_pins ov5640_to_lcd_1/vsync] [get_bd_pins v_vid_in_axi4s_1/vid_vsync]
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_1/video_out] [get_bd_intf_pins axi_vdma_1/S_AXIS_S2MM]
# Common FCLK control clock and reset for the new path.
foreach pin {s_axi_lite_aclk m_axi_s2mm_aclk s_axis_s2mm_aclk} {connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_vdma_1/$pin]}
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins v_vid_in_axi4s_1/aclk] [get_bd_pins ov5640_to_lcd_1/s00_axi_aclk] [get_bd_pins ps7_0_axi_periph/M06_ACLK] [get_bd_pins ps7_0_axi_periph/M07_ACLK]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins axi_vdma_1/axi_resetn] [get_bd_pins v_vid_in_axi4s_1/aresetn] [get_bd_pins ov5640_to_lcd_1/s00_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M06_ARESETN] [get_bd_pins ps7_0_axi_periph/M07_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_reset] [get_bd_pins v_vid_in_axi4s_1/vid_io_in_reset]
connect_bd_net [get_bd_pins const_axis_en/dout] [get_bd_pins v_vid_in_axi4s_1/axis_enable] [get_bd_pins v_vid_in_axi4s_1/aclken]
# Route the second VDMA master into the retained HP DDR SmartConnect.
connect_bd_intf_net [get_bd_intf_pins axi_vdma_1/M_AXI_S2MM] [get_bd_intf_pins remap_hp_smc/S02_AXI]
# Reconnect original VDMA and UDP DMA to the first two SmartConnect inputs.
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins remap_hp_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_udp_0/M_AXI_MM2S] [get_bd_intf_pins remap_hp_smc/S01_AXI]
# Connect new AXI-Lite control ports to free interconnect master ports.
connect_bd_intf_net [get_bd_intf_pins axi_vdma_1/S_AXI_LITE] [get_bd_intf_pins ps7_0_axi_periph/M06_AXI]
connect_bd_intf_net [get_bd_intf_pins ov5640_to_lcd_1/S00_AXI] [get_bd_intf_pins ps7_0_axi_periph/M07_AXI]
# Add address segments and validate.
assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files "D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"] -top
update_compile_order -fileset sources_1
close_project
exit