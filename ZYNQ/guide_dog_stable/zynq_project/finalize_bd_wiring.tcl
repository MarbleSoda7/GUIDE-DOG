set p {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
set b {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
open_project $p
open_bd_design $b
# Reuse the removed accelerator's AXI-Lite slot for the camera2 config IP.
set n [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins ps7_0_axi_periph/M07_AXI]]
if {[llength $n]} {delete_bd_objs $n}
set_property CONFIG.NUM_MI {7} [get_bd_cells ps7_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins ov5640_to_lcd_1/S00_AXI] [get_bd_intf_pins ps7_0_axi_periph/M01_AXI]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins ov5640_to_lcd_1/sys_rst_n]
assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files $b] -top
update_compile_order -fileset sources_1
close_project
exit
