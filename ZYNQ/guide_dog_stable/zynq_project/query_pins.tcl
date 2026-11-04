open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
open_bd_design {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
puts [get_bd_pins -of_objects [get_bd_cells ov5640_to_lcd_0]]
puts [get_bd_intf_pins -of_objects [get_bd_cells ov5640_to_lcd_0]]
puts [get_bd_pins -of_objects [get_bd_cells v_vid_in_axi4s_0]]
close_project
exit
