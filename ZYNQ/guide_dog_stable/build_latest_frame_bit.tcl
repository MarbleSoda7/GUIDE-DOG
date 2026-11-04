if {[info exists ::env(LATEST_NODE_DIAG_BASE)] && $::env(LATEST_NODE_DIAG_BASE) ne {}} {
    set BASE [file normalize $::env(LATEST_NODE_DIAG_BASE)]
} else {
    set BASE [file normalize [file dirname [info script]]]
}
if {[info exists ::env(LATEST_NODE_DIAG_PROJECT_DIR)] &&
    $::env(LATEST_NODE_DIAG_PROJECT_DIR) ne {}} {
    set PROJECT_DIR $::env(LATEST_NODE_DIAG_PROJECT_DIR)
} else {
    set PROJECT_DIR latest_frame_project
}
set ROOT [file join $BASE $PROJECT_DIR]
if {[info exists ::env(LATEST_BUILD_ID)] && $::env(LATEST_BUILD_ID) ne {}} {
    set BUILD_ID $::env(LATEST_BUILD_ID)
} else {
    set BUILD_ID {20261001T001416Z_axis_nodes_v4}
}
if {[info exists ::env(LATEST_ARTIFACT_TAG)] && $::env(LATEST_ARTIFACT_TAG) ne {}} {
    set ARTIFACT_TAG $::env(LATEST_ARTIFACT_TAG)
} else {
    set ARTIFACT_TAG {stage5_latest_frame_node_diag_v4}
}
set OUT [file join $BASE test_artifacts $BUILD_ID]
file mkdir $OUT
open_project [file join $ROOT latest_frame_project.xpr]
set_property source_mgmt_mode All [current_project]
set_property TOP_AUTO_SET 0 [get_filesets sources_1]
set_property TOP zynq_wrapper [get_filesets sources_1]
foreach src [list \
    [file join $BASE rtl axis_rgb24_to_32_node_diag.v] \
    [file join $BASE rtl latest_frame_owner_diag.v] \
    [file join $BASE eth_rtl eth_stream_stage3_axis_diag.v]] {
    if {[llength [get_files -quiet $src]] == 0} { add_files -norecurse $src }
}
update_compile_order -fileset sources_1
set bd [get_files -quiet */zynq.bd]
open_bd_design $bd
# Do not refresh the old module_ref names in-place. This project contains
# multiple historical XCI snapshots with the same reference name; Vivado
# selected the stale axis_rgb24_to_32 boundary (the generated wrapper lacked
# diag_counters). Replace only these two cells with revision-unique wrappers,
# preserving the established instance names and reconnecting every endpoint.
file copy -force $bd [file join $OUT pre_node_diag_bd.json]
# This Tcl may be re-run against its own isolated project. Remove only the
# previous diagnostic counter net before deleting/recreating the module-ref
# cells; otherwise Vivado can retain an orphaned net and silently ground it
# while assigning a suffixed name to the newly connected net.
set stale_camera_diag_net [get_bd_nets -quiet -of_objects \
    [get_bd_pins -quiet axis_rgb24_to_32_0/diag_counters]]
if {[llength $stale_camera_diag_net] > 1} {
    error "LATEST_DIAG_STALE_COUNTER_NET_NOT_UNIQUE=$stale_camera_diag_net"
}
if {[llength $stale_camera_diag_net] == 1} {
    delete_bd_objs $stale_camera_diag_net
}
foreach cell_name {axis_rgb24_to_32_0 eth_stream_0} {
    set old_cell [get_bd_cells -quiet $cell_name]
    if {[llength $old_cell] != 1} { error "LATEST_DIAG_OLD_CELL_NOT_UNIQUE=$cell_name:$old_cell" }
    delete_bd_objs $old_cell
}
set old_owner_diag [get_bd_cells -quiet latest_frame_owner_diag_0]
if {[llength $old_owner_diag] == 1} { delete_bd_objs $old_owner_diag }
create_bd_cell -type module -reference axis_rgb24_to_32_node_diag axis_rgb24_to_32_0
create_bd_cell -type module -reference eth_stream_stage3_axis_diag eth_stream_0
create_bd_cell -type module -reference latest_frame_owner_diag latest_frame_owner_diag_0
set_property CONFIG.ENABLE_RGMII_ILA {1} [get_bd_cells eth_stream_0]

