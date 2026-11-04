open_project "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_bd_design "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:5.0 v_probe
set_property -dict [list CONFIG.C_HAS_ASYNC_CLK {1}] [get_bd_cells v_probe]
puts "=== PIN_DUMP_BEGIN ==="
foreach p [lsort [get_bd_pins v_probe/*]] { puts "PIN $p" }
puts "=== INTF_DUMP_BEGIN ==="
foreach i [lsort [get_bd_intf_pins v_probe/*]] { puts "INTF $i" }
puts "=== RESET_PINS ==="
foreach p [get_bd_pins v_probe/*reset*] { puts "RESETPIN $p" }
foreach p [get_bd_pins v_probe/*rst*] { puts "RSTPIN $p" }
puts "=== PROBE_DONE ==="
exit
