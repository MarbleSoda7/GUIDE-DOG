
# 100MHz 版本综合脚本
set project_dir "D:/distortion_correction/vivado/guide_linux_base_100mhz"
set project_name "guide_linux_base"

puts "========================================="
puts "打开工程: $project_dir/$project_name.xpr"
puts "========================================="

open_project "$project_dir/$project_name.xpr"

puts ""
puts "========================================="
puts "重置并运行综合"
puts "========================================="

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

puts ""
puts "========================================="
puts "运行实现"
puts "========================================="

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

puts ""
puts "========================================="
puts "检查时序"
puts "========================================="

open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
puts "WNS: $wns"

if {$wns < 0} {
    puts "ERROR: Timing violation, WNS = $wns"
    exit 1
}

puts ""
puts "========================================="
puts "导出 XSA"
puts "========================================="

write_hw_platform -fixed -include_bit -force -file "$project_dir/led_test_wrapper_100mhz.xsa"

puts ""
puts "========================================="
puts "完成！"
puts "========================================="
puts "Bitstream: $project_dir/guide_linux_base.runs/impl_1/led_test_wrapper.bit"
puts "XSA: $project_dir/led_test_wrapper_100mhz.xsa"

close_project
exit 0
