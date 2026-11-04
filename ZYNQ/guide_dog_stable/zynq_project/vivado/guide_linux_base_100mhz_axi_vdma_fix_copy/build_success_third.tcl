set proj "D:/distortion_correction/success_third/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr"
set out  "D:/distortion_correction/success_third/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy"
open_project $proj
puts "TOP=[get_property TOP [get_filesets sources_1]]"
foreach r [get_runs] { catch { reset_run $r } }
launch_runs synth_1 -jobs 1
wait_on_run synth_1
puts "SYNTH_PROGRESS=[get_property PROGRESS [get_runs synth_1]] STATUS=[get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { exit 1 }
open_run synth_1
report_utilization -file "$out/synth_utilization_success_third.rpt"
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
puts "IMPL_PROGRESS=[get_property PROGRESS [get_runs impl_1]] STATUS=[get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { exit 1 }
open_run impl_1
report_utilization -file "$out/impl_utilization_success_third.rpt"
report_timing_summary -file "$out/impl_timing_success_third.rpt"
write_hw_platform -fixed -include_bit -force -file "$out/led_test_wrapper_success_third.xsa"
puts "SUCCESS_THIRD_VIVADO_DONE"
close_project
exit
