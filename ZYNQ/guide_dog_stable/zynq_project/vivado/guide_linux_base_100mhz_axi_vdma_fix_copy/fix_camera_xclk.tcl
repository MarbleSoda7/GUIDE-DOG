open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
set ps [get_bd_cells processing_system7_0]
set cam [get_bd_cells ov5640_to_lcd_0]
set cam_port [get_bd_ports cam_xclk_0]
set oldnets [get_bd_nets -of_objects [get_bd_pins $cam/cam_xclk]]
foreach n $oldnets { disconnect_bd_net $n [get_bd_pins $cam/cam_xclk] }
set wiz [get_bd_cells cam_xclk_wiz]
if {[llength $wiz] == 0} {
  create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 cam_xclk_wiz
  set wiz [get_bd_cells cam_xclk_wiz]
}
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.0} \
  CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
  CONFIG.NUM_OUT_CLKS {1} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.0} \
  CONFIG.CLKOUT1_REQUESTED_DUTY_CYCLE {50.000} \
  CONFIG.USE_RESET {false} \
  CONFIG.USE_LOCKED {false}] $wiz
connect_bd_net [get_bd_pins $ps/FCLK_CLK0] [get_bd_pins $wiz/clk_in1]
connect_bd_net [get_bd_pins $wiz/clk_out1] $cam_port
validate_bd_design
save_bd_design
generate_target all [get_files D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd]
puts "CAM_XCLK_WIZ=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $wiz]"
puts "CAM_XCLK_PORT=[get_bd_ports cam_xclk_0]"
close_project
exit
