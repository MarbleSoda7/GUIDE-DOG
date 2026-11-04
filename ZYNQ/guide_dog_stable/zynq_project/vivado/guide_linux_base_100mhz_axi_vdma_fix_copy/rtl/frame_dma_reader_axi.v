`timescale 1ns/1ps
// Frame-level AXI HP0 read master skeleton.
// Clock: one 100MHz FCLK domain. No RGMII clock appears here.
// Data crosses to UDP only through XPM async FIFO in future BD integration.
module frame_dma_reader_axi #(
  parameter AXI_ADDR_W = 32,
  parameter AXI_DATA_W = 64,
  parameter MAX_BURST_BEATS = 16
)(
  input wire aclk, input wire aresetn,
  // AXI-Lite control slave, intentionally small; BD assigns its base address.
  input wire [5:0] s_awaddr, input wire s_awvalid, output wire s_awready,
  input wire [31:0] s_wdata, input wire s_wvalid, output wire s_wready,
  output wire [1:0] s_bresp, output wire s_bvalid, input wire s_bready,
  input wire [5:0] s_araddr, input wire s_arvalid, output wire s_arready,
  output wire [31:0] s_rdata, output wire [1:0] s_rresp, output wire s_rvalid, input wire s_rready,
  // AXI4 read master to PS S_AXI_HP0 through SmartConnect.
  output wire [AXI_ADDR_W-1:0] m_araddr, output wire [7:0] m_arlen,
  output wire [2:0] m_arsize, output wire [1:0] m_arburst,
  output wire m_arvalid, input wire m_arready,
  input wire [AXI_DATA_W-1:0] m_rdata, input wire [1:0] m_rresp,
  input wire m_rlast, input wire m_rvalid, output wire m_rready,
  // Stream output to an XPM FIFO write-side adapter.
  output wire [AXI_DATA_W-1:0] out_data, output wire out_valid, input wire out_ready,
  output wire busy, output wire done, output wire error
);
  // Register offsets: CTRL=00, STATUS=04, FRAME_BASE=08, BYTE_COUNT=0C, WORDS=10, ERROR=14.
  reg [31:0] frame_base, byte_count; reg start_req, busy_r, done_r, error_r;
  reg [31:0] words_issued, bytes_left, next_addr; reg [7:0] burst_left;
  reg aw_seen, w_seen; reg [5:0] awaddr_r; reg [31:0] wdata_r; reg bvalid_r;
  reg rvalid_r; reg [31:0] rdata_r; reg ar_pending;
  wire wr_fire = aw_seen && w_seen;
  assign s_awready = !aw_seen; assign s_wready = !w_seen; assign s_bresp=2'b00; assign s_bvalid=bvalid_r;
  assign s_arready = !ar_pending && !rvalid_r; assign s_rresp=2'b00; assign s_rvalid=rvalid_r; assign s_rdata=rdata_r;
  assign busy=busy_r; assign done=done_r; assign error=error_r;
  always @(posedge aclk) begin
    if(!aresetn) begin aw_seen<=0; w_seen<=0; bvalid_r<=0; frame_base<=0; byte_count<=0; start_req<=0; done_r<=0; error_r<=0; end
    else begin
      if(s_awvalid && !aw_seen) begin aw_seen<=1; awaddr_r<=s_awaddr; end
      if(s_wvalid && !w_seen) begin w_seen<=1; wdata_r<=s_wdata; end
      if(wr_fire) begin
        aw_seen<=0; w_seen<=0; bvalid_r<=1;
        case(awaddr_r)
          6'h00: begin if(wdata_r[0]) start_req<=1; if(wdata_r[1]) begin busy_r<=0; error_r<=0; end if(wdata_r[2]) begin done_r<=0; error_r<=0; end end
          6'h08: frame_base<=wdata_r;
          6'h0c: byte_count<=wdata_r;
        endcase
      end else if(bvalid_r && s_bready) bvalid_r<=0;
    end
  end
  always @(posedge aclk) begin
    if(!aresetn) begin rvalid_r<=0; ar_pending<=0; rdata_r<=0; end
    else begin
      if(s_arvalid && s_arready) begin
        ar_pending<=1; rvalid_r<=1;
        case(s_araddr)
          6'h04: rdata_r<={28'd0,error_r,done_r,busy_r};
          6'h08: rdata_r<=frame_base; 6'h0c: rdata_r<=byte_count;
          6'h10: rdata_r<=words_issued; 6'h14: rdata_r<={30'd0,error_r,1'b0};
          default: rdata_r<=0;
        endcase
      end else if(rvalid_r && s_rready) begin rvalid_r<=0; ar_pending<=0; end
    end
  end
  // Read engine. Each AXI burst is 16 64-bit beats or less for the final tail.
  reg arvalid_r, reading;
  wire [31:0] beats_remaining = bytes_left >> 3;
  wire [7:0] requested_len = (beats_remaining >= MAX_BURST_BEATS) ? (MAX_BURST_BEATS-1) : (beats_remaining-1);
  assign m_araddr=next_addr; assign m_arlen=requested_len; assign m_arsize=3'd3; assign m_arburst=2'b01; assign m_arvalid=arvalid_r;
  assign m_rready=reading && out_ready; assign out_data=m_rdata; assign out_valid=reading && m_rvalid;
  always @(posedge aclk) begin
    if(!aresetn) begin busy_r<=0; done_r<=0; error_r<=0; words_issued<=0; bytes_left<=0; next_addr<=0; arvalid_r<=0; reading<=0; burst_left<=0; end
    else begin
      if(start_req && !busy_r) begin
        start_req<=0; done_r<=0; error_r<=0; words_issued<=0; bytes_left<=byte_count; next_addr<=frame_base; busy_r<=1;
      end
      if(busy_r && !reading && !arvalid_r && bytes_left!=0) arvalid_r<=1;
      if(arvalid_r && m_arready) begin arvalid_r<=0; reading<=1; burst_left<=requested_len+1'b1; end
      if(reading && m_rvalid && out_ready) begin
        if(m_rresp!=2'b00) error_r<=1;
        words_issued<=words_issued+1; bytes_left<=bytes_left-8; next_addr<=next_addr+8; burst_left<=burst_left-1;
        if(m_rlast) begin
          reading<=0;
          if(bytes_left==8) begin busy_r<=0; done_r<=1; end
        end
      end
    end
  end
endmodule