# Restore the pixel/VDMA interface and camera clock/reset/fault wiring.
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_0/video_out] \
                    [get_bd_intf_pins axis_rgb24_to_32_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_rgb24_to_32_0/m_axis] \
                    [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] \
               [get_bd_pins axis_rgb24_to_32_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
               [get_bd_pins axis_rgb24_to_32_0/aresetn]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault] \
               [get_bd_pins latest_fault_or_0/Op2] \
               [get_bd_pins latest_diag_fault_concat/In1] \
               [get_bd_pins latest_diag_detail_concat/In1]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault_sof] \
               [get_bd_pins latest_diag_detail_concat/In3]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault_eol] \
               [get_bd_pins latest_diag_detail_concat/In4]

# Restore the Ethernet AXI-Lite/AXIS, clocks, board pins, and stream counters.
connect_bd_intf_net [get_bd_intf_pins axis_fifo_udp_0/M_AXIS] \
                    [get_bd_intf_pins eth_stream_0/dma_axis]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] \
                    [get_bd_intf_pins eth_stream_0/s_axi]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins eth_stream_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
               [get_bd_pins eth_stream_0/s_axi_aresetn] \
               [get_bd_pins eth_stream_0/sys_rst_n]
connect_bd_net [get_bd_pins u_clk_phase/clk_out1] [get_bd_pins eth_stream_0/rgmii_rxc]
foreach {port pin} {
    rgmii_rx_ctl rgmii_rx_ctl rgmii_rxd rgmii_rxd
    rgmii_txc rgmii_txc rgmii_tx_ctl rgmii_tx_ctl rgmii_txd rgmii_txd
    eth_rst_n eth_rst_n
} {
    if {[string match {rgmii_t*} $port] || $port eq {eth_rst_n}} {
        connect_bd_net [get_bd_pins eth_stream_0/$pin] [get_bd_ports $port]
    } else {
        connect_bd_net [get_bd_ports $port] [get_bd_pins eth_stream_0/$pin]
    }
}
connect_bd_net [get_bd_pins axis_flow_monitor_0/dbg_accepted_beats] \
               [get_bd_pins eth_stream_0/dma_mon_accepted_beats]
connect_bd_net [get_bd_pins axis_flow_monitor_0/dbg_tlasts] \
               [get_bd_pins eth_stream_0/dma_mon_tlasts]
connect_bd_net [get_bd_pins axis_flow_monitor_0/dbg_stall_cycles] \
               [get_bd_pins eth_stream_0/dma_mon_stall_cycles]
connect_bd_net [get_bd_pins latest_frame_owner_diag_0/diag_counters] \
               [get_bd_pins eth_stream_0/camera_axis_diag_counters]
connect_bd_net [get_bd_pins latest_diag_detail_concat/dout] \
               [get_bd_pins eth_stream_0/camera_axis_diag_faults]

# PL-owner node diagnostics: counters are generated in the 100 MHz FCLK
# domain and Gray-coded before the existing Ethernet CDC synchronizer.
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins latest_frame_owner_diag_0/clk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
               [get_bd_pins latest_frame_owner_diag_0/rst_n]
