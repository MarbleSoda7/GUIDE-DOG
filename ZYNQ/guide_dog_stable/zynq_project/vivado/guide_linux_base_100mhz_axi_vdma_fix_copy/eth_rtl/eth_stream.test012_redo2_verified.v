`timescale 1ns/1ns
// TEST-012 REDO: RGMII-only, legally routed ODDR outputs.
// RX: 5 IDDR. TX: 5 ODDR. Every ODDR Q directly drives its top-level RGMII output.
// No UDP, BRAM, CDC, AXI business logic, no mode counter, no post-ODDR LUT/mux.
module eth_stream #(
 parameter integer C_BRAM_AW=10, parameter [47:0] P_BOARD_MAC=48'h12_34_56_78_9a_bc,
 parameter [31:0] P_BOARD_IP={8'd10,8'd212,8'd211,8'd3}, parameter [47:0] P_DES_MAC=48'hff_ff_ff_ff_ff_ff,
 parameter [31:0] P_DES_IP={8'd10,8'd212,8'd211,8'd2}
)(
 input wire s_axi_aclk,input wire s_axi_aresetn,input wire [5:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,input wire [31:0] s_axi_wdata,input wire s_axi_wvalid,output wire s_axi_wready,output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,input wire [5:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output wire s_axi_rvalid,input wire s_axi_rready,
 input wire rgmii_rxc,input wire rgmii_rx_ctl,input wire [3:0] rgmii_rxd,output wire rgmii_txc,output wire rgmii_tx_ctl,output wire [3:0] rgmii_txd,input wire sys_rst_n,output wire eth_rst_n
);
// Inert AXI response only; no PS-controlled state.
assign s_axi_awready=1'b1; assign s_axi_wready=1'b1; assign s_axi_bvalid=s_axi_awvalid&s_axi_wvalid; assign s_axi_bresp=2'b00;
assign s_axi_arready=1'b1; assign s_axi_rvalid=s_axi_arvalid; assign s_axi_rdata=32'd0; assign s_axi_rresp=2'b00;
assign eth_rst_n=1'b0;
// RX IDDRs kept, output unconsumed by design.
wire [1:0] rxctl_q; wire [7:0] rxd_q;
(* DONT_TOUCH="true" *) IDDR2 #(.DDR_ALIGNMENT("C0"),.INIT_Q0(1'b0),.INIT_Q1(1'b0),.SRTYPE("ASYNC")) U_RX_CTL(
 .Q0(rxctl_q[0]),.Q1(rxctl_q[1]),.C0(rgmii_rxc),.C1(~rgmii_rxc),.CE(1'b1),.D(rgmii_rx_ctl),.R(1'b0),.S(1'b0));
genvar i; generate for(i=0;i<4;i=i+1) begin:U_RX_DATA
 (* DONT_TOUCH="true" *) IDDR2 #(.DDR_ALIGNMENT("C0"),.INIT_Q0(1'b0),.INIT_Q1(1'b0),.SRTYPE("ASYNC")) U_IDDR(
 .Q0(rxd_q[4+i]),.Q1(rxd_q[i]),.C0(rgmii_rxc),.C1(~rgmii_rxc),.CE(1'b1),.D(rgmii_rxd[i]),.R(1'b0),.S(1'b0));
end endgenerate
// TX clock is directly sourced from input clock; this matches original RGMII topology.
assign rgmii_txc=rgmii_rxc;
// Legal direct primitive-to-port topology. ODDRs continuously emit zero on both edges.
(* DONT_TOUCH="true" *) ODDR2 #(.DDR_ALIGNMENT("C0"),.INIT(1'b0),.SRTYPE("ASYNC")) U_TX_CTL(
 .Q(rgmii_tx_ctl),.C0(rgmii_rxc),.C1(~rgmii_rxc),.CE(1'b1),.D0(1'b0),.D1(1'b0),.R(1'b0),.S(1'b0));
generate for(i=0;i<4;i=i+1) begin:U_TX_DATA
 (* DONT_TOUCH="true" *) ODDR2 #(.DDR_ALIGNMENT("C0"),.INIT(1'b0),.SRTYPE("ASYNC")) U_ODDR(
 .Q(rgmii_txd[i]),.C0(rgmii_rxc),.C1(~rgmii_rxc),.CE(1'b1),.D0(1'b0),.D1(1'b0),.R(1'b0),.S(1'b0));
end endgenerate
endmodule