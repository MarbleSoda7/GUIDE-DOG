open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
open_bd_design {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
foreach p {/ov5640_to_lcd_0/tft_data /ov5640_to_lcd_1/tft_data /ov5640_to_lcd_0/ov5640_data /processing_system7_0/GPIO_0 /cam_sccb /axi_vdma_0/M_AXI_S2MM /axi_vdma_1/M_AXI_S2MM /remap_hp_smc/S00_AXI /remap_hp_smc/S01_AXI /remap_hp_smc/S02_AXI} {if {[llength [get_bd_pins -quiet $p]]} {puts "$p left=[get_property LEFT [get_bd_pins $p]] right=[get_property RIGHT [get_bd_pins $p]] width=[get_property WIDTH [get_bd_pins $p]] net=[get_bd_intf_nets -of_objects [get_bd_pins $p]]"} elseif {[llength [get_bd_intf_ports -quiet $p]]} {puts "$p left=[get_property LEFT [get_bd_intf_ports $p]] right=[get_property RIGHT [get_bd_intf_ports $p]] net=[get_bd_intf_nets -of_objects [get_bd_intf_ports $p]]"}}
puts "CONSTRAINTS=[get_files -of_objects [get_filesets constrs_1]]"
puts "AXIL=[get_bd_intf_nets -of_objects [get_bd_intf_pins axi_vdma_1/S_AXI_LITE]]"
validate_bd_design
close_project
exit
