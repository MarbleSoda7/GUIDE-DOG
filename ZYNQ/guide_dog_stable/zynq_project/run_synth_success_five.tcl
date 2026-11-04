open_project {D:/distortion_correction/success_five/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
if {[get_property STATUS [get_runs synth_1]] eq "synth_design Complete!"} {
  open_run synth_1
  report_utilization -file {D:/distortion_correction/success_five/vivado/synth_utilization.rpt}
  report_timing_summary -file {D:/distortion_correction/success_five/vivado/synth_timing.rpt}
}
close_project
exit
