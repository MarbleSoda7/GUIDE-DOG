`timescale 1ns/1ps
// Drop a complete MM2S video frame unless its actual VDMA read slot contains
// a DDR-committed generation newer than the last one sent. Never switch source
// midway through a frame. The caller must use the three-slot writer state to
// prevent write/read overlap. The read pointer is allowed to visit any safe
// completed slot; requiring read_slot == latest_slot would discard roughly two
// of every three circular VDMA reads when the writer and reader run at the
// same frame cadence.
module latest_frame_stream_gate #(
    parameter integer LINES = 480
) (
    input wire clk, rst_n,
    input wire external_fault,
    input wire write_start,
    input wire [1:0] write_start_slot,
    input wire commit,
    input wire [1:0] commit_slot,
    input wire [31:0] commit_generation,
    input wire [1:0] latest_slot,
    input wire [31:0] latest_generation,
    input wire [1:0] read_slot,
    input wire [31:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tuser,
    input wire s_axis_tlast,
    output wire [31:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tuser,
    output wire m_axis_tlast,
    output reg stream_done,
    output reg [31:0] last_sent_generation,
    output reg [31:0] drop_count,
    output reg fault
);
    reg [31:0] slot_generation [0:2];
    reg [2:0] slot_valid, slot_writing;
    reg active, passing;
    reg [1:0] active_slot;
    reg [31:0] active_generation;
    reg [9:0] line_count;
    integer i;

    // The read-side monitor decodes the actual AXI ARADDR, not VDMA's
    // six-bit Gray/reverse-order genlock token.
    wire valid_read_slot = read_slot < 3;
    wire start_allowed = valid_read_slot && slot_valid[read_slot] &&
                         !slot_writing[read_slot] &&
                         slot_generation[read_slot] > last_sent_generation &&
                         latest_generation != 0 && !fault;
    wire pass_now = active ? passing : (s_axis_tuser && start_allowed);
    assign s_axis_tready = pass_now ? m_axis_tready : 1'b1;
    assign m_axis_tvalid = s_axis_tvalid && pass_now && !fault;
    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tuser = s_axis_tuser;
    assign m_axis_tlast = s_axis_tlast;
    wire s_fire = s_axis_tvalid && s_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_valid <= 0; slot_writing <= 0;
            active <= 0; passing <= 0; active_slot <= 0;
            active_generation <= 0; line_count <= 0;
            stream_done <= 0; last_sent_generation <= 0;
            drop_count <= 0; fault <= 0;
            for (i = 0; i < 3; i = i + 1) slot_generation[i] <= 0;
        end else begin
            stream_done <= 0;
            if (external_fault) fault <= 1;
            if (write_start) begin
                if (write_start_slot > 2 ||
                    (active && passing && active_slot == write_start_slot))
                    fault <= 1;
                else begin
                    slot_writing[write_start_slot] <= 1;
                    slot_valid[write_start_slot] <= 0;
                end
            end
            if (commit) begin
                if (commit_slot > 2 ||
                    (write_start && write_start_slot == commit_slot))
                    fault <= 1;
                else begin
                    slot_writing[commit_slot] <= 0;
                    slot_valid[commit_slot] <= 1;
                    slot_generation[commit_slot] <= commit_generation;
                end
            end
            if (s_fire) begin
                if (s_axis_tuser) begin
                    if (active) fault <= 1;
                    active <= 1;
                    passing <= start_allowed && !active;
                    active_slot <= read_slot;
                    active_generation <= valid_read_slot ? slot_generation[read_slot] : 0;
                    line_count <= 0;
                    if (!start_allowed || active) drop_count <= drop_count + 1'b1;
                end else if (!active) begin
                    // Ignore pre-SOF input; a new VDMA run must start at SOF.
                    drop_count <= drop_count + 1'b1;
                end
                // The first line may end on the same beat as SOF.  Count it;
                // otherwise a complete frame never generates stream_done.
                if (s_axis_tlast && (active || s_axis_tuser)) begin
                    if ((s_axis_tuser && LINES == 1) ||
                        (!s_axis_tuser && line_count == LINES - 1)) begin
                        active <= 0;
                        stream_done <= 1;
                        if ((s_axis_tuser ? start_allowed : passing) && !fault)
                            last_sent_generation <= s_axis_tuser ?
                                                    slot_generation[read_slot] :
                                                    active_generation;
                    end else line_count <= s_axis_tuser ? 10'd1 :
                                                        line_count + 1'b1;
                end
            end
        end
    end
endmodule
