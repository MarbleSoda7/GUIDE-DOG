`timescale 1ns/1ps

// RX conversion is unchanged. Only TXC-to-data timing is explicit here.
module gmii_to_rgmii_phase_sweep (
    output wire gmii_rx_clk, output wire gmii_rx_dv, output wire [7:0] gmii_rxd,
    output wire gmii_tx_clk, input wire gmii_tx_en, input wire [7:0] gmii_txd,
    input wire [1:0] txc_phase_req, output wire [1:0] txc_phase_active,
    output wire txc_locked, input wire rgmii_rxc, input wire rgmii_rx_ctl,
    input wire [3:0] rgmii_rxd, output wire rgmii_txc, output wire rgmii_tx_ctl,
    output wire [3:0] rgmii_txd
);
    assign gmii_tx_clk = gmii_rx_clk;
    rgmii_rx u_rgmii_rx (
        .gmii_rx_clk(gmii_rx_clk), .rgmii_rxc(rgmii_rxc),
        .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxd(rgmii_rxd),
        .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd)
    );
    rgmii_tx_phase_sweep u_rgmii_tx (
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .txc_phase_req(txc_phase_req), .txc_phase_active(txc_phase_active),
        .txc_locked(txc_locked), .rgmii_txc(rgmii_txc),
        .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd)
    );
endmodule
