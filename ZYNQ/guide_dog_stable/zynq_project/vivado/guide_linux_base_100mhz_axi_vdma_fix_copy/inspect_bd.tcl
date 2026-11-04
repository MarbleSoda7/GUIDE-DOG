open_project "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_bd_design "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
puts "=== PS properties HP ==="
report_property [get_bd_cells processing_system7_0]
puts "=== PS AXI pins ==="
puts [get_bd_intf_pins processing_system7_0/*AXI*]
puts "=== AXI peripheral pins ==="
puts [get_bd_intf_pins ps7_0_axi_periph/*]
puts "=== Clocks/reset ==="
puts [get_bd_pins processing_system7_0/FCLK_CLK0]
puts [get_bd_pins rst_ps7_0_50M/peripheral_aresetn]
close_project
exit
