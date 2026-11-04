`timescale 1ns/1ps

// Revision-unique, self-contained module-ref for the single-burn node
// diagnostic. Keeping the implementation in this module (rather than
// instantiating a nested core) ensures Vivado sees diag_counters as a real
// driven output instead of grounding a net from an unresolved child.
module axis_rgb24_to_32_node_diag (
    input wire aclk,
    input wire aresetn,
    input wire [23:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tuser,
    input wire s_axis_tlast,
    output wire [31:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tuser,
    output wire m_axis_tlast,
    output reg fault,
    output reg fault_sof,
    output reg fault_eol,
    output wire [159:0] diag_counters
);
    reg [55:0] pending;
    reg [2:0] count;
    reg line_end, frame_start;
    reg [31:0] diag_input_pixels, diag_input_sofs, diag_input_eols;
    reg [31:0] diag_output_beats, diag_output_tlasts;

    assign m_axis_tvalid = count >= 4;
    assign s_axis_tready = !m_axis_tvalid && !line_end && count <= 3;
    assign m_axis_tdata = pending[31:0];
    assign m_axis_tlast = line_end && count == 4;
    assign m_axis_tuser = frame_start;
    assign diag_counters = {
        (diag_output_tlasts ^ (diag_output_tlasts >> 1)),
        (diag_output_beats ^ (diag_output_beats >> 1)),
        (diag_input_eols ^ (diag_input_eols >> 1)),
        (diag_input_sofs ^ (diag_input_sofs >> 1)),
        (diag_input_pixels ^ (diag_input_pixels >> 1))};

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            pending <= 0; count <= 0; line_end <= 0; frame_start <= 0;
            fault <= 0; fault_sof <= 0; fault_eol <= 0;
            diag_input_pixels <= 0; diag_input_sofs <= 0; diag_input_eols <= 0;
            diag_output_beats <= 0; diag_output_tlasts <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            diag_output_beats <= diag_output_beats + 1'b1;
            if (m_axis_tlast) diag_output_tlasts <= diag_output_tlasts + 1'b1;
            pending <= pending >> 32; count <= count - 4; frame_start <= 0;
            if (m_axis_tlast) line_end <= 0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            diag_input_pixels <= diag_input_pixels + 1'b1;
            if (s_axis_tuser) diag_input_sofs <= diag_input_sofs + 1'b1;
            if (s_axis_tlast) diag_input_eols <= diag_input_eols + 1'b1;
            if (s_axis_tuser) begin
                if (count != 0 || line_end) fault_sof <= 1'b1;
                pending <= {{32{1'b0}}, s_axis_tdata}; count <= 3;
                line_end <= 0; frame_start <= 1;
            end else begin
                pending <= pending | ({{32{1'b0}}, s_axis_tdata} << (count * 8));
                count <= count + 3;
            end
            if (s_axis_tlast) begin
                line_end <= 1;
                if (!s_axis_tuser && (count + 3) % 4 != 0) begin
                    fault <= 1'b1; fault_eol <= 1'b1;
                end
            end
        end
    end
endmodule
