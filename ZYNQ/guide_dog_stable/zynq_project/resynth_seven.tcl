open_project {D:/distortion_correction/success_seven/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
generate_target all [get_files led_test.bd] -force
foreach r {led_test_axis_rgb24_to_32_0_0_synth_1 led_test_axis_rgb24_to_32_1_0_synth_1 led_test_eth_stream_0_0_synth_1 led_test_axis_flow_monitor_0_0_synth_1} {
  if {[llength [get_runs -quiet $r]]} { reset_run $r ; puts "reset $r" }
}
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
close_project
exit
