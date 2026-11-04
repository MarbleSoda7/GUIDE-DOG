# Second implementation pass: the routed checkpoint already meets timing
# (WNS +0.150 ns) but post-route phys_opt_design aborted with 'bad allocation'
# (host memory).  Post-route phys_opt is unnecessary when route already closes,
# so disable it and re-run place/route, verify timing, then write the bitstream.
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

set synth [get_runs synth_1]
if {[get_property STATUS $synth] ne "synth_design Complete!"} { error "synth_1 is not complete: [get_property STATUS $synth]" }

set impl [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false $impl
reset_run $impl

proc parse_timing {rpt} {
    if {![file isfile $rpt]} { error "Missing routed timing report: $rpt" }
    set ch [open $rpt r]; set txt [read $ch]; close $ch
    set idx [string first "Design Timing Summary" $txt]
    if {$idx < 0} { error "Timing summary section not found in $rpt" }
    set tail [string range $txt $idx end]
    if {![regexp -line {\s*(-?\d+\.\d+)\s+-?\d+\.\d+\s+(\d+)\s+\d+\s+(-?\d+\.\d+)} $tail -> wns tfail whs]} {
        error "Could not parse timing summary from $rpt"
    }
    return [list $wns $tfail $whs]
}

puts "PL_RECTIFY_STAGE place_route_start=[clock format [clock seconds]]"
launch_runs $impl -to_step route_design -jobs 1
wait_on_run $impl
if {[get_property STATUS $impl] ne "route_design Complete!"} { error "impl_1 route failed: [get_property STATUS $impl]" }
set rpt [file join [get_property DIRECTORY $impl] led_test_wrapper_timing_summary_routed.rpt]
lassign [parse_timing $rpt] wns tfail whs
puts "PL_RECTIFY_TIMING post_route wns=$wns tns_failing=$tfail whs=$whs"
if {$wns < 0 || $tfail > 0} { error "Routed design violates setup timing: WNS=$wns ns, $tfail failing endpoints" }

puts "PL_RECTIFY_STAGE bitstream_start=[clock format [clock seconds]]"
launch_runs $impl -to_step write_bitstream -jobs 1
wait_on_run $impl
if {[get_property STATUS $impl] ne "write_bitstream Complete!"} { error "impl_1 bitstream failed: [get_property STATUS $impl]" }
lassign [parse_timing $rpt] wns tfail whs
puts "PL_RECTIFY_TIMING final wns=$wns tns_failing=$tfail whs=$whs"

set bit [file join [get_property DIRECTORY $impl] led_test_wrapper.bit]
set bd [file join $root guide_linux_base.srcs sources_1 bd led_test led_test.bd]
set hwh [file join $root guide_linux_base.gen sources_1 bd led_test hw_handoff led_test.hwh]
if {![file isfile $bit] || [file mtime $bit] < $build_start} { error "Missing same-round led_test_wrapper.bit: $bit" }
# The HWH is regenerated from the BD by generate_target, which happens before
# implementation; require it to be at least as new as the BD itself.
if {![file isfile $hwh] || [file mtime $hwh] < [file mtime $bd]} { error "Stale BD HWH: $hwh" }
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
