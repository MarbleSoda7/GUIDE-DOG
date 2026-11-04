`timescale 1ns/1ns
// eth_stream.v — TEST-012 RGMII 原语链二分
// 保留: gmii_to_rgmii（IDDR/ODDR）及其相移RGMII时钟
// 移除: UDP、BRAM、CDC、PHY复位业务、AXI业务逻辑
module eth_stream #(
 parameter integer C_BRAM_AW=10, parameter [47:0] P_BOARD_MAC=48'h12_34_56_78_9a_bc,
 parameter [31:0] P_BOARD_IP={8'd10,8'd212,8'd211,8'd3}, parameter [47:0] P_DES_MAC=48'hff_ff_ff_ff_ff_ff,
 parameter [31:0] P_DES_IP={8'd10,8'd212,8'd211,8'd2}
)(
 input wire s_axi_aclk,input wire s_axi_aresetn,input wire [5:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,input wire [31:0] s_axi_wdata,input wire s_axi_wvalid,output wire s_axi_wready,output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,input wire [5:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output wire s_axi_rvalid,input wire s_axi_rready,
 input wire rgmii_rxc,input wire rgmii_rx_ctl,input wire [3:0] rgmii_rxd,output wire rgmii_txc,output wire rgmii_tx_ctl,output wire [3:0] rgmii_txd,input wire sys_rst_n,output wire eth_rst_n
);
// 静默AXI应答
assign s_axi_awready=1'b1; assign s_axi_wready=1'b1; assign s_axi_bvalid=s_axi_awvalid&s_axi_wvalid; assign s_axi_bresp=2'b00;
assign s_axi_arready=1'b1; assign s_axi_rvalid=s_axi_arvalid; assign s_axi_rdata=32'd0; assign s_axi_rresp=2'b00;
// RGMII原语链：接收IDDR仍工作；发送ODDR发送恒定0，不接UDP业务。
wire gmii_rx_clk,gmii_rx_dv,gmii_tx_clk;
wire [7:0] gmii_rxd;
wire [7:0] gmii_txd=8'h00;
gmii_to_rgmii u_gmii(
 .gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),
 .gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(1'b0),.gmii_txd(gmii_txd),
 .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
assign eth_rst_n=1'b0;
endmodule