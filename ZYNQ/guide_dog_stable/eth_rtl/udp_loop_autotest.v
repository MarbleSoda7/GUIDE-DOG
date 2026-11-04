`timescale 1ns/1ps

// UDP-loop derived probe: phase-shifted RGMII clock and fixed periodic payload.
module udp_loop_autotest (
  input wire sys_rst_n, input wire rgmii_rxc, input wire rgmii_rx_ctl,
  input wire [3:0] rgmii_rxd, output wire rgmii_txc, output wire rgmii_tx_ctl,
  output wire [3:0] rgmii_txd, output wire eth_rst_n, output wire [3:0] probe_led
);
  localparam [47:0] BOARD_MAC=48'h12_34_56_78_9a_bc;
  localparam [31:0] BOARD_IP=32'h0a_d4_d3_03;
  localparam [47:0] DES_MAC=48'hff_ff_ff_ff_ff_ff;
  localparam [31:0] DES_IP=32'h0a_d4_d3_02;
  wire clk_phase, gmii_rx_clk, gmii_rx_dv, gmii_tx_clk, gmii_tx_en, tx_done, tx_req;
  wire [7:0] gmii_rxd, gmii_txd;
  reg [26:0] period_count;
  reg [2:0] state;
  reg [26:0] state_count;
  reg tx_start;

  // Keep the PHY out of reset exactly as the known-good UDP loop example does.
  assign eth_rst_n=1'b1;
  assign probe_led={1'b0,state};
  zynq_u_clk_phase_0 phase_clock(.clk_in1(rgmii_rxc),.clk_out1(clk_phase));
  gmii_to_rgmii rgmii(
    .gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),
    .gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
    .rgmii_rxc(clk_phase),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
    .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
  always @(posedge gmii_tx_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin period_count<=0; state<=3'd0; state_count<=0; tx_start<=0; end
    else begin
      tx_start<=0;
      case (state)
        3'd0: begin state<=3'd1; state_count<=0; end // phase clock observed
        3'd1: if(state_count==27'd124999999) begin state<=3'd2; state_count<=0; end else state_count<=state_count+1'b1;
        3'd2: begin tx_start<=1'b1; state<=3'd3; state_count<=0; end // UDP start issued
        3'd3: if(gmii_tx_en) begin state<=3'd4; state_count<=0; end else if(state_count==27'd124999999) begin state<=3'd7; end else state_count<=state_count+1'b1;
        3'd4: if(tx_done) begin state<=3'd5; state_count<=0; end else if(state_count==27'd124999999) begin state<=3'd7; end else state_count<=state_count+1'b1;
        3'd5: state<=3'd5; // terminal success: exactly one frame was completed
        default: state<=3'd7; // terminal timeout: no further ambiguity
      endcase
    end
  end
  udp #(.BOARD_MAC(BOARD_MAC),.BOARD_IP(BOARD_IP),.DES_MAC(DES_MAC),.DES_IP(DES_IP)) udp_tx(
    .rst_n(sys_rst_n),.gmii_rx_clk(gmii_rx_clk),.gmii_rx_dv(gmii_rx_dv),.gmii_rxd(gmii_rxd),
    .gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
    .rec_pkt_done(),.rec_en(),.rec_data(),.rec_byte_num(),.tx_start_en(tx_start),
    .tx_data(32'h54455354),.tx_byte_num(16'd32),.tx_done(tx_done),.tx_req(tx_req));
endmodule