foreach {source sink} {
    vdma_frame_commit_axi_0/write_start latest_frame_owner_diag_0/write_start
    vdma_frame_commit_axi_0/commit latest_frame_owner_diag_0/commit
    vdma_frame_commit_axi_0/commit_generation latest_frame_owner_diag_0/commit_generation
    vdma_frame_commit_axi_0/error_count latest_frame_owner_diag_0/commit_error_count
    vdma_frame_commit_axi_0/fault latest_frame_owner_diag_0/commit_fault
    latest_frame_pacer_0/latest_slot latest_frame_owner_diag_0/latest_slot
    latest_frame_pacer_0/latest_generation latest_frame_owner_diag_0/latest_generation
    latest_frame_pacer_0/requested_generation latest_frame_owner_diag_0/requested_generation
    latest_frame_pacer_0/busy latest_frame_owner_diag_0/busy
    latest_frame_pacer_0/fault latest_frame_owner_diag_0/pacer_fault
    latest_frame_pacer_0/mm2s_fsync latest_frame_owner_diag_0/mm2s_fsync
    latest_frame_stream_gate_0/stream_done latest_frame_owner_diag_0/stream_done
    latest_frame_stream_gate_0/last_sent_generation latest_frame_owner_diag_0/last_sent_generation
    latest_frame_stream_gate_0/drop_count latest_frame_owner_diag_0/drop_count
    latest_frame_stream_gate_0/fault latest_frame_owner_diag_0/gate_fault
    vdma_mm2s_slot_monitor_0/read_slot latest_frame_owner_diag_0/read_slot
    vdma_mm2s_slot_monitor_0/fault latest_frame_owner_diag_0/read_fault
} { connect_bd_net [get_bd_pins $source] [get_bd_pins $sink] }

# Recreate the PS-visible Ethernet segment after replacing its module-ref
# cell. The ELF and legacy BSP both use the established 0x40000000 base.
assign_bd_address
set eth_seg [get_bd_addr_segs -quiet -of_objects [get_bd_intf_pins eth_stream_0/s_axi]]
if {[llength $eth_seg] != 1} { error "LATEST_ETH_AXI_SEGMENT_NOT_UNIQUE=$eth_seg" }
save_bd_design
set bd_fh [open $bd r]
set bd_text [read $bd_fh]
close $bd_fh
set seg_start [string first {"SEG_eth_stream_0_reg0"} $bd_text]
if {$seg_start < 0} { error "LATEST_ETH_AXI_SEGMENT_NOT_IN_SAVED_BD=$bd" }
set seg_text [string range $bd_text $seg_start [expr {$seg_start + 1200}]]
if {![regexp -nocase {"offset"[[:space:]]*:[[:space:]]*"([^"]+)"} $seg_text -> eth_offset]} {
    error "LATEST_ETH_AXI_OFFSET_NOT_IN_SAVED_BD=$bd"
}
puts "LATEST_ETH_AXI_SEGMENT=$eth_seg OFFSET=$eth_offset"
if {[string tolower $eth_offset] ne {0x40000000}} {
    error "LATEST_ETH_AXI_BASE_MISMATCH=$eth_offset"
}
save_bd_design
# The integration script generates the wrapper under the BD generated tree.
# Add that exact file explicitly so a fresh run cannot synthesize without the
# selected top when generated outputs were cleaned between builds.
set wrapper [file join $ROOT phase_b_project.gen sources_1 bd zynq hdl zynq_wrapper.v]
if {![file exists $wrapper]} { error "LATEST_WRAPPER_MISSING=$wrapper" }
if {[llength [get_files -quiet $wrapper]] == 0} { add_files -norecurse $wrapper }
set_property TOP_AUTO_SET 0 [get_filesets sources_1]
set_property TOP zynq_wrapper [get_filesets sources_1]
validate_bd_design
if {[get_property TOP [get_filesets sources_1]] ne {zynq_wrapper}} {
    error "LATEST_BUILD_WRONG_TOP=[get_property TOP [get_filesets sources_1]]"
}
if {[llength [get_bd_cells -quiet ila_latest_frame]] != 0} {
    error "LATEST_BUILD_STALE_SECOND_ILA"
}
if {[get_property CONFIG.ENABLE_RGMII_ILA [get_bd_cells eth_stream_0]] ne {1}} {
    error "LATEST_BUILD_RGMII_ILA_DISABLED"
}
foreach {pin width direction} {
    axis_rgb24_to_32_0/diag_counters 160 O
    latest_frame_owner_diag_0/diag_counters 160 O
    eth_stream_0/camera_axis_diag_counters 160 I
    eth_stream_0/camera_axis_diag_faults 5 I
} {
    set p [get_bd_pins -quiet $pin]
    if {[llength $p] != 1 || [get_property DIR $p] ne $direction ||
        [get_property LEFT $p] != ($width - 1) || [get_property RIGHT $p] != 0} {
        error "LATEST_DIAG_PIN_MISMATCH=$pin"
    }
}
foreach {source_pin sink_pin} {
    latest_frame_owner_diag_0/diag_counters eth_stream_0/camera_axis_diag_counters
    latest_diag_detail_concat/dout eth_stream_0/camera_axis_diag_faults
} {
    set source_nets [get_bd_nets -quiet -of_objects [get_bd_pins $source_pin]]
    set sink_nets [get_bd_nets -quiet -of_objects [get_bd_pins $sink_pin]]
    if {[llength $source_nets] != 1 || $source_nets ne $sink_nets} {
        error "LATEST_DIAG_CONNECTION_MISMATCH=$source_pin:$source_nets->$sink_pin:$sink_nets"
    }
}
generate_target all -force $bd
update_compile_order -fileset sources_1
set status_file [file join $OUT latest_frame_ip_status.rpt]
report_ip_status -file $status_file
set fh [open $status_file r]
set status_report [read $fh]
close $fh
if {[regexp -nocase {\|\s*[^|]+\s*\|\s*(Locked|Upgrade Required|Out-of-date|Missing)\s*\|} $status_report]} {
    error "LATEST_BUILD_STALE_IP_REPORT=$status_file"
}
puts "LATEST_BUILD_SOURCE_GATE_PASS"
if {[info exists ::env(LATEST_NODE_DIAG_PREFLIGHT_ONLY)] &&
    $::env(LATEST_NODE_DIAG_PREFLIGHT_ONLY) eq {1}} {
    puts "LATEST_NODE_DIAG_PREFLIGHT_ONLY_PASS"
    close_project
    exit
}
foreach run [get_runs -quiet] {
    set run_name [get_property NAME $run]
    if {[regexp {^zynq_(eth_stream|axis_rgb24_to_32)_0.*_synth_1$} $run_name]} {
        reset_run $run
    }
}
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
puts "LATEST_SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne {100%}} {
    error "LATEST_SYNTH_FAILED=[get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
