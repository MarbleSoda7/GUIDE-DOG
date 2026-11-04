open_project "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_bd_design "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
# 先用 5.1 创建视频桥，探测真实引脚
create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:5.1 v_probe
set_property CONFIG.C_HAS_ASYNC_CLK {1} [get_bd_cells v_probe]
puts "=== v_vid_in_axi4s:5.1 引脚 ==="
foreach p [get_bd_pins v_probe/*] { puts $p }
puts "=== 复位相关引脚 ==="
foreach p [get_bd_pins v_probe/*reset*] { puts "RESET_PIN: $p" }
# 探测完删掉
delete_bd_objs [get_bd_cells v_probe]
close_project
exit
