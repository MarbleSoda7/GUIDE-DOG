# Run from Vivado Hardware Manager after connecting hw_server.
# The ELF is downloaded separately with XSDB/Vitis because Vivado programs only the FPGA.
set here [file normalize [file dirname [info script]]]
set root [file normalize [file join $here ..]]
set bit [file join $root test_artifacts commit_restart_v1.bit]
if {![file exists $bit]} { error "Missing bitstream: $bit" }
open_hw_manager
connect_hw_server -url tcp:127.0.0.1:3121
set targets [get_hw_targets]
if {[llength $targets] == 0} { error "No JTAG target found" }
current_hw_target [lindex $targets 0]
open_hw_target
set devs [get_hw_devices]
if {[llength $devs] == 0} { error "No FPGA device found" }
set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMMED_BIT=$bit"
