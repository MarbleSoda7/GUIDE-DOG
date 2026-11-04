`timescale 1ns/1ps

module rgmii_phase_sweep_top (
  inout [14:0] DDR_addr, inout [2:0] DDR_ba, inout DDR_cas_n, inout DDR_ck_n, inout DDR_ck_p,
  inout DDR_cke, inout DDR_cs_n, inout [3:0] DDR_dm, inout [31:0] DDR_dq, inout [3:0] DDR_dqs_n,
  inout [3:0] DDR_dqs_p, inout DDR_odt, inout DDR_ras_n, inout DDR_reset_n, inout DDR_we_n,
  inout FIXED_IO_ddr_vrn, inout FIXED_IO_ddr_vrp, inout [53:0] FIXED_IO_mio, inout FIXED_IO_ps_clk,
  inout FIXED_IO_ps_porb, inout FIXED_IO_ps_srstb, input rgmii_rxc, input rgmii_rx_ctl, input [3:0] rgmii_rxd,
  output rgmii_tx_ctl, output rgmii_txc, output [3:0] rgmii_txd, output eth_rst_n, output [3:0] led
);
  wire clk100, rst100n;
  wire [1:0] gpio_o, gpio_t;
  zynq_processing_system7_0_0 ps7 (
    .GPIO_I(2'b00), .GPIO_O(gpio_o), .GPIO_T(gpio_t), .FCLK_CLK0(clk100), .FCLK_RESET0_N(rst100n),
    .MIO(FIXED_IO_mio), .DDR_Addr(DDR_addr), .DDR_BankAddr(DDR_ba), .DDR_CAS_n(DDR_cas_n),
    .DDR_Clk_n(DDR_ck_n), .DDR_Clk(DDR_ck_p), .DDR_CKE(DDR_cke), .DDR_CS_n(DDR_cs_n), .DDR_DM(DDR_dm),
    .DDR_DQ(DDR_dq), .DDR_DQS_n(DDR_dqs_n), .DDR_DQS(DDR_dqs_p), .DDR_ODT(DDR_odt), .DDR_RAS_n(DDR_ras_n),
    .DDR_DRSTB(DDR_reset_n), .DDR_WEB(DDR_we_n), .DDR_VRN(FIXED_IO_ddr_vrn), .DDR_VRP(FIXED_IO_ddr_vrp),
    .PS_CLK(FIXED_IO_ps_clk), .PS_PORB(FIXED_IO_ps_porb), .PS_SRSTB(FIXED_IO_ps_srstb)
  );
  rgmii_phase_sweep_autotest probe (
    .sys_rst_n(rst100n), .rgmii_rxc(rgmii_rxc), .rgmii_txc(rgmii_txc),
    .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd), .eth_rst_n(eth_rst_n), .probe_led(led)
  );
endmodule
