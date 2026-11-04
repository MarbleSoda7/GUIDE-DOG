open_project "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr"
open_bd_design "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
puts "CELL=[get_property CONFIG.C_S_AXIS_S2MM_TDATA_WIDTH [get_bd_cells axi_vdma_0]]"
puts "PIN=[get_property CONFIG.TDATA_WIDTH [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]]"
puts "OUT=[get_property CONFIG.TDATA_WIDTH [get_bd_intf_pins axis_rgb24_to_32_0/m_axis]]"
puts "SRC=[get_property CONFIG.C_S_AXIS_S2MM_TDATA_WIDTH.VALUE_SRC [get_bd_cells axi_vdma_0]]"
close_project
exit
