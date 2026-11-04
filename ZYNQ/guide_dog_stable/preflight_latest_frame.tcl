set ROOT [file normalize [file join [file dirname [info script]] latest_frame_project]]
open_project [file join $ROOT latest_frame_project.xpr]
set bd [get_files -quiet */zynq.bd]
open_bd_design $bd
validate_bd_design
puts "LATEST_PREFLIGHT_TOP=[get_property TOP [get_filesets sources_1]]"
set eth [get_bd_cells -quiet eth_stream_0]
if {[llength $eth] != 1} { error "LATEST_PREFLIGHT_MISSING_ETH_STREAM=$eth" }
if {[get_property CONFIG.ENABLE_RGMII_ILA $eth] ne {1}} {
    error "LATEST_PREFLIGHT_RGMII_ILA_DISABLED"
}
set ila [get_ips -quiet ila_rgmii_tx]
if {[llength $ila] != 1} { error "LATEST_PREFLIGHT_MISSING_ILA_IP=$ila" }
set ila_probes [get_property CONFIG.C_NUM_OF_PROBES $ila]
if {$ila_probes ne {5}} { error "LATEST_PREFLIGHT_ILA_PROBE_COUNT=$ila_probes" }
puts "LATEST_PREFLIGHT_ILA_PROBES=$ila_probes"
foreach cell {axi_vdma_0 axis_rgb24_to_32_0 vdma_frame_commit_axi_0 vdma_mm2s_slot_monitor_0 latest_frame_pacer_0 latest_frame_stream_gate_0 axis_32_to_64_0 axis_flow_monitor_0 eth_stream_0} {
    if {[llength [get_bd_cells -quiet $cell]] != 1} { error "LATEST_PREFLIGHT_MISSING=$cell" }
}
foreach {cell pin} {
    axi_vdma_0 M_AXI_S2MM
    axi_vdma_0 M_AXI_MM2S
    axi_vdma_0 S_AXIS_S2MM
    axi_vdma_0 M_AXIS_MM2S
    vdma_frame_commit_axi_0 mon_axi
    vdma_mm2s_slot_monitor_0 mon_axi
    latest_frame_stream_gate_0 s_axis
    latest_frame_stream_gate_0 m_axis
    axis_32_to_64_0 m_axis
    axis_flow_monitor_0 s_axis
} {
    if {[llength [get_bd_intf_nets -of_objects [get_bd_intf_pins $cell/$pin]]] != 1} {
        error "LATEST_PREFLIGHT_DISCONNECTED=$cell/$pin"
    }
}
report_ip_status -file [file join $ROOT latest_ip_status.rpt]
puts "LATEST_PREFLIGHT_IP_STATUS=[file join $ROOT latest_ip_status.rpt]"
puts "LATEST_PREFLIGHT_PASS"
close_project
exit
