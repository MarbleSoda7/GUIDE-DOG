# Isolate the proven cyclic baseline; never overwrite its bitstream or ELF.
set BASE [file normalize [file dirname [info script]]]
set OUT [file join $BASE latest_frame_project]
if {![file exists [file join $OUT latest_frame_project.xpr]]} {
    open_project [file join $BASE phase_b_project.xpr]
    save_project_as latest_frame_project $OUT
    close_project
}
# save_project_as copies stale generated XML and cached OOC products from the
# historical project. Remove only this newly created copy's derived outputs.
file copy -force [file join $BASE phase_b_project.srcs sources_1 bd zynq zynq.bd] \
                 [file join $OUT latest_frame_project.srcs sources_1 bd zynq zynq.bd]
foreach derived {latest_frame_project.gen latest_frame_project.cache latest_frame_project.runs latest_frame_project.ip_user_files phase_b_project.gen phase_b_project.runs} {
    set target [file join $OUT $derived]
    if {[file exists $target]} { file delete -force $target }
}
open_project [file join $OUT latest_frame_project.xpr]
set_property source_mgmt_mode All [current_project]
set obsolete [get_files -quiet *axi_s2mm_commit_bridge.v]
if {[llength $obsolete]} { remove_files $obsolete }
set bd [get_files -quiet */zynq.bd]
if {[llength $bd] != 1} { error "LATEST_BD_NOT_UNIQUE=$bd" }
foreach name {vdma_frame_commit_axi vdma_mm2s_slot_monitor latest_frame_pacer latest_frame_stream_gate axis_rgb24_to_32 axis_32_to_64 latest_frame_owner_diag} {
    set src [file join $BASE rtl ${name}.v]
    if {[llength [get_files -quiet $src]] == 0} { add_files -norecurse $src }
}
update_compile_order -fileset sources_1
open_bd_design $bd

# The installed BASIC license permits one ILA instance per design.  The
# Ethernet IP already contains the five-probe RGMII ILA used for this run;
# remove any stale standalone latest-frame ILA left by an earlier integration.
set stale_ila [get_bd_cells -quiet ila_latest_frame]
if {[llength $stale_ila]} { delete_bd_objs $stale_ila }

# S2MM dynamic master skips an active reader; MM2S dynamic slave follows
# completed stores, and an external FSYNC permits only a committed candidate.
set vdma [get_bd_cells axi_vdma_0]
set_property CONFIG.ENABLE_RGMII_ILA {1} [get_bd_cells eth_stream_0]
set_property -dict [list \
    CONFIG.c_include_mm2s {1} CONFIG.c_include_s2mm {1} \
    CONFIG.c_num_fstores {3} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_include_internal_genlock {1} \
    CONFIG.c_s2mm_genlock_mode {2} \
    CONFIG.c_mm2s_genlock_mode {3} \
    CONFIG.c_use_mm2s_fsync {1}] $vdma
set_property CONFIG.NUM_SI {4} [get_bd_cells axi_smc]
foreach name {vdma_frame_commit_axi vdma_mm2s_slot_monitor latest_frame_pacer latest_frame_stream_gate axis_rgb24_to_32 axis_32_to_64 latest_frame_owner_diag} {
    create_bd_cell -type module -reference $name ${name}_0
}
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 latest_enable_0
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells latest_enable_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 latest_fault_zero_0
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells latest_fault_zero_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 latest_fault_or_0
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 latest_fault_or_1
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 latest_diag_fault_concat
set_property -dict [list CONFIG.NUM_PORTS {3} CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {1}] [get_bd_cells latest_diag_fault_concat]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 latest_diag_detail_concat
set_property -dict [list CONFIG.NUM_PORTS {5} CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {1} CONFIG.IN3_WIDTH {1} CONFIG.IN4_WIDTH {1}] [get_bd_cells latest_diag_detail_concat]
foreach c {latest_fault_or_0 latest_fault_or_1} {
    set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {or}] [get_bd_cells $c]
}

set old [get_bd_intf_nets -quiet axi_dma_udp_0_M_AXIS_MM2S]
if {[llength $old] != 1} { error "LATEST_OLD_AXIS_NOT_FOUND=$old" }
disconnect_bd_intf_net $old [get_bd_intf_pins axis_flow_monitor_0/s_axis]
set write_bus [get_bd_intf_nets -quiet axi_vdma_0_M_AXI_S2MM]
if {[llength $write_bus] != 1} { error "LATEST_WRITE_BUS_NOT_FOUND=$write_bus" }
if {[llength [get_bd_intf_pins -quiet vdma_frame_commit_axi_0/mon_axi]] != 1} {
    error "LATEST_MONITOR_INTERFACE_NOT_INFERRED"
}
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins vdma_frame_commit_axi_0/mon_axi]
if {[llength [get_bd_intf_pins -quiet vdma_mm2s_slot_monitor_0/mon_axi]] != 1} {
    error "LATEST_READ_MONITOR_INTERFACE_NOT_INFERRED"
}
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] [get_bd_intf_pins vdma_mm2s_slot_monitor_0/mon_axi]
set camera_axis [get_bd_intf_nets -of_objects [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]]
if {[llength $camera_axis] != 1} { error "LATEST_CAMERA_AXIS_NOT_FOUND=$camera_axis" }
delete_bd_objs $camera_axis
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_0/video_out] [get_bd_intf_pins axis_rgb24_to_32_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_rgb24_to_32_0/m_axis] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins latest_frame_stream_gate_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins latest_frame_stream_gate_0/m_axis] [get_bd_intf_pins axis_32_to_64_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_32_to_64_0/m_axis] [get_bd_intf_pins axis_flow_monitor_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] [get_bd_intf_pins axi_smc/S03_AXI]

