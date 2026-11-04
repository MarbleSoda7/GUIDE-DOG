`timescale 1ns/1ns
// TEST-015: UDP state-machine only.
// Keeps TEST-014 verified PHY/RGMII hardware chain, adds udp RX/TX state machines.
// Excludes BRAM, AXI business registers, PS↔ETH CDC and all transmission start events.
module eth_stream #(
 parameter integer C_BRAM_AW=10, parameter [47:0] P_BOARD_MAC=48'h12_34_56_78_9a_bc,
 parameter [31:0] P_BOARD_IP={8'd10,8'd212,8'd211,8'd3}, parameter [47:0] P_DES_MAC=48'hff_ff_ff_ff_ff_ff,
 parameter [31:0] P_DES_IP={8'd10,8'd212,8'd211,8'd2}
)(
 input wire s_axi_aclk,input wire s_axi_aresetn,input wire [5:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,input wire [31:0] s_axi_wdata,input wire s_axi_wvalid,output wire s_axi_wready,output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,input wire [5:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output wire s_axi_rvalid,input wire s_axi_rready,
 input wire rgmii_rxc,input wire rgmii_rx_ctl,input wire [3:0] rgmii_rxd,output wire rgmii_txc,output wire rgmii_tx_ctl,output wire [3:0] rgmii_txd,input wire sys_rst_n,output wire eth_rst_n
);
// Inert AXI-Lite response (no state, no AXI business function).
assign s_axi_awready=1'b1; assign s_axi_wready=1'b1; assign s_axi_bvalid=s_axi_awvalid&s_axi_wvalid;assign s_axi_bresp=2'b00;
assign s_axi_arready=1'b1; assign s_axi_rvalid=s_axi_arvalid;assign s_axi_rdata=32'd0;assign s_axi_rresp=2'b00;
// Same verified 670ms PHY reset-release path as TEST-014.
reg [26:0] phy_rst_count;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if(!s_axi_aresetn) phy_rst_count<=27'd0;
 else if(phy_rst_count!={27{1'b1}}) phy_rst_count<=phy_rst_count+1'b1;
end
assign eth_rst_n=(phy_rst_count=={27{1'b1}});
// Full RGMII RX/TX primitive chain.
wire gmii_rx_clk,gmii_rx_dv,gmii_tx_clk,gmii_tx_en;
wire [7:0] gmii_rxd,gmii_txd;
gmii_to_rgmii u_rgmii(
 .gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),
 .gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
 .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
// TEST-016 FINAL: explicit RAMB18E1 true dual-port, no inference ambiguity.
(* DONT_TOUCH = "true" *) reg [9:0] test_wr_addr;
(* DONT_TOUCH = "true" *) reg [9:0] test_rd_addr;
wire [15:0] test_rd_data;
(* DONT_TOUCH = "true" *) reg [15:0] test_rd_checksum;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
  if(!s_axi_aresetn) test_wr_addr <= 10'd0;
  else test_wr_addr <= test_wr_addr + 1'b1;
end
// Port B returns to real RGMII clock; its address is in upper physical half.
always @(posedge rgmii_rxc or negedge sys_rst_n) begin
  if(!sys_rst_n) begin
    test_rd_addr <= 10'd0;
    test_rd_checksum <= 16'd0;
  end else begin
    test_rd_addr <= test_rd_addr + 1'b1;
    test_rd_checksum <= test_rd_checksum ^ test_rd_data;
  end
end
(* DONT_TOUCH = "true" *) RAMB18E1 #(
 .RAM_MODE("TDP"),.READ_WIDTH_A(18),.READ_WIDTH_B(18),.WRITE_WIDTH_A(18),.WRITE_WIDTH_B(18),.WRITE_MODE_A("WRITE_FIRST"),.WRITE_MODE_B("READ_FIRST"),.DOA_REG(0),.DOB_REG(0),.INIT_A(18'h0),.INIT_B(18'h0),.SRVAL_A(18'h0),.SRVAL_B(18'h0),.SIM_COLLISION_CHECK("ALL")
) U_TEST_RAM(
 .CLKARDCLK(s_axi_aclk),.ENARDEN(1'b1),.REGCEAREGCE(1'b0),.WEA(2'b11),.ADDRARDADDR({1'b0,test_wr_addr[8:0],4'b0000}),.DIADI({6'h15,test_wr_addr}),.DIPADIP(2'b00),.DOADO(),.DOPADOP(),.RSTRAMARSTRAM(1'b0),.RSTREGARSTREG(1'b0),
 .CLKBWRCLK(rgmii_rxc),.ENBWREN(1'b0),.REGCEB(1'b0),.WEBWE(4'b0000),.ADDRBWRADDR({1'b1,test_rd_addr[8:0],4'b0000}),.DIBDI(16'b0),.DIPBDIP(2'b00),.DOBDO(test_rd_data),.DOPBDOP(),.RSTRAMB(1'b0),.RSTREGB(1'b0)
);

// UDP runs and receives frames, but cannot transmit: tx_start_en permanently low.
wire rec_pkt_done,rec_en,udp_tx_done,tx_req;
wire [31:0] rec_data;
wire [15:0] rec_byte_num;
(* DONT_TOUCH="true" *) udp #(
 .BOARD_MAC(P_BOARD_MAC),.BOARD_IP(P_BOARD_IP),.DES_MAC(P_DES_MAC),.DES_IP(P_DES_IP)
) u_udp(
 .rst_n(sys_rst_n),.gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),
 .gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
 .rec_pkt_done(rec_pkt_done),.rec_en(rec_en),.rec_data(rec_data),.rec_byte_num(rec_byte_num),
 .tx_start_en(1'b0),.tx_data(32'd0),.tx_byte_num(16'd0),.tx_done(udp_tx_done),.tx_req(tx_req));
endmodule