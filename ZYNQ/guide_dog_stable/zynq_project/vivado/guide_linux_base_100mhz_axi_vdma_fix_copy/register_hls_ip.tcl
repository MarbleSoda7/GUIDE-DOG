# Source from integration; opens only the relocated copy when used standalone.
set root [file normalize [file dirname [info script]]]
source [file join $root prepare_project.tcl]
set repo [file join $root ip_repo hls]
if {![file isdirectory $repo]} { error "HLS export missing: $repo" }
set repos [get_property ip_repo_paths [current_project]]
lappend repos $repo
set_property ip_repo_paths [lsort -unique $repos] [current_project]
update_ip_catalog -rebuild
set defs [get_ipdefs -all xilinx.com:hls:pl_remap_accel:1.0]
if {[llength $defs] != 1} { error "Expected exactly one xilinx.com:hls:pl_remap_accel:1.0; got $defs" }
puts "PL_REMAP_IP_FOUND=$defs"