set clk [get_bd_pins processing_system7_0/FCLK_CLK0]
set rst [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]
foreach c {vdma_frame_commit_axi_0 vdma_mm2s_slot_monitor_0 latest_frame_pacer_0 latest_frame_stream_gate_0 latest_frame_owner_diag_0} {
    connect_bd_net $clk [get_bd_pins $c/clk]
    connect_bd_net $rst [get_bd_pins $c/rst_n]
}
connect_bd_net $clk [get_bd_pins axi_vdma_0/m_axi_mm2s_aclk] [get_bd_pins axi_vdma_0/m_axis_mm2s_aclk] [get_bd_pins axis_32_to_64_0/aclk]
connect_bd_net $rst [get_bd_pins axis_32_to_64_0/aresetn]
connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axis_rgb24_to_32_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axis_rgb24_to_32_0/aresetn]
connect_bd_net [get_bd_pins latest_enable_0/dout] [get_bd_pins latest_frame_pacer_0/enable]
connect_bd_net [get_bd_pins latest_fault_zero_0/dout] [get_bd_pins latest_fault_or_0/Op1]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault] [get_bd_pins latest_fault_or_0/Op2]
connect_bd_net [get_bd_pins latest_fault_or_0/Res] [get_bd_pins latest_fault_or_1/Op1]
# The MM2S slot monitor remains observable through ILA, but it is not a
# functional fatal source: VDMA can issue a startup prefetch before the first
# committed frame and that diagnostic condition must not deadlock the sender.
connect_bd_net [get_bd_pins latest_fault_zero_0/dout] [get_bd_pins latest_fault_or_1/Op2]

# Observe the VDMA write master before SmartConnect.  Commit is the final
# successful DDR B response, never the sensor VSYNC or VDMA frame pointer.
foreach {source sink} {
    vdma_frame_commit_axi_0/write_start latest_frame_stream_gate_0/write_start
    vdma_frame_commit_axi_0/write_start_slot latest_frame_stream_gate_0/write_start_slot
    vdma_frame_commit_axi_0/commit latest_frame_stream_gate_0/commit
    vdma_frame_commit_axi_0/commit_slot latest_frame_stream_gate_0/commit_slot
    vdma_frame_commit_axi_0/commit_generation latest_frame_stream_gate_0/commit_generation
    latest_fault_or_1/Res latest_frame_stream_gate_0/external_fault
    vdma_frame_commit_axi_0/commit latest_frame_pacer_0/commit
    vdma_frame_commit_axi_0/commit_slot latest_frame_pacer_0/commit_slot
    vdma_frame_commit_axi_0/commit_generation latest_frame_pacer_0/commit_generation
    latest_frame_stream_gate_0/fault latest_frame_pacer_0/external_fault
    latest_frame_stream_gate_0/stream_done latest_frame_pacer_0/stream_done
    latest_frame_pacer_0/latest_slot latest_frame_stream_gate_0/latest_slot
    latest_frame_pacer_0/latest_generation latest_frame_stream_gate_0/latest_generation
    latest_frame_pacer_0/mm2s_fsync axi_vdma_0/mm2s_fsync
    vdma_mm2s_slot_monitor_0/read_slot latest_frame_stream_gate_0/read_slot
} { connect_bd_net [get_bd_pins $source] [get_bd_pins $sink] }
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
# These packed diagnostic nets remain available to the PS diagnostic area;
# the sole hardware ILA is the five-probe RGMII instance inside eth_stream_0.
connect_bd_net [get_bd_pins vdma_frame_commit_axi_0/fault] [get_bd_pins latest_diag_fault_concat/In0]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault] [get_bd_pins latest_diag_fault_concat/In1]
connect_bd_net [get_bd_pins vdma_mm2s_slot_monitor_0/fault] [get_bd_pins latest_diag_fault_concat/In2]
connect_bd_net [get_bd_pins vdma_frame_commit_axi_0/fault] [get_bd_pins latest_diag_detail_concat/In0]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault] [get_bd_pins latest_diag_detail_concat/In1]
connect_bd_net [get_bd_pins vdma_mm2s_slot_monitor_0/fault] [get_bd_pins latest_diag_detail_concat/In2]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault_sof] [get_bd_pins latest_diag_detail_concat/In3]
connect_bd_net [get_bd_pins axis_rgb24_to_32_0/fault_eol] [get_bd_pins latest_diag_detail_concat/In4]
if {[get_property CONFIG.ENABLE_RGMII_ILA [get_bd_cells eth_stream_0]] ne {1}} {
    error "LATEST_RGMII_ILA_DISABLED"
}
assign_bd_address
validate_bd_design
save_bd_design
generate_target all $bd
set wrapper [make_wrapper -files $bd -top -force]
if {[llength [get_files -quiet $wrapper]] == 0} { add_files -norecurse $wrapper }
update_compile_order -fileset sources_1
set_property TOP_AUTO_SET 0 [get_filesets sources_1]
set_property TOP zynq_wrapper [get_filesets sources_1]
if {[get_property TOP [get_filesets sources_1]] ne {zynq_wrapper}} { error "LATEST_WRAPPER_TOP_NOT_SET" }
foreach {key expected} {
    CONFIG.c_include_mm2s 1 CONFIG.c_include_internal_genlock 1
    CONFIG.c_s2mm_genlock_mode 2 CONFIG.c_mm2s_genlock_mode 3
    CONFIG.c_use_mm2s_fsync 1
} {
    if {[get_property $key $vdma] ne $expected} { error "LATEST_VDMA_CONFIG_CHANGED=$key:[get_property $key $vdma]" }
}
puts "LATEST_FRAME_BD_VALIDATED=$bd"
close_project
exit
