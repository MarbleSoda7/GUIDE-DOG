set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
open_project $proj
open_bd_design $bdfile

puts "=== 重新生成 BD 输出产物 ==="
generate_target all [get_files $bdfile] -force
export_ip_user_files -of_objects [get_files $bdfile] -no_script -sync -force

puts "=== 检查生成的 IP 文件 ==="
set smc_path [get_property IP_OUTPUT_DIR [get_ips led_test_remap_hp_smc_0]]
puts "SmartConnect output: $smc_path"
if {[file exists "$smc_path/synth/led_test_remap_hp_smc_0.v"]} {
    puts "✅ SmartConnect RTL 已生成"
} else {
    puts "❌ SmartConnect RTL 缺失"
}

set eth_path [get_property IP_OUTPUT_DIR [get_ips led_test_eth_stream_0_0]]
puts "eth_stream output: $eth_path"
if {[file exists "$eth_path/sim/led_test_eth_stream_0_0.v"]} {
    puts "✅ eth_stream wrapper 已生成"
} else {
    puts "❌ eth_stream wrapper 缺失"
}

# 补充缺失的 gmii_to_rgmii_phase_sweep.v（从参考工程复制）
set missing_src "D:/qian-master/qian-master/ZYNQ/guide_dog_main/stage3/gmii_to_rgmii_phase_sweep.v"
set dest_dir "D:/distortion_correction/vivado/guide_linux_base/eth_rtl"
if {[file exists $missing_src]} {
    file copy -force $missing_src $dest_dir
    add_files "$dest_dir/gmii_to_rgmii_phase_sweep.v"
    puts "✅ 已补充 gmii_to_rgmii_phase_sweep.v"
} else {
    puts "⚠️  参考文件不存在: $missing_src"
}

save_project
close_project
puts "BD_REGENERATED"
exit
