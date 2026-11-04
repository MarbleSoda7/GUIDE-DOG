open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "implementation failed" }
write_hw_platform -fixed -include_bit -force -file D:/distortion_correction/vivado/guide_linux_base_100mhz/led_test_wrapper_100mhz_freerun.xsa
close_project
exit
