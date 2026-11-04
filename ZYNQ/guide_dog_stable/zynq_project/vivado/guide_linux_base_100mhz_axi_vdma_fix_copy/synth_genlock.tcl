# 重新综合实现脚本（Genlock 版本）

puts "打开工程..."
open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr

puts ""
puts "重置运行..."
reset_run synth_1
reset_run impl_1

puts ""
puts "启动综合..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: 综合失败"
    exit 1
}

puts ""
puts "✅ 综合完成"
puts ""

puts "启动实现..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: 实现失败"
    exit 1
}

puts ""
puts "✅ 实现完成，比特流已生成"
puts ""

puts "导出 XSA..."
write_hw_platform -fixed -include_bit -force -file D:/distortion_correction/vivado/guide_linux_base_100mhz/led_test_wrapper_100mhz_genlock.xsa

puts ""
puts "════════════════════════════════════════════════════════════════"
puts "🎉 综合实现完成！(Genlock 版本)"
puts "════════════════════════════════════════════════════════════════"
puts ""
puts "输出文件："
puts "  - Bitstream: guide_linux_base.runs/impl_1/led_test_wrapper.bit"
puts "  - XSA: led_test_wrapper_100mhz_genlock.xsa"
puts ""
puts "关键改动："
puts "  ✓ VDMA Genlock 已启用"
puts "  ✓ S2MM/MM2S 同步，防止读写冲突"
puts "  ✓ FCLK_CLK0 = 100 MHz"
puts ""

close_project
exit
