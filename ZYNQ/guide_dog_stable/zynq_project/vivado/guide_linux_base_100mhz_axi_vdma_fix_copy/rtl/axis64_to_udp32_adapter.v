`timescale 1ns/1ps
// AXIS 64-bit to legacy UDP 32-bit request adapter skeleton.
// This module is NOT wired into existing UDP today; it is the Phase-C adapter contract.
module axis64_to_udp32_adapter(
 input wire aclk, input wire aresetn,
 input wire [63:0] s_axis_tdata, input wire s_axis_tvalid, output wire s_axis_tready, input wire s_axis_tlast,
 input wire udp_tx_req, output reg [31:0] udp_tx_data, output reg udp_data_valid, output reg frame_done
);
 reg half; reg [63:0] held; reg held_valid; reg held_last;
 // Accept a new 64-bit AXIS beat only when no beat is buffered.
 assign s_axis_tready = !held_valid;
 always @(posedge aclk) begin
  if(!aresetn) begin
    half<=0; held<=0; held_last<=0; held_valid<=0;
    udp_tx_data<=0; udp_data_valid<=0; frame_done<=0;
  end else begin
    udp_data_valid<=0; frame_done<=0;
    if(s_axis_tvalid && s_axis_tready) begin
      held<=s_axis_tdata; held_last<=s_axis_tlast; held_valid<=1; half<=0;
    end
    if(udp_tx_req && held_valid) begin
      udp_tx_data <= half ? held[31:0] : held[63:32];
      udp_data_valid<=1;
      if(half) begin
        held_valid<=0; half<=0;
        if(held_last) frame_done<=1;
      end else half<=1;
    end
  end
 end
endmodule