`timescale 1ns/1ps
// VDMA MM2S RGB888 -> byte-contiguous AXIS64. TLAST is an end-of-line mark;
// dma_udp_packetizer counts exact FRAME_BYTES and sends a short last packet.
module axis_rgb24_to_64 (
    input wire aclk, aresetn,
    input wire [23:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,
    output wire [63:0] m_axis_tdata,
    output wire [7:0] m_axis_tkeep,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast
);
    reg [87:0] bytes_pending;
    reg [3:0] pending_count;
    reg line_end_pending;
    assign m_axis_tvalid = pending_count >= 8 ||
                           (line_end_pending && pending_count != 0);
    assign s_axis_tready = !m_axis_tvalid && !line_end_pending &&
                           pending_count <= 7;
    assign m_axis_tdata = bytes_pending[63:0];
    assign m_axis_tkeep = pending_count >= 8 ? 8'hff :
                          (8'hff >> (8 - pending_count));
    assign m_axis_tlast = line_end_pending && pending_count <= 8;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bytes_pending <= 0;
            pending_count <= 0;
            line_end_pending <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (m_axis_tlast) begin
                bytes_pending <= 0;
                pending_count <= 0;
                line_end_pending <= 0;
            end else begin
                bytes_pending <= bytes_pending >> 64;
                pending_count <= pending_count - 8;
            end
        end else if (s_axis_tvalid && s_axis_tready) begin
            bytes_pending <= bytes_pending |
                             ({{64{1'b0}}, s_axis_tdata} << (pending_count * 8));
            pending_count <= pending_count + 3;
            if (s_axis_tlast) line_end_pending <= 1;
        end
    end
endmodule
