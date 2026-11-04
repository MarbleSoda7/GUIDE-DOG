set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set outdir "D:/distortion_correction/vivado/guide_linux_base"
open_project $proj
puts "TOP=[get_property TOP [get_filesets sources_1]]"
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set p [get_property PROGRESS [get_runs synth_1]]
puts "SYNTH_PROGRESS=$p"
if {$p ne "100%"} {
  puts "SYNTH_FAILED"
  set s [get_property STATUS [get_runs synth_1]]
  puts "SYNTH_STATUS=$s"
  exit 1
}
open_run synth_1
report_utilization -file "$outdir/full_utilization.rpt"
report_timing_summary -file "$outdir/full_timing_summary.rpt"
report_drc -file "$outdir/full_drc.rpt"
puts "SYNTH_COMPLETE"
close_project
exit
