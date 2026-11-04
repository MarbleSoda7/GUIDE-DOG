`timescale 1ns/1ns

// Unique module-ref name for Stage 3A. The wrapper prevents Vivado from
// reusing the old eth_stream module-ref port cache.
module eth_stream_stage3 #(
    parameter integer C_BRAM_AW = 10,
    parameter [47:0] P_BOARD_MAC = 48'h12_34_56_78_9a_bc,
    parameter [31:0] P_BOARD_IP  = {8'd10, 8'd212, 8'd211, 8'd3},
    parameter [47:0] P_DES_MAC   = 48'hff_ff_ff_ff_ff_ff,
    parameter [31:0] P_DES_IP    = {8'd10, 8'd212, 8'd211, 8'd2}
)(
    input wire s_axi_aclk, input wire s_axi_aresetn,
    input wire [5:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output wire s_axi_bvalid, input wire s_axi_bready,
    input wire [5:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
    output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid, input wire s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 rgmii_rxc CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 125000000, PHASE 210.0" *)
    input wire rgmii_rxc, input wire rgmii_rx_ctl, input wire [3:0] rgmii_rxd,
    output wire rgmii_txc, output wire rgmii_tx_ctl, output wire [3:0] rgmii_txd,
    input wire sys_rst_n, output wire eth_rst_n,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_axis TDATA" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME dma_axis, TDATA_NUM_BYTES 8, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 125000000, PHASE 210.0, ASSOCIATED_CLK rgmii_rxc" *)
    input wire [63:0] dma_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_axis TKEEP" *)
    input wire [7:0] dma_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_axis TVALID" *)
    input wire dma_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_axis TREADY" *)
    output wire dma_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 dma_axis TLAST" *)
    input wire dma_axis_tlast,
    input wire [31:0] dma_mon_accepted_beats, input wire [31:0] dma_mon_tlasts,
    input wire [31:0] dma_mon_stall_cycles
);
    eth_stream #(
        .C_BRAM_AW(C_BRAM_AW), .P_BOARD_MAC(P_BOARD_MAC), .P_BOARD_IP(P_BOARD_IP),
        .P_DES_MAC(P_DES_MAC), .P_DES_IP(P_DES_IP)
    ) u_eth_stream (
        .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready), .rgmii_rxc(rgmii_rxc), .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_rxd(rgmii_rxd), .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl),
        .rgmii_txd(rgmii_txd), .sys_rst_n(sys_rst_n), .eth_rst_n(eth_rst_n),
        .dma_axis_tdata(dma_axis_tdata), .dma_axis_tkeep(dma_axis_tkeep),
        .dma_axis_tvalid(dma_axis_tvalid), .dma_axis_tready(dma_axis_tready),
        .dma_axis_tlast(dma_axis_tlast), .dma_mon_accepted_beats(dma_mon_accepted_beats),
        .dma_mon_tlasts(dma_mon_tlasts), .dma_mon_stall_cycles(dma_mon_stall_cycles)
    );
endmodule
