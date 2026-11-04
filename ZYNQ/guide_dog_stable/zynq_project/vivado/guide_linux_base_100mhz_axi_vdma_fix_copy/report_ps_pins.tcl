open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
puts "PSPINS=[get_bd_pins -of_objects [get_bd_cells processing_system7_0]]"
puts "PSINTF=[get_bd_intf_pins -of_objects [get_bd_cells processing_system7_0]]"
close_project
exit
