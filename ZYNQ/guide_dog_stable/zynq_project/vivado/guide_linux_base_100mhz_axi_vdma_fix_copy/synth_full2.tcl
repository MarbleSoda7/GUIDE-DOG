set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set outdir "D:/distortion_correction/vivado/guide_linux_base"
open_project $proj
puts "TOP=[get_property TOP [get_filesets sources_1]]"
# 重置所有 runs (含 OOC IP runs), 清除上次失败留下的损坏缓存
foreach r [get_runs] { catch { reset_run $r } }
puts "RUNS_RESET_DONE"
# 低并发避免 21MB 器件 rtd 文件并发读冲突
launch_runs synth_1 -jobs 2
wait_on_run synth_1
set p [get_property PROGRESS [get_runs synth_1]]
set s [get_property STATUS [get_runs synth_1]]
puts "SYNTH_PROGRESS=$p"
puts "SYNTH_STATUS=$s"
if {$p ne "100%"} { puts "SYNTH_FAILED"; exit 1 }
open_run synth_1
report_utilization -file "$outdir/full_utilization.rpt"
report_timing_summary -file "$outdir/full_timing_summary.rpt"
report_drc -file "$outdir/full_drc.rpt"
puts "SYNTH_COMPLETE"
close_project
exit
