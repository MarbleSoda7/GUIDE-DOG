`timescale 1ns/1ps

// Sends one fixed UDP packet at each TXC phase: 0, 90, 180, 270 degrees.
// Payload starts "PH", followed by the phase index, so RK tcpdump identifies it.
module rgmii_phase_sweep_autotest (
  input wire sys_rst_n,
  input wire rgmii_rxc,
  output wire rgmii_txc,
  output wire rgmii_tx_ctl,
  output wire [3:0] rgmii_txd,
  output wire eth_rst_n,
  output wire [3:0] probe_led
);
  localparam [47:0] BOARD_MAC = 48'h12_34_56_78_9a_bc;
  localparam [31:0] BOARD_IP = 32'h0a_d4_d3_03;
  localparam [47:0] DES_MAC = 48'hff_ff_ff_ff_ff_ff;
  localparam [31:0] DES_IP = 32'h0a_d4_d3_02;
  localparam [26:0] STARTUP_CYCLES = 27'd125000000;
  localparam [26:0] SETTLE_CYCLES = 27'd62500000;

  wire clkfb, clk0_raw, clk90_raw, clk180_raw, clk270_raw;
  wire data_clk, txc0_clk, txc90_clk, txc180_clk, txc270_clk;
  wire txc_clk, mmcm_locked;
  wire gmii_tx_en, tx_done, tx_req;
  wire [7:0] gmii_txd;
  reg [1:0] phase_idx;
  reg [2:0] state;
  reg [26:0] count;
  reg tx_start;

  assign eth_rst_n = 1'b1;
  // High two bits are the current phase index; low bits expose test progress.
  assign probe_led = {phase_idx, state[1:0]};

  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(8.0), .CLKFBOUT_MULT_F(8.0),
    .DIVCLK_DIVIDE(1), .CLKOUT0_DIVIDE_F(8.0), .CLKOUT0_PHASE(0.0),
    .CLKOUT1_DIVIDE(8), .CLKOUT1_PHASE(90.0),
    .CLKOUT2_DIVIDE(8), .CLKOUT2_PHASE(180.0),
    .CLKOUT3_DIVIDE(8), .CLKOUT3_PHASE(270.0),
    .STARTUP_WAIT("FALSE")
  ) mmcm (
    .CLKIN1(rgmii_rxc), .CLKFBIN(clkfb), .RST(~sys_rst_n), .PWRDWN(1'b0),
    .CLKFBOUT(clkfb), .CLKOUT0(clk0_raw), .CLKOUT1(clk90_raw),
    .CLKOUT2(clk180_raw), .CLKOUT3(clk270_raw), .LOCKED(mmcm_locked)
  );
  BUFG data_buf(.I(clk0_raw), .O(data_clk));
  BUFG txc0_buf(.I(clk0_raw), .O(txc0_clk));
  BUFG txc90_buf(.I(clk90_raw), .O(txc90_clk));
  BUFG txc180_buf(.I(clk180_raw), .O(txc180_clk));
  BUFG txc270_buf(.I(clk270_raw), .O(txc270_clk));
  // The phase selector changes only after a packet has completed and the
  // link has idled for SETTLE_CYCLES.  Keep it outside the global-clock tree:
  // cascading BUFGMUX cells is illegal on this device and prevents placement.
  assign txc_clk = (phase_idx == 2'd0) ? txc0_clk :
                   (phase_idx == 2'd1) ? txc90_clk :
                   (phase_idx == 2'd2) ? txc180_clk : txc270_clk;

  always @(posedge data_clk or negedge sys_rst_n) begin
    if (!sys_rst_n || !mmcm_locked) begin
      phase_idx <= 2'd0;
      state <= 3'd0;
      count <= 27'd0;
      tx_start <= 1'b0;
    end else begin
      tx_start <= 1'b0;
      case (state)
        3'd0: if (count == STARTUP_CYCLES - 1'b1) begin
          count <= 0;
          state <= 3'd1;
        end else count <= count + 1'b1;
        3'd1: if (count == SETTLE_CYCLES - 1'b1) begin
          count <= 0;
          state <= 3'd2;
        end else count <= count + 1'b1;
        3'd2: begin
          tx_start <= 1'b1;
          count <= 0;
          state <= 3'd3;
        end
        3'd3: if (gmii_tx_en) begin
          count <= 0;
          state <= 3'd4;
        end else if (count == STARTUP_CYCLES - 1'b1) state <= 3'd7;
        else count <= count + 1'b1;
        3'd4: if (tx_done) begin
          count <= 0;
          state <= 3'd5;
        end else if (count == STARTUP_CYCLES - 1'b1) state <= 3'd7;
        else count <= count + 1'b1;
        3'd5: if (count == SETTLE_CYCLES - 1'b1) begin
          count <= 0;
          if (phase_idx == 2'd3) state <= 3'd6;
          else begin
            phase_idx <= phase_idx + 1'b1;
            state <= 3'd1;
          end
        end else count <= count + 1'b1;
        default: state <= state;
      endcase
    end
  end

  udp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP), .DES_MAC(DES_MAC), .DES_IP(DES_IP)) udp_tx (
    .rst_n(sys_rst_n), .gmii_rx_clk(data_clk), .gmii_rx_dv(1'b0), .gmii_rxd(8'd0),
    .gmii_tx_clk(data_clk), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
    .rec_pkt_done(), .rec_en(), .rec_data(), .rec_byte_num(), .tx_start_en(tx_start),
    .tx_data({8'h50, 8'h48, 6'd0, phase_idx, 8'ha5}), .tx_byte_num(16'd32),
    .tx_done(tx_done), .tx_req(tx_req)
  );

  rgmii_tx_skew_probe tx_ddr (
    .data_clk(data_clk), .txc_clk(txc_clk), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
    .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd)
  );
endmodule
