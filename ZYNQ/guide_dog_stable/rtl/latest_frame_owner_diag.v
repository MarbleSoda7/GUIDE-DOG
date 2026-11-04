`timescale 1ns/1ps
// Pack PL-owner progress into the existing 160-bit diagnostic CDC bus.
// Every lane is Gray-coded so eth_stream can safely synchronize it into the
// 125 MHz Ethernet clock domain without adding a new AXI-Lite peripheral.
module latest_frame_owner_diag (
    input wire clk,
    input wire rst_n,
    input wire write_start,
    input wire commit,
    input wire [31:0] commit_generation,
    input wire [31:0] commit_error_count,
    input wire commit_fault,
    input wire [1:0] latest_slot,
    input wire [31:0] latest_generation,
    input wire [31:0] requested_generation,
    input wire busy,
    input wire pacer_fault,
    input wire mm2s_fsync,
    input wire stream_done,
    input wire [31:0] last_sent_generation,
    input wire [31:0] drop_count,
    input wire gate_fault,
    input wire [1:0] read_slot,
    input wire read_fault,
    output wire [159:0] diag_counters
);
    reg [31:0] write_count, commit_count, fsync_count, done_count;
    reg [31:0] lane0, lane1, lane2, lane3, lane4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_count <= 0;
            commit_count <= 0;
            fsync_count <= 0;
            done_count <= 0;
        end else begin
            if (write_start) write_count <= write_count + 1'b1;
            if (commit) commit_count <= commit_count + 1'b1;
            if (mm2s_fsync) fsync_count <= fsync_count + 1'b1;
            if (stream_done) done_count <= done_count + 1'b1;
        end
    end

    always @* begin
        lane0 = write_count;
        lane1 = commit_count;
        lane2 = fsync_count;
        lane3 = done_count;
        lane4 = {commit_fault, pacer_fault, gate_fault, read_fault,
                 busy, mm2s_fsync, stream_done, write_start,
                 read_slot, latest_slot, commit_generation[11:0],
                 requested_generation[7:0]};
    end

    assign diag_counters = {
        (lane4 ^ (lane4 >> 1)),
        (lane3 ^ (lane3 >> 1)),
        (lane2 ^ (lane2 >> 1)),
        (lane1 ^ (lane1 >> 1)),
        (lane0 ^ (lane0 >> 1))};
endmodule
