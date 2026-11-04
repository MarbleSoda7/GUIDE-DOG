`timescale 1ns/1ps
// Revision-specific module reference prevents reuse of the old observer OOC.
module vdma_frame_commit_axi_restart_v1 #(
    parameter [31:0] FRAME_BASE = 32'h1100_0000,
    parameter [31:0] FRAME_BYTES = 32'd1152000,
    parameter integer QUEUE_LOG2 = 5
) (
    input wire clk, rst_n,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi AWADDR", X_INTERFACE_MODE = "monitor" *) input wire [31:0] awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi AWLEN" *) input wire [7:0] awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi AWSIZE" *) input wire [2:0] awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi AWVALID" *) input wire awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi AWREADY" *) input wire awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi WDATA" *) input wire [63:0] wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi WVALID" *) input wire wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi WREADY" *) input wire wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi BRESP" *) input wire [1:0] bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi BVALID" *) input wire bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_axi BREADY" *) input wire bready,
    output wire write_start, output wire [1:0] write_start_slot,
    output wire commit, output wire [1:0] commit_slot,
    output wire [31:0] commit_generation, error_count,
    output wire fault
);
    vdma_frame_commit_axi #(.FRAME_BASE(FRAME_BASE), .FRAME_BYTES(FRAME_BYTES),
                           .QUEUE_LOG2(QUEUE_LOG2)) u_commit (
        .clk(clk), .rst_n(rst_n), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awvalid(awvalid), .awready(awready), .wdata(wdata),
        .wvalid(wvalid), .wready(wready), .bresp(bresp),
        .bvalid(bvalid), .bready(bready), .write_start(write_start),
        .write_start_slot(write_start_slot), .commit(commit),
        .commit_slot(commit_slot), .commit_generation(commit_generation),
        .error_count(error_count), .fault(fault)
    );
endmodule
