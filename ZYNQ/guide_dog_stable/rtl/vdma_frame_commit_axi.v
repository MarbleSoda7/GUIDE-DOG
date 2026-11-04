`timescale 1ns/1ps
// Publish a camera frame only after the DDR write responses cover its store.
// Tap VDMA's ordered, single-ID S2MM AXI interface before SmartConnect.
module vdma_frame_commit_axi #(
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
    output reg write_start,
    output reg [1:0] write_start_slot,
    output reg commit,
    output reg [1:0] commit_slot,
    output reg [31:0] commit_generation,
    output reg [31:0] error_count,
    output reg fault
);
    localparam integer DEPTH = 1 << QUEUE_LOG2;
    localparam integer COUNT_W = $clog2(FRAME_BYTES + 32'd65536);
    reg [1:0] slot_q [0:DEPTH-1];
    reg [15:0] bytes_q [0:DEPTH-1];
    reg valid_q [0:DEPTH-1];
    reg start_q [0:DEPTH-1];
    reg [QUEUE_LOG2-1:0] head, tail;
    reg [QUEUE_LOG2:0] pending;
    reg response_pending, response_valid;
    reg response_start;
    reg [1:0] response_slot, response_code;
    reg [15:0] response_bytes;
    reg [COUNT_W-1:0] completed [0:2];
    reg [31:0] expected_aw [0:2];
    reg bad [0:2];
    integer i;
    wire aw_fire = awvalid && awready;
    wire b_fire = bvalid && bready;
    wire [31:0] burst_bytes = ({24'd0, awlen} + 32'd1) << awsize;
    wire [31:0] frame_span = FRAME_BYTES * 3;
    wire in_range = awaddr >= FRAME_BASE && awaddr < FRAME_BASE + frame_span;
    wire [31:0] offset = awaddr - FRAME_BASE;
    wire [1:0] new_slot = offset < FRAME_BYTES ? 2'd0 :
                          offset < 2 * FRAME_BYTES ? 2'd1 : 2'd2;
    wire [31:0] slot_end = FRAME_BASE + (new_slot + 32'd1) * FRAME_BYTES;
    wire [31:0] slot_begin = FRAME_BASE + new_slot * FRAME_BYTES;
    wire frame_start_aw = in_range && awaddr == slot_begin;
    // VDMA may abandon a short frame and revisit this store at its base.
    // Base restarts are boundaries, not noncontiguous writes within a frame.
    wire address_expected = awaddr == expected_aw[new_slot] || frame_start_aw;
    wire burst_valid = in_range && burst_bytes != 0 &&
                       (awaddr + burst_bytes) <= slot_end &&
                       (awaddr + burst_bytes) >= awaddr &&
                       address_expected;
    wire q_has_item = pending != 0;
    wire q_has_space = pending < DEPTH || b_fire;
    // Reset in B-response order: resetting on AW could discard old responses
    // still in flight, or combine a short frame with the next frame's bytes.
    wire [COUNT_W-1:0] response_end =
        (response_start ? {COUNT_W{1'b0}} : completed[response_slot]) + response_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0; tail <= 0; pending <= 0;
            response_pending <= 0; response_valid <= 0;
            response_start <= 0;
            response_slot <= 0; response_code <= 0; response_bytes <= 0;
            write_start <= 0; write_start_slot <= 0;
            commit <= 0; commit_slot <= 0; commit_generation <= 0;
            error_count <= 0; fault <= 0;
            for (i = 0; i < 3; i = i + 1) begin
                completed[i] <= 0; bad[i] <= 0;
                expected_aw[i] <= FRAME_BASE + i * FRAME_BYTES;
            end
        end else begin
            commit <= 0;
            write_start <= 0;
            if (aw_fire) begin
                if (!q_has_space) begin
                    fault <= 1; error_count <= error_count + 1'b1;
                end else begin
                    slot_q[tail] <= new_slot;
                    bytes_q[tail] <= burst_bytes[15:0];
                    valid_q[tail] <= burst_valid && burst_bytes <= 16'hffff;
                    start_q[tail] <= frame_start_aw;
                    tail <= tail + 1'b1;
                    // Invalid AW latches fault; its speculative next address
                    // cannot publish a frame and keeps AWLEN off the CE path.
                    expected_aw[new_slot] <= awaddr + burst_bytes;
                    if (burst_valid && frame_start_aw) begin
                        write_start <= 1;
                        write_start_slot <= new_slot;
                        if (expected_aw[new_slot] != slot_begin &&
                            expected_aw[new_slot] != slot_end)
                            error_count <= error_count + 1'b1;
                    end
                    if (!burst_valid || burst_bytes > 16'hffff) begin
                        fault <= 1; error_count <= error_count + 1'b1;
                    end
                end
            end
            if (b_fire) begin
                if (!q_has_item) begin
                    fault <= 1; error_count <= error_count + 1'b1;
                end else begin
                    head <= head + 1'b1;
                    response_slot <= slot_q[head];
                    response_bytes <= bytes_q[head];
                    response_valid <= valid_q[head];
                    response_start <= start_q[head];
                    response_code <= bresp;
                end
            end
            response_pending <= b_fire && q_has_item;
            if (response_pending && response_valid) begin
                if (response_end == FRAME_BYTES) begin
                    completed[response_slot] <= 0;
                    bad[response_slot] <= 0;
                    if (!fault && (response_start || !bad[response_slot]) &&
                        response_code == 2'b00) begin
                        commit <= 1;
                        commit_slot <= response_slot;
                        commit_generation <= commit_generation + 1'b1;
                    end else error_count <= error_count + 1'b1;
                end else if (response_end > FRAME_BYTES) begin
                    completed[response_slot] <= 0;
                    bad[response_slot] <= 0;
                    fault <= 1; error_count <= error_count + 1'b1;
                end else begin
                    completed[response_slot] <= response_end;
                    if (response_start) bad[response_slot] <= response_code != 2'b00;
                    else if (response_code != 2'b00) bad[response_slot] <= 1;
                end
            end
            case ({aw_fire && q_has_space, b_fire && q_has_item})
                2'b10: pending <= pending + 1'b1;
                2'b01: pending <= pending - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
