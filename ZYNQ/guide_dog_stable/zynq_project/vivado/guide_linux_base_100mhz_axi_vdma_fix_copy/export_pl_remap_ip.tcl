# Export-only recovery path: reuses an existing csynth_design solution.
# Same explicit opt-in gate as run_pl_remap_hls.tcl.
if {![info exists ::env(PL_RECTIFY_BUILD)] || $::env(PL_RECTIFY_BUILD) ne "1"} {
    error "Refusing HLS IP export: use BUILD_PL_RECTIFY.ps1 -Build explicitly"
}
set root [file normalize [file dirname [info script]]]
set project [file join $root pl_remap_accel_hls]
set output [file join $root ip_repo hls]
if {[file exists $output]} { error {Refusing existing HLS export repo; archive it before a new build} }
if {![file isdir $project]} { error "Missing synthesised project: $project" }
open_project $project
open_solution solution1
set packaged [file join $project solution1 impl ip]
if {[file isfile [file join $packaged component.xml]]} {
    file delete -force $packaged
}
export_design -format ip_catalog -vendor xilinx.com -library hls -version 1.0
if {![file isfile [file join $packaged component.xml]]} { error {Missing standard HLS IP component.xml} }
file mkdir [file dirname $output]
file copy $packaged $output
if {![file isfile [file join $output component.xml]]} { error "HLS export did not create [file join $output component.xml]" }
close_project
puts "PL_REMAP_IP_EXPORTED=$output"
