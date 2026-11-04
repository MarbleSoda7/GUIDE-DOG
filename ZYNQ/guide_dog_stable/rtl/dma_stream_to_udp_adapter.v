`timescale 1ns/1ps
// Placeholder for future 64-bit DMA stream to legacy UDP packetizer adaptation.
// This module is intentionally not connected to the current top-level.
module dma_stream_to_udp_adapter(input wire clk,input wire rstn,input wire [63:0] in_data,input wire in_valid,output wire in_ready,input wire [15:0] frame_id,input wire start,input wire udp_tx_req,output reg [31:0] udp_word,output reg udp_word_valid);
assign in_ready = udp_tx_req;
always @(posedge clk) begin if(!rstn) begin udp_word<=0; udp_word_valid<=0; end else begin udp_word_valid<=in_valid && udp_tx_req; if(in_valid && udp_tx_req) udp_word<=in_data[31:0]; end end
endmodule