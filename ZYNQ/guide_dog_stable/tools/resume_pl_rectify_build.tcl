# Resume launcher: relaunch only the OOC/top runs that are not complete.
# Same gates/checks as launch_pl_rectify_build.tcl.
if {![info exists ::env(PL_RECTIFY_BUILD)] || $::env(PL_RECTIFY_BUILD) ne "1"} {
    error "Refusing synth/impl: use BUILD_PL_RECTIFY.ps1 -Build explicitly"
}
set root [file normalize [file join [file dirname [info script]] .. zynq_project vivado guide_linux_base_100mhz_axi_vdma_fix_copy]]
set output [file join $root build_output]
file mkdir $output
foreach name {led_test_wrapper.bit led_test_wrapper.hwh led_test_wrapper.xsa} {
    set stale [file join $output $name]
    if {[file exists $stale]} { error "Refusing to overwrite existing artifact: $stale" }
}
set build_start [clock seconds]
open_project [file join $root guide_linux_base.xpr]
set jobs 1
if {[info exists ::env(PL_RECTIFY_JOBS)] && $::env(PL_RECTIFY_JOBS) ne ""} {
    set jobs [expr {max(1, int($::env(PL_RECTIFY_JOBS)))}]
}
puts "PL_RECTIFY_JOBS=$jobs"

# Reset only runs that are not already complete, so finished OOC syntheses are reused.
foreach run [get_runs -quiet *] {
    set st [get_property STATUS $run]
    set is_synth [get_property IS_SYNTHESIS $run]
    if {$is_synth && $st ne "synth_design Complete!" && $st ne "Not started"} {
        puts "PL_RECTIFY_RESET=$run ($st)"
        reset_run $run
    }
}

set synth [get_runs synth_1]
if {[get_property STATUS $synth] ne "synth_design Complete!"} {
    launch_runs $synth -jobs $jobs
    wait_on_run $synth
}
if {[get_property STATUS $synth] ne "synth_design Complete!"} { error "synth_1 failed: [get_property STATUS $synth]" }
puts "PL_RECTIFY_SYNTH_DONE=[get_property STATUS $synth]"

set impl [get_runs impl_1]
reset_run $impl
launch_runs $impl -to_step write_bitstream -jobs $jobs
wait_on_run $impl
if {[get_property STATUS $impl] ne "write_bitstream Complete!"} { error "impl_1 failed: [get_property STATUS $impl]" }

set bit [file join [get_property DIRECTORY $impl] led_test_wrapper.bit]
set hwh [file join $root guide_linux_base.gen sources_1 bd led_test hw_handoff led_test.hwh]
if {![file isfile $bit] || [file mtime $bit] < $build_start} { error "Missing same-round led_test_wrapper.bit: $bit" }
if {![file isfile $hwh] || [file mtime $hwh] < $build_start} { error "Missing same-round BD HWH: $hwh" }
set ch [open $hwh r]; set hs [string tolower [read $ch]]; close $ch
if {[string first "pl_remap" $hs] < 0 || [string first "remap_axi_guard" $hs] < 0} { error "HWH lacks PL remap/guard nodes: $hwh" }
file copy -force $bit [file join $output led_test_wrapper.bit]
file copy -force $hwh [file join $output led_test_wrapper.hwh]
open_run $impl
write_hw_platform -fixed -include_bit -force -file [file join $output led_test_wrapper.xsa]
foreach name {led_test_wrapper.bit led_test_wrapper.hwh led_test_wrapper.xsa} {
    if {![file isfile [file join $output $name]]} { error "Missing canonical artifact: $name" }
}
close_project
puts "PL_RECTIFY_ARTIFACTS=$output"
