if {![info exists ::env(PL_RECTIFY_BUILD)] || $::env(PL_RECTIFY_BUILD) ne "1"} { error "opt-in required" }
open_project {D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
set jobs 1
set targets {}
foreach run [get_runs -quiet *] {
    if {[get_property IS_SYNTHESIS $run] && [get_property STATUS $run] ne "synth_design Complete!" && $run ne "synth_1"} {
        lappend targets $run
    }
}
puts "PL_RECTIFY_TARGETS $targets"
foreach run $targets {
    if {[get_property STATUS $run] eq "Queued..."} { reset_run $run }
    puts "PL_RECTIFY_RUN_START $run ([get_property STATUS $run])"
    launch_runs $run -jobs $jobs
    wait_on_run $run
    set st [get_property STATUS $run]
    puts "PL_RECTIFY_RUN_DONE $run = $st"
    if {$st ne "synth_design Complete!"} { error "OOC synth failed: $run = $st" }
}
puts "PL_RECTIFY_ALL_OOC_DONE"
close_project
