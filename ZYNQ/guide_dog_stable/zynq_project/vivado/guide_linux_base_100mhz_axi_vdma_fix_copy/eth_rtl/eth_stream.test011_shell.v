`timescale 1ns/1ns
// eth_stream.v — TEST-011 静默空壳
// 保留通信 BD/RGMII 引脚/u_clk_phase/XDC，移除 UDP、BRAM、CDC、AXI业务逻辑。
// 用于分离“eth_stream业务RTL”与“新增RGMII时钟/约束/引脚”对HDMI的影响。
module eth_stream #(
    parameter integer C_BRAM_AW = 10,
    parameter [47:0] P_BOARD_MAC = 48'h12_34_56_78_9a_bc,
    parameter [31:0] P_BOARD_IP  = {8'd10,8'd212,8'd211,8'd3},
    parameter [47:0] P_DES_MAC   = 48'hff_ff_ff_ff_ff_ff,
    parameter [31:0] P_DES_IP    = {8'd10,8'd212,8'd211,8'd2}
)(
    input wire s_axi_aclk, input wire s_axi_aresetn,
    input wire [5:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output wire s_axi_bvalid, input wire s_axi_bready,
    input wire [5:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
    output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp, output wire s_axi_rvalid, input wire s_axi_rready,
    input wire rgmii_rxc, input wire rgmii_rx_ctl, input wire [3:0] rgmii_rxd,
    output wire rgmii_txc, output wire rgmii_tx_ctl, output wire [3:0] rgmii_txd,
    input wire sys_rst_n, output wire eth_rst_n
);
// 安静、安全的 AXI-Lite 从机：仅保证任何意外访问不会挂总线；状态读回0。
assign s_axi_awready = 1'b1;
assign s_axi_wready  = 1'b1;
assign s_axi_bvalid  = s_axi_awvalid & s_axi_wvalid;
assign s_axi_bresp   = 2'b00;
assign s_axi_arready = 1'b1;
assign s_axi_rvalid  = s_axi_arvalid;
assign s_axi_rresp   = 2'b00;
assign s_axi_rdata   = 32'd0;
// PHY 保持复位，静默RGMII输出；不实例化任何以太网时钟域逻辑。
assign eth_rst_n     = 1'b0;
assign rgmii_txc     = 1'b0;
assign rgmii_tx_ctl  = 1'b0;
assign rgmii_txd     = 4'b0000;
endmodule