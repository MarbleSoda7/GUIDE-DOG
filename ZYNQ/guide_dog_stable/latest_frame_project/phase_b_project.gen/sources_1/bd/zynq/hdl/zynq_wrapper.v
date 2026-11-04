//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2026.1 (win64) Build 6511674 Tue Jun 16 11:02:23 MDT 2026
//Date        : Thu Oct  1 16:42:29 2026
//Host        : LY running 64-bit major release  (build 9200)
//Command     : generate_target zynq_wrapper.bd
//Design      : zynq_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module zynq_wrapper
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    cam_pdn_0,
    cam_rst_n,
    cam_sccb_tri_io,
    cam_xclk_0,
    eth_rst_n,
    led,
    ov5640_data,
    ov5640_href,
    ov5640_pclk,
    ov5640_vsync,
    rgmii_rx_ctl,
    rgmii_rxc,
    rgmii_rxd,
    rgmii_tx_ctl,
    rgmii_txc,
    rgmii_txd);
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  output cam_pdn_0;
  output cam_rst_n;
  inout [1:0]cam_sccb_tri_io;
  output cam_xclk_0;
  output eth_rst_n;
  output [3:0]led;
  input [7:0]ov5640_data;
  input ov5640_href;
  input ov5640_pclk;
  input ov5640_vsync;
  input rgmii_rx_ctl;
  input rgmii_rxc;
  input [3:0]rgmii_rxd;
  output rgmii_tx_ctl;
  output rgmii_txc;
  output [3:0]rgmii_txd;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire cam_pdn_0;
  wire cam_rst_n;
  wire [0:0]cam_sccb_tri_i_0;
  wire [1:1]cam_sccb_tri_i_1;
  wire [0:0]cam_sccb_tri_io_0;
  wire [1:1]cam_sccb_tri_io_1;
  wire [0:0]cam_sccb_tri_o_0;
  wire [1:1]cam_sccb_tri_o_1;
  wire [0:0]cam_sccb_tri_t_0;
  wire [1:1]cam_sccb_tri_t_1;
  wire cam_xclk_0;
  wire eth_rst_n;
  wire [3:0]led;
  wire [7:0]ov5640_data;
  wire ov5640_href;
  wire ov5640_pclk;
  wire ov5640_vsync;
  wire rgmii_rx_ctl;
  wire rgmii_rxc;
  wire [3:0]rgmii_rxd;
  wire rgmii_tx_ctl;
  wire rgmii_txc;
  wire [3:0]rgmii_txd;

  IOBUF cam_sccb_tri_iobuf_0
       (.I(cam_sccb_tri_o_0),
        .IO(cam_sccb_tri_io[0]),
        .O(cam_sccb_tri_i_0),
        .T(cam_sccb_tri_t_0));
  IOBUF cam_sccb_tri_iobuf_1
       (.I(cam_sccb_tri_o_1),
        .IO(cam_sccb_tri_io[1]),
        .O(cam_sccb_tri_i_1),
        .T(cam_sccb_tri_t_1));
  zynq zynq_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .cam_pdn_0(cam_pdn_0),
        .cam_rst_n(cam_rst_n),
        .cam_sccb_tri_i({cam_sccb_tri_i_1,cam_sccb_tri_i_0}),
        .cam_sccb_tri_o({cam_sccb_tri_o_1,cam_sccb_tri_o_0}),
        .cam_sccb_tri_t({cam_sccb_tri_t_1,cam_sccb_tri_t_0}),
        .cam_xclk_0(cam_xclk_0),
        .eth_rst_n(eth_rst_n),
        .led(led),
        .ov5640_data(ov5640_data),
        .ov5640_href(ov5640_href),
        .ov5640_pclk(ov5640_pclk),
        .ov5640_vsync(ov5640_vsync),
        .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_rxc(rgmii_rxc),
        .rgmii_rxd(rgmii_rxd),
        .rgmii_tx_ctl(rgmii_tx_ctl),
        .rgmii_txc(rgmii_txc),
        .rgmii_txd(rgmii_txd));
endmodule
