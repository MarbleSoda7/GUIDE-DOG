# Explicit long-flow launcher. Never call directly without BUILD_PL_RECTIFY=1.
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
set bd [get_files [file join $root guide_linux_base.srcs sources_1 bd led_test led_test.bd]]
reset_target all $bd
generate_target all $bd
set synth [get_runs synth_1]
set impl [get_runs impl_1]
# Default to one parallel job: this host has 15.3 GB RAM and the four-job
# fan-out (main Vivado + four OOC synthesizers) dies with
# "boost::filesystem::status: 系统资源不足" during create_project -in_memory.
set jobs 1
if {[info exists ::env(PL_RECTIFY_JOBS)] && $::env(PL_RECTIFY_JOBS) ne ""} {
    set jobs [expr {max(1, int($::env(PL_RECTIFY_JOBS)))}]
}
puts "PL_RECTIFY_JOBS=$jobs"
reset_run $synth
launch_runs $synth -jobs $jobs
wait_on_run $synth
if {[get_property STATUS $synth] ne "synth_design Complete!"} { error "synth_1 failed: [get_property STATUS $synth]" }
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

