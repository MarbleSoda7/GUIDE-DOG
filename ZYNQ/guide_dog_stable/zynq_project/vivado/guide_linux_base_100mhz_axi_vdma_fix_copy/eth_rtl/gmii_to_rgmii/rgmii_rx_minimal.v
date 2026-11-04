`timescale 1ns/1ps
module rgmii_rx(
  output wire gmii_rx_clk, output wire gmii_rx_dv, output wire [7:0] gmii_rxd,
  input wire rgmii_rxc, input wire rgmii_rx_ctl, input wire [3:0] rgmii_rxd
);
  wire [1:0] ctl;
  wire [7:0] data;
  IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),.INIT_Q1(1'b0),.INIT_Q2(1'b0),.SRTYPE("ASYNC")) ctl_ddr(
    .Q1(ctl[0]),.Q2(ctl[1]),.C(rgmii_rxc),.CE(1'b1),.D(rgmii_rx_ctl),.R(1'b0),.S(1'b0));
  genvar i;
  generate for (i=0;i<4;i=i+1) begin : ddr_nibble
    IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),.INIT_Q1(1'b0),.INIT_Q2(1'b0),.SRTYPE("ASYNC")) data_ddr(
      .Q1(data[4+i]),.Q2(data[i]),.C(rgmii_rxc),.CE(1'b1),.D(rgmii_rxd[i]),.R(1'b0),.S(1'b0));
  end endgenerate
  assign gmii_rx_clk=rgmii_rxc;
  assign gmii_rxd=data;
  assign gmii_rx_dv=ctl[0];
endmodule
