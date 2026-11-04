`timescale 1ns/1ps
// Non-invasive AXI monitor: the actual DDR read address identifies the store.
// The first burst must begin at a configured frame-store base.
module vdma_mm2s_slot_monitor #(
    parameter [31:0] FRAME_BASE = 32'h1100_0000,
    parameter [31:0] FRAME_BYTES = 32'd1152000
) (
    input wire clk, rst_n,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi ARADDR", X_INTERFACE_MODE = "monitor" *) input wire [31:0] araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi ARLEN" *) input wire [7:0] arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi ARSIZE" *) input wire [2:0] arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi ARVALID" *) input wire arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi ARREADY" *) input wire arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi RDATA" *) input wire [63:0] rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi RVALID" *) input wire rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi RREADY" *) input wire rready,
    output reg [1:0] read_slot,
    output reg fault
);
    wire [31:0] span = FRAME_BYTES * 3;
    wire in_range = araddr >= FRAME_BASE && araddr < FRAME_BASE + span;
    wire [31:0] offset = araddr - FRAME_BASE;
    wire [1:0] slot = offset < FRAME_BYTES ? 2'd0 :
                      offset < FRAME_BYTES * 2 ? 2'd1 : 2'd2;
    wire [31:0] burst_bytes = ({24'd0, arlen} + 1) << arsize;
    wire [31:0] slot_end = FRAME_BASE + (slot + 32'd1) * FRAME_BYTES;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin read_slot <= 2'd3; fault <= 0; end
        else if (arvalid && arready) begin
            if (!in_range || burst_bytes == 0 ||
                araddr + burst_bytes > slot_end ||
                araddr + burst_bytes < araddr) fault <= 1;
            else read_slot <= slot;
        end
    end
endmodule
