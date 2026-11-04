# Generate Vivado-managed Block Design output products, including zynq_wrapper.v.
# This is a source-generation step only; it does not synthesize or implement.
set root [file normalize [file dirname [info script]]]
set xpr [file join $root phase_b_project.xpr]
if {![file exists $xpr]} { error "PROJECT_NOT_FOUND=$xpr" }
open_project $xpr
set bd [get_files -quiet [file join $root phase_b_project.srcs sources_1 bd zynq zynq.bd]]
if {[llength $bd] != 1} { error "BD_NOT_FOUND=$bd" }
generate_target all $bd
make_wrapper -files $bd -top
set wrapper [file join $root phase_b_project.gen sources_1 bd zynq hdl zynq_wrapper.v]
if {[llength [get_files -quiet $wrapper]] == 0} { add_files -norecurse $wrapper }
set_property source_mgmt_mode All [current_project]
set_property top zynq_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
if {![file exists $wrapper]} { error "WRAPPER_NOT_GENERATED=$wrapper" }
puts "WRAPPER_GENERATED=$wrapper"
close_project
exit
