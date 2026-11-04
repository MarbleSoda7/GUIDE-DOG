set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
open_project $proj
open_bd_design $bdfile
set_property ip_repo_paths [list "D:/distortion_correction/vivado/guide_linux_base/ip_repo" "D:/distortion_correction/vivado/guide_linux_base/hls_ip_repo"] [current_project]
update_ip_catalog

# --- AXI DMA MM2S (照抄 guide_dog) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_udp_0
set_property -dict [list CONFIG.c_include_mm2s {1} CONFIG.c_include_s2mm {0} CONFIG.c_include_sg {0} CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_m_axis_mm2s_tdata_width {64}] [get_bd_cells axi_dma_udp_0]

# --- 流监视器 (module_ref) ---
create_bd_cell -type module -reference axis_flow_monitor axis_flow_monitor_0

# --- 异步 FIFO (照抄 guide_dog) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_fifo_udp_0
set_property -dict [list CONFIG.IS_ACLK_ASYNC {1} CONFIG.TDATA_NUM_BYTES {8} CONFIG.FIFO_DEPTH {2048} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_bd_cells axis_fifo_udp_0]

# --- UDP 组包+RGMII (module_ref, 照抄 guide_dog) ---
create_bd_cell -type module -reference eth_stream_stage3_diag eth_stream_0

# --- RGMII 时钟 (照抄 guide_dog: 125in -> 125out) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 u_clk_phase
set_property -dict [list CONFIG.PRIM_IN_FREQ {125} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} CONFIG.CLKOUT1_REQUESTED_PHASE {0.0} CONFIG.USE_LOCKED {false} CONFIG.USE_RESET {false}] [get_bd_cells u_clk_phase]

puts "=== DUMP_BEGIN ==="
foreach c {axi_dma_udp_0 axis_flow_monitor_0 axis_fifo_udp_0 eth_stream_0 u_clk_phase} {
  puts "---CELL $c---"
  foreach p [lsort [get_bd_pins $c/*]] { puts "PIN $p" }
  foreach i [lsort [get_bd_intf_pins $c/*]] { puts "INTF $i" }
}
puts "=== DUMP_END ==="
save_bd_design
close_project
exit
