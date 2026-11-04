`timescale 1ns/1ps

// RGMII TX for the Stage5 physical-layer sweep. TXD and TX_CTL retain the
// legacy ODDR data launch clock; TXC is selectable between complete frames.
module rgmii_tx_phase_sweep (
    input wire gmii_tx_clk, input wire gmii_tx_en, input wire [7:0] gmii_txd,
    input wire [1:0] txc_phase_req, output wire [1:0] txc_phase_active,
    output wire txc_locked, output wire rgmii_txc, output wire rgmii_tx_ctl,
    output wire [3:0] rgmii_txd
);
    // Board-proven UDP-loop topology: TXC is the PHY-recovered GMII clock
    // itself.  The former "0-degree" MMCM path was a new physical clock path,
    // not an equivalent of this direct net, and every MMCM sweep setting lost
    // packets at RK.  RTL data launch remains unchanged below.
    assign rgmii_txc = gmii_tx_clk;
    assign txc_phase_active = 2'd0;
    assign txc_locked = 1'b1;

    ODDR2 #(.DDR_ALIGNMENT("C0"), .INIT(1'b0), .SRTYPE("ASYNC")) ctl_oddr (
        .Q(rgmii_tx_ctl), .C0(gmii_tx_clk), .C1(~gmii_tx_clk), .CE(1'b1),
        .D0(gmii_tx_en), .D1(gmii_tx_en), .R(1'b0), .S(1'b0)
    );
    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : txdata_bus
        ODDR2 #(.DDR_ALIGNMENT("C0"), .INIT(1'b0), .SRTYPE("ASYNC")) data_oddr (
            .Q(rgmii_txd[i]), .C0(gmii_tx_clk), .C1(~gmii_tx_clk), .CE(1'b1),
            .D0(gmii_txd[i]), .D1(gmii_txd[i + 4]), .R(1'b0), .S(1'b0)
        );
    end endgenerate
endmodule