puts "LATEST_IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] ne {100%}} {
    error "LATEST_IMPL_FAILED=[get_property STATUS [get_runs impl_1]]"
}
set impldir [get_property DIRECTORY [get_runs impl_1]]
set bit [file join $impldir zynq_wrapper.bit]
if {![file exists $bit]} { error "LATEST_BIT_MISSING=$bit" }
open_run impl_1
report_timing_summary -file [file join $OUT latest_frame_timing.rpt]
report_drc -file [file join $OUT latest_frame_drc.rpt]
report_route_status -file [file join $OUT latest_frame_route.rpt]
set setup_slack [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1] 0]]
set hold_slack [get_property SLACK [lindex [get_timing_paths -hold -max_paths 1] 0]]
puts "LATEST_TIMING setup=$setup_slack hold=$hold_slack"
if {$setup_slack < 0 || $hold_slack < 0} {
    error "LATEST_TIMING_FAILED setup=$setup_slack hold=$hold_slack"
}
file copy -force $bit [file join $OUT ${ARTIFACT_TAG}.bit]
write_debug_probes -force [file join $OUT ${ARTIFACT_TAG}.ltx]
puts "LATEST_BUILD_ID=$BUILD_ID"
puts "LATEST_BIT=[file join $OUT ${ARTIFACT_TAG}.bit]"
puts "LATEST_LTX=[file join $OUT ${ARTIFACT_TAG}.ltx]"
puts "LATEST_BUILD_COMPLETE=$BUILD_ID"
close_project
exit
