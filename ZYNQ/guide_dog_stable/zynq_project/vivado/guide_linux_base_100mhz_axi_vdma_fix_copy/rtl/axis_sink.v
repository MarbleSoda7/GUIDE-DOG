`timescale 1ns/1ps
// Stage 2 verification sink: always-ready AXIS consumer.
// Will be REPLACED by dma_udp_packetizer in Stage 3.
module axis_sink (
  input  wire        aclk,
  input  wire        aresetn,
  input  wire        s_axis_tvalid,
  output wire        s_axis_tready,
  input  wire [63:0] s_axis_tdata,
  input  wire [7:0]  s_axis_tkeep,
  input  wire        s_axis_tlast,
  output reg  [31:0] beat_count
);
  assign s_axis_tready = 1'b1;
  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn)
      beat_count <= 32'd0;
    else if (s_axis_tvalid && s_axis_tready)
      beat_count <= beat_count + 1'b1;
  end
endmodule