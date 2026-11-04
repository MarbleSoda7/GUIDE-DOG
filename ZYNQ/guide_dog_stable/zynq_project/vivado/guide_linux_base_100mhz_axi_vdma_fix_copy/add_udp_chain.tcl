set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
open_project $proj
open_bd_design $bdfile

# === 地址空间扩展 ===
set_property CONFIG.NUM_SI {6} [get_bd_cells remap_hp_smc]
set_property CONFIG.NUM_MI {6} [get_bd_cells ps7_0_axi_periph]

# === 数据通路连线 (照抄 guide_dog) ===
# DMA 读 DDR -> 流监视 -> 异步FIFO -> eth_stream
connect_bd_intf_net [get_bd_intf_pins axi_dma_udp_0/M_AXIS_MM2S] [get_bd_intf_pins axis_flow_monitor_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_flow_monitor_0/m_axis] [get_bd_intf_pins axis_fifo_udp_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_fifo_udp_0/M_AXIS] [get_bd_intf_pins eth_stream_0/dma_axis]

# DMA 内存口 -> HP SmartConnect 第6路
connect_bd_intf_net [get_bd_intf_pins axi_dma_udp_0/M_AXI_MM2S] [get_bd_intf_pins remap_hp_smc/S05_AXI]

# AXI-Lite 控制
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M04_AXI] [get_bd_intf_pins axi_dma_udp_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M05_AXI] [get_bd_intf_pins eth_stream_0/s_axi]

# === FCLK0 时钟域 ===
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins axi_dma_udp_0/s_axi_lite_aclk] \
  [get_bd_pins axi_dma_udp_0/m_axi_mm2s_aclk] \
  [get_bd_pins axis_flow_monitor_0/aclk] \
  [get_bd_pins axis_fifo_udp_0/s_axis_aclk] \
  [get_bd_pins eth_stream_0/s_axi_aclk] \
  [get_bd_pins ps7_0_axi_periph/M04_ACLK] \
  [get_bd_pins ps7_0_axi_periph/M05_ACLK]

# === RGMII 时钟域 (clk_wiz 125MHz) ===
connect_bd_net [get_bd_pins u_clk_phase/clk_out1] [get_bd_pins eth_stream_0/rgmii_rxc]
connect_bd_net [get_bd_pins u_clk_phase/clk_out1] [get_bd_pins axis_fifo_udp_0/m_axis_aclk]

# === 复位 ===
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] \
  [get_bd_pins axi_dma_udp_0/axi_resetn] \
  [get_bd_pins axis_flow_monitor_0/aresetn] \
  [get_bd_pins axis_fifo_udp_0/s_axis_aresetn] \
  [get_bd_pins eth_stream_0/s_axi_aresetn] \
  [get_bd_pins eth_stream_0/sys_rst_n] \
  [get_bd_pins ps7_0_axi_periph/M04_ARESETN] \
  [get_bd_pins ps7_0_axi_periph/M05_ARESETN]

# === 流监视信号 -> eth_stream 诊断口 ===
connect_bd_net [get_bd_pins axis_flow_monitor_0/dbg_accepted_beats] [get_bd_pins eth_stream_0/dma_mon_accepted_beats]
connect_bd_net [get_bd_pins axis_flow_monitor_0/dbg_tlasts] [get_bd_pins eth_stream_0/dma_mon_tlasts]
connect_bd_net [get_bd_pins axis_flow_monitor_0/dbg_stall_cycles] [get_bd_pins eth_stream_0/dma_mon_stall_cycles]

# === RGMII 外部端口 ===
create_bd_port -dir I -type clk -freq_hz 125000000 rgmii_rxc
connect_bd_net [get_bd_ports rgmii_rxc] [get_bd_pins u_clk_phase/clk_in1]
create_bd_port -dir I rgmii_rx_ctl
connect_bd_net [get_bd_ports rgmii_rx_ctl] [get_bd_pins eth_stream_0/rgmii_rx_ctl]
create_bd_port -dir I -from 3 -to 0 rgmii_rxd
connect_bd_net [get_bd_ports rgmii_rxd] [get_bd_pins eth_stream_0/rgmii_rxd]
create_bd_port -dir O rgmii_txc
connect_bd_net [get_bd_ports rgmii_txc] [get_bd_pins eth_stream_0/rgmii_txc]
create_bd_port -dir O rgmii_tx_ctl
connect_bd_net [get_bd_ports rgmii_tx_ctl] [get_bd_pins eth_stream_0/rgmii_tx_ctl]
create_bd_port -dir O -from 3 -to 0 rgmii_txd
connect_bd_net [get_bd_ports rgmii_txd] [get_bd_pins eth_stream_0/rgmii_txd]
create_bd_port -dir O eth_rst_n
connect_bd_net [get_bd_ports eth_rst_n] [get_bd_pins eth_stream_0/eth_rst_n]

assign_bd_address
set rc [catch {validate_bd_design} vmsg]
puts "VALIDATE_RC=$rc"
if {$rc} { puts "VALIDATE_MSG=$vmsg"; error $vmsg }
save_bd_design
puts "UDP_CHAIN_OK"
close_project
exit