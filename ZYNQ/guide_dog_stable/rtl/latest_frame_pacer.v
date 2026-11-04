`timescale 1ns/1ps
// PL-only one-deep mailbox between committed camera frames and VDMA MM2S.
// A second commit while MM2S is busy supersedes the older pending frame.
// Fsync is one clock wide and never repeats an already requested generation.
module latest_frame_pacer #(
    parameter integer WATCHDOG_CYCLES = 50000000
) (
    input wire clk, rst_n,
    input wire enable,
    input wire commit,
    input wire [1:0] commit_slot,
    input wire [31:0] commit_generation,
    input wire stream_done,
    input wire external_fault,
    output reg mm2s_fsync,
    output reg [1:0] latest_slot,
    output reg [31:0] latest_generation,
    output reg [31:0] requested_generation,
    output reg busy,
    output reg fault
);
    reg [31:0] wait_cycles;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mm2s_fsync <= 0;
            latest_slot <= 0;
            latest_generation <= 0;
            requested_generation <= 0;
            busy <= 0;
            fault <= 0;
            wait_cycles <= 0;
        end else begin
            mm2s_fsync <= 0;
            if (external_fault) fault <= 1;
            if (commit) begin
                latest_slot <= commit_slot;
                latest_generation <= commit_generation;
            end
            if (stream_done) begin
                if (!busy) fault <= 1;
                busy <= 0;
                wait_cycles <= 0;
            end else if (busy) begin
                if (wait_cycles >= WATCHDOG_CYCLES - 1) fault <= 1;
                else wait_cycles <= wait_cycles + 1'b1;
            end
            if (enable && !fault && !external_fault && !busy && !stream_done &&
                latest_generation != 0 && latest_generation != requested_generation) begin
                mm2s_fsync <= 1;
                requested_generation <= latest_generation;
                busy <= 1;
                wait_cycles <= 0;
            end
        end
    end
endmodule
