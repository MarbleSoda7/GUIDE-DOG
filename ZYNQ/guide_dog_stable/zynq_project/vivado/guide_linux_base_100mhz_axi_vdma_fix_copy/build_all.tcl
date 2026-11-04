set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set out  "D:/distortion_correction/vivado/guide_linux_base"
open_project $proj
# 移除未使用的混合版 IP 仓库路径
set keep {}
foreach p [get_property ip_repo_paths [current_project]] { if {![string match *hls_ip_grid_hybrid* $p]} { lappend keep $p } }
set_property ip_repo_paths $keep [current_project]
update_ip_catalog
puts "IP_REPOS=[get_property ip_repo_paths [current_project]]"
puts "TOP=[get_property TOP [get_filesets sources_1]]"

foreach r [get_runs] { catch { reset_run $r } }
launch_runs synth_1 -jobs 1
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "SYNTH_FAILED"; exit 1 }
open_run synth_1
report_utilization -file "$out/synth_utilization.rpt"
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "IMPL_FAILED"; exit 1 }
open_run impl_1
report_utilization -file "$out/impl_utilization.rpt"
report_timing_summary -file "$out/impl_timing_summary.rpt"
write_hw_platform -fixed -include_bit -force -file "$out/led_test_wrapper.xsa"
puts "ALL_DONE"
close_project
exit
