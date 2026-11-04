open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
set cam_port [get_bd_ports cam_xclk_0]
set cam_pin [get_bd_pins ov5640_to_lcd_0/cam_xclk]
set wizout [get_bd_pins cam_xclk_wiz/clk_out1]
foreach p [list $cam_port $cam_pin $wizout] {
  foreach n [get_bd_nets -of_objects $p] { disconnect_bd_net $n $p }
}
connect_bd_net $wizout $cam_port
validate_bd_design
save_bd_design
generate_target all [get_files D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd]
puts "CAM_PORT_NET=[get_bd_nets -of_objects $cam_port]"
puts "CAM_PIN_NET=[get_bd_nets -of_objects $cam_pin]"
puts "WIZ_NET=[get_bd_nets -of_objects $wizout]"
close_project
exit
