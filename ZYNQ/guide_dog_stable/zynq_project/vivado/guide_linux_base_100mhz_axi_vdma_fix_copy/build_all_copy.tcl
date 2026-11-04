set proj "D:/distortion_correction/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr"
set out  "D:/distortion_correction/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy"
open_project $proj
puts "TOP=[get_property TOP [get_filesets sources_1]]"
foreach r [get_runs] { catch { reset_run $r } }
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set sp [get_property PROGRESS [get_runs synth_1]]
puts "SYNTH_PROGRESS=$sp STATUS=[get_property STATUS [get_runs synth_1]]"
if {$sp ne "100%"} { exit 1 }
open_run synth_1
report_utilization -file "$out/synth_utilization.rpt"
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set ip [get_property PROGRESS [get_runs impl_1]]
puts "IMPL_PROGRESS=$ip STATUS=[get_property STATUS [get_runs impl_1]]"
if {$ip ne "100%"} { exit 1 }
open_run impl_1
report_utilization -file "$out/impl_utilization.rpt"
report_timing_summary -file "$out/impl_timing_summary.rpt"
write_hw_platform -fixed -include_bit -force -file "$out/led_test_wrapper.xsa"
puts "ALL_DONE_COPY"
close_project
exit
