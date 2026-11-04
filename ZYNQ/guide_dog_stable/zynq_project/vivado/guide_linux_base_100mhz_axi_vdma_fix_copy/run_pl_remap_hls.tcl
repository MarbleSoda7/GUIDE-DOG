# Explicit opt-in only. BUILD_PL_RECTIFY.ps1 sets this after -Build.
if {![info exists ::env(PL_RECTIFY_BUILD)] || $::env(PL_RECTIFY_BUILD) ne "1"} {
    error "Refusing HLS synthesis: use BUILD_PL_RECTIFY.ps1 -Build explicitly"
}
set root [file normalize [file dirname [info script]]]
set project [file join $root pl_remap_accel_hls]
set output [file join $root ip_repo hls]
if {[file exists $output]} { error {Refusing existing HLS export repo; archive it before a new build} }
set component [file join $output component.xml]
open_project -reset $project
set_top pl_remap_accel
add_files [file join $root pl_remap_accel.cpp] -cflags {-std=c++14}
# A proper HLS csim testbench can be supplied by the kernel owner.
set tb [file join $root pl_remap_accel_tb.cpp]
if {[file isfile $tb]} { add_files -tb $tb -cflags {-std=c++14} }
open_solution -reset solution1 -flow_target vivado
set_part xc7z020clg400-2
create_clock -period 10.0 -name ap_clk
if {[file isfile $tb]} { csim_design }
csynth_design
export_design -format ip_catalog -vendor xilinx.com -library hls -version 1.0
set packaged [file join $project solution1 impl ip]
if {![file isfile [file join $packaged component.xml]]} { error {Missing standard HLS IP component.xml} }
file mkdir [file dirname $output]
file copy $packaged $output
if {![file isfile $component]} { error "HLS export did not create $component" }
close_project
puts "PL_REMAP_IP_EXPORTED=$output"
