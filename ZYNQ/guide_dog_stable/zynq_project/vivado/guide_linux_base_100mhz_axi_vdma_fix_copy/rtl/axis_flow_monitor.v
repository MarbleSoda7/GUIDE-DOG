`timescale 1ns/1ps
module axis_flow_monitor (
 input wire aclk,input wire aresetn,input wire [63:0] s_axis_tdata,input wire [7:0] s_axis_tkeep,input wire s_axis_tvalid,output wire s_axis_tready,input wire s_axis_tlast,
 output wire [63:0] m_axis_tdata,output wire [7:0] m_axis_tkeep,output wire m_axis_tvalid,input wire m_axis_tready,output wire m_axis_tlast,
 output reg [31:0] dbg_accepted_beats,output reg [31:0] dbg_tlasts,output reg [31:0] dbg_stall_cycles
);
assign m_axis_tdata=s_axis_tdata; assign m_axis_tkeep=s_axis_tkeep; assign m_axis_tvalid=s_axis_tvalid; assign m_axis_tlast=s_axis_tlast; assign s_axis_tready=m_axis_tready;
always @(posedge aclk or negedge aresetn) begin
 if(!aresetn) begin dbg_accepted_beats<=0;dbg_tlasts<=0;dbg_stall_cycles<=0;end else begin
  if(s_axis_tvalid&&s_axis_tready) begin dbg_accepted_beats<=dbg_accepted_beats+1'b1;if(s_axis_tlast) dbg_tlasts<=dbg_tlasts+1'b1;end
  if(s_axis_tvalid&&!s_axis_tready) dbg_stall_cycles<=dbg_stall_cycles+1'b1;
 end
end
endmodule
