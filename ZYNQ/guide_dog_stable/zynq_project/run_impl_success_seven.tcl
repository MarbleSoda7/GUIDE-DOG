open_project {D:/distortion_correction/success_seven/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
if {[get_property STATUS [get_runs impl_1]] eq "write_bitstream Complete!"} {
  open_run impl_1
  report_utilization -hierarchical -hierarchical_depth 2 -file {D:/distortion_correction/success_seven/vivado/impl_utilization_seven.rpt}
  report_timing_summary -file {D:/distortion_correction/success_seven/vivado/impl_timing_seven.rpt}
  write_hw_platform -fixed -include_bit -force -file {D:/distortion_correction/success_seven/hardware.xsa}
}
close_project
exit
