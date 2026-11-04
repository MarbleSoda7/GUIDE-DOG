`timescale 1ns/1ps
// Byte-accurate AXIS64 -> legacy udp_tx packetizer, same clock as udp_tx.
// Packet: [4B zero][fid BE2][total=827 BE2][idx BE2][1394 raw bytes].
module dma_udp_packetizer #(parameter PAYLOAD_BYTES=1394, parameter TOTAL_PKTS=827, parameter FRAME_BYTES=1152000)(
 input wire clk,input wire rst_n,input wire [15:0] frame_id,output reg frame_done,
 input wire [63:0] s_axis_tdata,input wire [7:0] s_axis_tkeep,input wire s_axis_tvalid,output wire s_axis_tready,input wire s_axis_tlast,
 input wire udp_tx_req,output reg [31:0] udp_tx_data,output reg udp_tx_start,output reg [15:0] udp_tx_bytes,input wire udp_tx_done,
 output wire [1:0] dbg_state,output wire [15:0] dbg_axis_live,output reg [31:0] dbg_heartbeat,output reg [31:0] dbg_axis_beats,output reg [31:0] dbg_byte_steps,output reg [31:0] dbg_packet_starts,output reg [31:0] dbg_udp_reqs,output reg [31:0] dbg_udp_dones
);
localparam ST_FILL=2'd0,ST_START=2'd1,ST_SEND=2'd2,ST_WAIT=2'd3;
reg [1:0] state; reg [15:0] pkt_idx; reg [10:0] payload_idx; reg [9:0] send_word;
reg [20:0] frame_byte_count;
reg [63:0] beat_buf; reg [7:0] beat_keep; reg [2:0] beat_pos; reg beat_valid,beat_last;
reg [7:0] packet_mem [0:1403];
reg [11:0] packet_valid_bytes;
reg [11:0] send_base;
function [7:0] axis_byte; input [63:0] d; input [2:0] n; begin case(n)
 // AXI4-Stream byte lane 0 is TDATA[7:0], matching TKEEP[0].
 3'd0:axis_byte=d[7:0];3'd1:axis_byte=d[15:8];3'd2:axis_byte=d[23:16];3'd3:axis_byte=d[31:24];
 3'd4:axis_byte=d[39:32];3'd5:axis_byte=d[47:40];3'd6:axis_byte=d[55:48];default:axis_byte=d[63:56];endcase end endfunction
 function [7:0] packet_byte; input [11:0] n; begin
  if (n >= packet_valid_bytes) packet_byte=8'd0;
  else packet_byte=packet_mem[n];
 end endfunction
task setup_header; input [11:0] total_bytes; begin
 packet_mem[0]<=0;packet_mem[1]<=0;packet_mem[2]<=0;packet_mem[3]<=0;
 packet_mem[4]<=frame_id[15:8];packet_mem[5]<=frame_id[7:0];
 packet_mem[6]<=8'h03;packet_mem[7]<=8'h3b;
 packet_mem[8]<=pkt_idx[15:8];packet_mem[9]<=pkt_idx[7:0];
 packet_valid_bytes<=total_bytes;
 udp_tx_bytes<=total_bytes;
end endtask
assign s_axis_tready = (state==ST_FILL) && !beat_valid;
assign dbg_state = state;
/* Live read-side AXIS state: {last, beat_valid, beat_pos, state,
   tvalid, tready, tlast}.  This distinguishes missing FIFO output from a
   packetizer backpressure fault without altering the handshake. */
assign dbg_axis_live = {6'd0, beat_last, beat_valid, beat_pos, state,
                        s_axis_tvalid, s_axis_tready, s_axis_tlast};
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin state<=ST_FILL;pkt_idx<=0;payload_idx<=0;send_word<=0;send_base<=0;packet_valid_bytes<=0;frame_byte_count<=0;beat_buf<=0;beat_keep<=0;beat_pos<=0;beat_valid<=0;beat_last<=0;frame_done<=0;udp_tx_start<=0;udp_tx_bytes<=0;udp_tx_data<=0;dbg_heartbeat<=0;dbg_axis_beats<=0;dbg_byte_steps<=0;dbg_packet_starts<=0;dbg_udp_reqs<=0;dbg_udp_dones<=0; end
 else begin
  dbg_heartbeat<=dbg_heartbeat+1'b1;
  udp_tx_start<=0;frame_done<=0;
  if(state==ST_FILL && beat_valid) dbg_byte_steps<=dbg_byte_steps+1'b1;
  if(state==ST_FILL && s_axis_tvalid && s_axis_tready) begin beat_buf<=s_axis_tdata;beat_keep<=s_axis_tkeep;beat_pos<=0;beat_valid<=1;beat_last<=s_axis_tlast;dbg_axis_beats<=dbg_axis_beats+1'b1;end
  case(state)
   ST_FILL: if(beat_valid) begin
     if(beat_keep[beat_pos]) begin
       packet_mem[10+payload_idx] <= axis_byte(beat_buf,beat_pos);
       frame_byte_count <= frame_byte_count + 1'b1;
       if(payload_idx==PAYLOAD_BYTES-1) begin
          setup_header(10 + PAYLOAD_BYTES); state<=ST_START; payload_idx<=0;
         if(beat_pos==3'd7) begin beat_valid<=0;beat_pos<=0;end else beat_pos<=beat_pos+1'b1;
       end else if(frame_byte_count == FRAME_BYTES-1) begin
          // Final packet is short; never transmit uninitialized pad bytes.
          setup_header(10 + payload_idx + 1'b1);
          state<=ST_START; payload_idx<=0; frame_byte_count<=0;
          beat_valid<=0; beat_pos<=0;
       end else begin
         payload_idx<=payload_idx+1'b1;
         if(beat_pos==3'd7) begin beat_valid<=0;beat_pos<=0;end else beat_pos<=beat_pos+1'b1;
       end
     end else begin
       // An unaligned AXI DMA command can create sparse TKEEP lanes at the
       // start/end of its AXIS frame.  Skip only this invalid lane; clearing
       // the whole beat here discarded valid lanes above it and lost payload.
       if(beat_pos==3'd7) begin beat_valid<=0;beat_pos<=0;end else beat_pos<=beat_pos+1'b1;
     end
   end
   ST_START: begin udp_tx_start<=1;send_word<=0;send_base<=0;state<=ST_SEND;dbg_packet_starts<=dbg_packet_starts+1'b1;end
   ST_SEND: if(udp_tx_req) begin
    dbg_udp_reqs<=dbg_udp_reqs+1'b1;
    udp_tx_data<={packet_byte(send_base),packet_byte(send_base+1'b1),packet_byte(send_base+2'd2),packet_byte(send_base+2'd3)};
    if(send_word==(((packet_valid_bytes + 12'd3) >> 2) - 1'b1)) state<=ST_WAIT;
    else begin send_word<=send_word+1'b1;send_base<=send_base+3'd4;end
   end
   ST_WAIT: if(udp_tx_done) begin dbg_udp_dones<=dbg_udp_dones+1'b1;if(pkt_idx==TOTAL_PKTS-1) begin frame_done<=1;pkt_idx<=0;state<=ST_FILL;end else begin pkt_idx<=pkt_idx+1'b1;state<=ST_FILL;end end
  endcase
 end
end
endmodule
