// ============================================================
// zynq_eth_stream_0_0.v — BD OOC 包装层
// BD 的 synth/zynq.v 实例化 zynq_eth_stream_0_0 (IP 包装名);
// 真实逻辑在同目录 eth_stream.v (module_ref 直接引用)
// 此包装确保非工程模式综合能解析, 且永远使用当前源码。
// ============================================================
module zynq_eth_stream_0_0 #(
    parameter integer C_BRAM_AW = 10,
    parameter [47:0] P_BOARD_MAC = 48'h12_34_56_78_9a_bc,
    parameter [31:0] P_BOARD_IP  = {8'd10, 8'd212, 8'd211, 8'd3},
    parameter [47:0] P_DES_MAC   = 48'hff_ff_ff_ff_ff_ff,
    parameter [31:0] P_DES_IP    = {8'd10, 8'd212, 8'd211, 8'd2}
)(
    input  wire        s_axi_aclk    ,
    input  wire        s_axi_aresetn ,
    input  wire [5:0]  s_axi_awaddr  ,
    input  wire        s_axi_awvalid ,
    output wire        s_axi_awready ,
    input  wire [31:0] s_axi_wdata   ,
    input  wire        s_axi_wvalid  ,
    output wire        s_axi_wready  ,
    output wire [1:0]  s_axi_bresp   ,
    output wire        s_axi_bvalid  ,
    input  wire        s_axi_bready  ,
    input  wire [5:0]  s_axi_araddr  ,
    input  wire        s_axi_arvalid ,
    output wire        s_axi_arready ,
    output wire [31:0] s_axi_rdata   ,
    output wire [1:0]  s_axi_rresp   ,
    output wire        s_axi_rvalid  ,
    input  wire        s_axi_rready  ,
    input  wire        rgmii_rxc     ,
    input  wire        rgmii_rx_ctl  ,
    input  wire [3:0]  rgmii_rxd     ,
    output wire        rgmii_txc     ,
    output wire        rgmii_tx_ctl  ,
    output wire [3:0]  rgmii_txd     ,
    input  wire        sys_rst_n     ,
    output wire        eth_rst_n     ,
    input  wire [63:0] dma_axis_tdata,
    input  wire [7:0]  dma_axis_tkeep,
    input  wire        dma_axis_tvalid,
    output wire        dma_axis_tready,
    input  wire        dma_axis_tlast
);
    eth_stream #(
        .C_BRAM_AW   (C_BRAM_AW),
        .P_BOARD_MAC (P_BOARD_MAC),
        .P_BOARD_IP  (P_BOARD_IP ),
        .P_DES_MAC   (P_DES_MAC  ),
        .P_DES_IP    (P_DES_IP   )
    ) u_eth_stream (
        .s_axi_aclk    (s_axi_aclk),
        .s_axi_aresetn (s_axi_aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .rgmii_rxc     (rgmii_rxc),
        .rgmii_rx_ctl  (rgmii_rx_ctl),
        .rgmii_rxd     (rgmii_rxd),
        .rgmii_txc     (rgmii_txc),
        .rgmii_tx_ctl  (rgmii_tx_ctl),
        .rgmii_txd     (rgmii_txd),
        .sys_rst_n     (sys_rst_n),
        .eth_rst_n     (eth_rst_n),
        .dma_axis_tdata(dma_axis_tdata),
        .dma_axis_tkeep(dma_axis_tkeep),
        .dma_axis_tvalid(dma_axis_tvalid),
        .dma_axis_tready(dma_axis_tready),
        .dma_axis_tlast(dma_axis_tlast)
    );
endmodule