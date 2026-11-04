`timescale 1ns/1ps
// Minimal physical-path test. Sends a fixed UDP payload without AXI/DMA/BRAM.
module eth_stream #(
 parameter integer C_BRAM_AW=10,
 parameter [47:0] P_BOARD_MAC=48'h12_34_56_78_9a_bc,
 parameter [31:0] P_BOARD_IP={8'd10,8'd212,8'd211,8'd3},
 parameter [47:0] P_DES_MAC=48'hff_ff_ff_ff_ff_ff,
 parameter [31:0] P_DES_IP={8'd10,8'd212,8'd211,8'd2}
)(
 input wire s_axi_aclk,input wire s_axi_aresetn,input wire [5:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire s_axi_wvalid,output wire s_axi_wready,output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,
 input wire [5:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output wire s_axi_rvalid,input wire s_axi_rready,
 input wire rgmii_rxc,input wire rgmii_rx_ctl,input wire [3:0] rgmii_rxd,output wire rgmii_txc,output wire rgmii_tx_ctl,output wire [3:0] rgmii_txd,
 input wire sys_rst_n,output wire eth_rst_n,
 input wire [63:0] dma_axis_tdata,input wire [7:0] dma_axis_tkeep,input wire dma_axis_tvalid,output wire dma_axis_tready,input wire dma_axis_tlast,
 input wire [31:0] dma_mon_accepted_beats,input wire [31:0] dma_mon_tlasts,input wire [31:0] dma_mon_stall_cycles
);
assign dma_axis_tready=1'b0;
assign s_axi_awready=1'b1; assign s_axi_wready=1'b1; assign s_axi_bvalid=s_axi_awvalid&s_axi_wvalid; assign s_axi_bresp=2'b00;
assign s_axi_arready=1'b1; assign s_axi_rvalid=s_axi_arvalid; assign s_axi_rdata=32'd0; assign s_axi_rresp=2'b00;

reg [26:0] phy_rst_count;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if(!s_axi_aresetn) phy_rst_count<=0;
 else if(phy_rst_count!={27{1'b1}}) phy_rst_count<=phy_rst_count+1'b1;
end
assign eth_rst_n=(phy_rst_count=={27{1'b1}});

wire gmii_rx_clk,gmii_rx_dv,gmii_tx_clk,gmii_tx_en,udp_tx_done,udp_tx_req;
wire [7:0] gmii_rxd,gmii_txd;
wire rec_pkt_done,rec_en;
wire [31:0] rec_data;
wire [15:0] rec_byte_num;
reg [31:0] settle_count;
reg tx_start_en;
wire tx_active = tx_start_en;

always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
 if(!sys_rst_n) begin settle_count<=0; tx_start_en<=0; end
 else begin
   tx_start_en<=0;
   if(!tx_active && !udp_tx_done) begin
     if(settle_count==32'd125000000) begin tx_start_en<=1; settle_count<=0; end
     else settle_count<=settle_count+1'b1;
   end
 end
end

gmii_to_rgmii u_rgmii(
 .gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),.gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
 .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),.rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));

udp #(.BOARD_MAC(P_BOARD_MAC),.BOARD_IP(P_BOARD_IP),.DES_MAC(P_DES_MAC),.DES_IP(P_DES_IP)) u_udp(
 .rst_n(sys_rst_n),.gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),.gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
 .rec_pkt_done(rec_pkt_done),.rec_en(rec_en),.rec_data(rec_data),.rec_byte_num(rec_byte_num),.tx_start_en(tx_start_en),.tx_data(32'h54455354),.tx_byte_num(16'd32),.tx_done(udp_tx_done),.tx_req(udp_tx_req));
endmodule
