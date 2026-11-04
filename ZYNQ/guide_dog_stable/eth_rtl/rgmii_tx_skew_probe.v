`timescale 1ns/1ps

// RGMII transmitter used only by the phase-sweep board test.
// Data/control launch on data_clk; TXC is a separately phase-controlled clock.
module rgmii_tx_skew_probe (
  input wire data_clk,
  input wire txc_clk,
  input wire gmii_tx_en,
  input wire [7:0] gmii_txd,
  output wire rgmii_txc,
  output wire rgmii_tx_ctl,
  output wire [3:0] rgmii_txd
);
  assign rgmii_txc = txc_clk;

  ODDR2 #(.DDR_ALIGNMENT("C0"), .INIT(1'b0), .SRTYPE("ASYNC")) ctl_oddr (
    .Q(rgmii_tx_ctl), .C0(data_clk), .C1(~data_clk), .CE(1'b1),
    .D0(gmii_tx_en), .D1(gmii_tx_en), .R(1'b0), .S(1'b0)
  );

  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : data_oddr
      ODDR2 #(.DDR_ALIGNMENT("C0"), .INIT(1'b0), .SRTYPE("ASYNC")) oddr (
        .Q(rgmii_txd[i]), .C0(data_clk), .C1(~data_clk), .CE(1'b1),
        .D0(gmii_txd[i]), .D1(gmii_txd[i + 4]), .R(1'b0), .S(1'b0)
      );
    end
  endgenerate
endmodule
