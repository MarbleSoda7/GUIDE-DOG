`timescale 1ns/1ps
module axis_32_to_64 (
    input wire aclk, aresetn,
    input wire [31:0] s_axis_tdata, input wire s_axis_tvalid,
    output wire s_axis_tready, input wire s_axis_tlast,
    output wire [63:0] m_axis_tdata, output wire [7:0] m_axis_tkeep,
    output wire m_axis_tvalid, input wire m_axis_tready,
    output wire m_axis_tlast
);
    reg [63:0] pending;
    reg [1:0] count;
    reg line_end;
    assign s_axis_tready = !m_axis_tvalid && !line_end;
    assign m_axis_tvalid = (count == 2) || (line_end && count != 0);
    assign m_axis_tdata = pending;
    assign m_axis_tkeep = count == 2 ? 8'hff : 8'h0f;
    assign m_axis_tlast = line_end && count != 0;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            pending <= 0; count <= 0; line_end <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            pending <= 0; count <= 0; line_end <= 0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            if (count == 0) pending[31:0] <= s_axis_tdata;
            else pending[63:32] <= s_axis_tdata;
            count <= count + 1'b1;
            if (s_axis_tlast) line_end <= 1;
        end
    end
endmodule
