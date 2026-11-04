# Probe: what happens to the interface net when taps are added per-pin.
if {![info exists ::env(PL_RECTIFY_PROBE)]} { error "probe only" }
set root [file normalize [file dirname [info script]]]
open_bd_design [file join $root guide_linux_base.srcs sources_1 bd led_test led_test.bd]
foreach signal {RVALID RRESP BVALID BRESP RREADY BREADY} {
    set mp [get_bd_pins -quiet pl_remap_accel_0/m_axi_gmem_$signal]
    set gp [get_bd_pins -quiet remap_axi_guard_0/[string tolower $signal]]
    set mn [get_bd_nets -quiet -of_objects $mp]
    set gn [get_bd_nets -quiet -of_objects $gp]
    puts "PROBE $signal master_pin=$mp master_net=$mn guard_pin=$gp guard_net=$gn"
}
set intf [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins pl_remap_accel_0/m_axi_gmem]]
puts "PROBE intf_net=$intf"
close_bd_design [current_bd_design]
close_project
