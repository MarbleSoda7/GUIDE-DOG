open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
open_bd_design {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
foreach c {ov5640_to_lcd_0 v_vid_in_axi4s_0 axi_vdma_0 axi_dma_udp_0 remap_hp_smc ps7_0_axi_periph} {puts "CELL=$c"; if {[llength [get_bd_cells -quiet $c]]} {puts "PINS=[get_bd_pins -of_objects [get_bd_cells $c]]"; puts "INTF=[get_bd_intf_pins -of_objects [get_bd_cells $c]]"}}
close_project
exit
