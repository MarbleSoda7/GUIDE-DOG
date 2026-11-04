set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_project $proj
set cdir "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/constrs_1/new"
# 移除根目录参考xdc(避免与正式约束冲突)
foreach f [get_files -quiet *eth_pins_reference.xdc] { remove_files $f }
foreach f [get_files -quiet *ov5640_reference.xdc] { remove_files $f }
# 加入正式约束
add_files -fileset constrs_1 -norecurse [list "$cdir/eth_pins.xdc" "$cdir/ov5640_camera.xdc"]
set_property target_constrs_file "$cdir/ov5640_camera.xdc" [get_filesets constrs_1]
update_compile_order -fileset sources_1
puts "=== 当前约束集文件 ==="
foreach f [get_files -of_objects [get_filesets constrs_1]] { puts "XDC $f" }
# 生成 BD 输出
generate_target all [get_files -quiet *led_test.bd]
puts "GENERATE_TARGET_DONE"
save_project
close_project
exit
