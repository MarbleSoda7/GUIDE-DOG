
cd D:/distortion_correction/vivado/guide_linux_base_100mhz
open_project guide_linux_base.xpr

puts "=========================================="
puts "重新综合 (genlock_mode=2 修复)"
puts "开始时间: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts "=========================================="

# 重置运行
reset_run synth_1
reset_run impl_1

# 综合
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "综合状态: $synth_status"

if {$synth_status != "synth_design Complete!"} {
  puts "ERROR: 综合失败"
  exit 1
}

# 实现
launch_runs impl_1 -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "实现状态: $impl_status"

if {$impl_status != "route_design Complete!"} {
  puts "ERROR: 实现失败"
  exit 1
}

# 生成比特流
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# 检查时序
open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "时序: WNS=$wns WHS=$whs"

if {$wns < 0} {
  puts "WARNING: Setup 时序违例 WNS=$wns"
}

# 导出 XSA (新名称避免覆盖)
write_hw_platform -fixed -include_bit -force -file led_test_wrapper_genlock2.xsa
puts "XSA 已导出: led_test_wrapper_genlock2.xsa"

close_project

puts "=========================================="
puts "完成时间: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts "=========================================="
exit 0
