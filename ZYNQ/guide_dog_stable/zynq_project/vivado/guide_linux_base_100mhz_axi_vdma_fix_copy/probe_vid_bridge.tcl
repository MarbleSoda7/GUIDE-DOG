open_project "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_bd_design "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
puts "=== v_vid_in_axi4s_0 所有引脚 ==="
foreach p [get_bd_pins v_vid_in_axi4s_0/*] { puts $p }
close_project
exit
