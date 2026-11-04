`timescale 1ns/1ns
//////////////////////////////////////////////////////////////////////
// eth_stream.v — ROOT FIX INTEGRATION: XPM ASYNC FIFO (二分第1轮: AXI + 单bank + v5引擎)
// 与 09-18 陈旧 dcp 行为对齐的最小完整发送链
//////////////////////////////////////////////////////////////////////
module eth_stream #(
    parameter integer C_BRAM_AW = 10,
    parameter [47:0] P_BOARD_MAC = 48'h12_34_56_78_9a_bc,
    parameter [31:0] P_BOARD_IP  = {8'd10, 8'd212, 8'd211, 8'd3},
    parameter [47:0] P_DES_MAC   = 48'hff_ff_ff_ff_ff_ff,
    parameter [31:0] P_DES_IP    = {8'd10, 8'd212, 8'd211, 8'd2},
    parameter integer ENABLE_RGMII_ILA = 1
)(
    input  wire        s_axi_aclk    ,
    input  wire        s_axi_aresetn ,
    input  wire [5:0]  s_axi_awaddr  ,
    input  wire        s_axi_awvalid ,
    output wire        s_axi_awready ,
    input  wire [31:0] s_axi_wdata   ,
    input  wire        s_axi_wvalid  ,
    output wire        s_axi_wready  ,
    output wire [1:0]  s_axi_bresp   ,
    output wire        s_axi_bvalid  ,
    input  wire        s_axi_bready  ,
    input  wire [5:0]  s_axi_araddr  ,
    input  wire        s_axi_arvalid ,
    output wire        s_axi_arready ,
    output wire [31:0] s_axi_rdata   ,
    output wire [1:0]  s_axi_rresp   ,
    output wire        s_axi_rvalid  ,
    input  wire        s_axi_rready  ,
    input  wire        rgmii_rxc     ,
    input  wire        rgmii_rx_ctl  ,
    input  wire [3:0]  rgmii_rxd     ,
    output wire        rgmii_txc     ,
    output wire        rgmii_tx_ctl  ,
    output wire [3:0]  rgmii_txd     ,
    input  wire        sys_rst_n     ,
    output wire        eth_rst_n     ,
    // Stage 3 DMA stream input. Clocked by raw rgmii_rxc / gmii_rx_clk.
    input  wire [63:0] dma_axis_tdata,
    input  wire [7:0]  dma_axis_tkeep,
    input  wire        dma_axis_tvalid,
    output wire        dma_axis_tready,
    input  wire        dma_axis_tlast,
    input wire [31:0] dma_mon_accepted_beats, input wire [31:0] dma_mon_tlasts,
    input wire [31:0] dma_mon_stall_cycles,
    input wire [159:0] camera_axis_diag_counters,
    input wire [4:0] camera_axis_diag_faults
);

localparam [5:0] ADDR_STATUS   = 6'h00;
localparam [5:0] ADDR_CTRL     = 6'h04;
localparam [5:0] ADDR_TXSTART  = 6'h08;
localparam [5:0] ADDR_TXBYTES  = 6'h0C;
localparam [5:0] ADDR_RAM_WA   = 6'h10;
localparam [5:0] ADDR_RAM_WD   = 6'h14;
localparam [5:0] ADDR_DBG_IN_BEATS=6'h18, ADDR_DBG_IN_LAST=6'h1C, ADDR_DBG_IN_STALL=6'h20;
localparam [5:0] ADDR_DBG_HEART=6'h24, ADDR_DBG_PKT_BEATS=6'h28, ADDR_DBG_PKT_START=6'h2C;
localparam [5:0] ADDR_DBG_UDP_REQ=6'h30, ADDR_DBG_UDP_DONE=6'h34, ADDR_DBG_STATE=6'h38;
localparam [5:0] ADDR_DBG_ETH=6'h3C;
// Read-only diagnostics aliases. AXI-Lite writes retain their historical
// controls; these reads expose camera/packer node counters for UART snapshots.
localparam [5:0] ADDR_DBG_CAM_IN_PIXELS=6'h08, ADDR_DBG_CAM_IN_SOF=6'h0C;
localparam [5:0] ADDR_DBG_CAM_IN_EOL=6'h10, ADDR_DBG_CAM_OUT_BEATS=6'h14;
localparam [5:0] ADDR_DBG_CAM_OUT_TLAST=6'h18, ADDR_DBG_CAM_FAULTS=6'h1C;

wire gmii_rx_clk;
wire gmii_rx_dv;
wire [7:0] gmii_rxd;
wire gmii_tx_clk;
wire gmii_tx_en;
wire [7:0] gmii_txd;
wire rec_pkt_done;
wire udp_tx_req;
wire udp_tx_done;
wire [1:0] txc_phase_active;
wire txc_locked;
reg  tx_start_en;
reg  [15:0] tx_byte_num;

reg [15:0] tx_bytes_ps;
reg [31:0] ram_wa_ps;
reg        bram_we;
reg        frame_req_clr;
reg        tx_start_ps;
reg        frame_req_ps;
reg [1:0]  sweep_mode_ps;

reg        tx_busy_eth;
reg [C_BRAM_AW-1:0] rd_addr_eth;
reg [31:0] tx_data_reg;
reg [31:0] pkt_heart_d1,pkt_heart_d2,pkt_beats_d1,pkt_beats_d2,pkt_start_d1,pkt_start_d2,pkt_req_d1,pkt_req_d2,pkt_done_d1,pkt_done_d2;
reg [1:0] pkt_state_d1,pkt_state_d2;
reg [15:0] pkt_live_d1,pkt_live_d2;
reg [31:0] pkt_byte_d1,pkt_byte_d2;
reg [31:0] eth_clk_heartbeat, eth_tx_active_cycles;
reg [31:0] eth_clk_d1, eth_clk_d2, eth_tx_d1, eth_tx_d2;
reg [1:0] sweep_mode_d1, sweep_mode_d2;
reg [1:0] txc_phase_ps, txc_phase_d1, txc_phase_d2;
reg [1:0] txc_phase_seen_d1, txc_phase_seen_d2;
reg txc_locked_d1, txc_locked_d2;
reg [3:0] sweep_phase;
reg [31:0] sweep_sink_beats, sweep_sink_tlasts, sweep_sink_stalls;
reg [159:0] cam_diag_sync1, cam_diag_sync2;
reg [4:0] cam_fault_sync1, cam_fault_sync2;
function [31:0] gray_to_binary;
    input [31:0] gray;
    integer g;
    begin
        gray_to_binary[31] = gray[31];
        for (g = 30; g >= 0; g = g - 1)
            gray_to_binary[g] = gray_to_binary[g+1] ^ gray[g];
    end
endfunction

// Match the board-proven UDP-loop probe: the PHY reset output is released
// continuously. Delaying this pin in the business design was the only
// remaining RGMII-side difference from the proven path.
assign eth_rst_n = 1'b1;

// ROOT FIX: standard XPM asynchronous FIFO replaces raw RGMII-clocked dual-port BRAM.
// Write side: PS AXI 100MHz. Read side: RGMII RXC. XPM owns Gray CDC/pointers/RAMB use.
reg [31:0] bram_wdata_d;
wire [31:0] fifo_dout;
wire fifo_empty, fifo_full, fifo_rd_valid;
wire fifo_wr_busy, fifo_rd_busy;
wire fifo_rst = ~s_axi_aresetn;
xpm_fifo_async #(
 .CDC_SYNC_STAGES(2), .DOUT_RESET_VALUE("0"), .ECC_MODE("no_ecc"),
 .FIFO_MEMORY_TYPE("block"), .FIFO_READ_LATENCY(1), .FIFO_WRITE_DEPTH(1024),
 .FULL_RESET_VALUE(1), .PROG_EMPTY_THRESH(10), .PROG_FULL_THRESH(1014),
 .RD_DATA_COUNT_WIDTH(11), .READ_DATA_WIDTH(32), .READ_MODE("std"),
 .RELATED_CLOCKS(0), .USE_ADV_FEATURES("0707"), .WAKEUP_TIME(0),
 .WRITE_DATA_WIDTH(32), .WR_DATA_COUNT_WIDTH(11)
) u_tx_async_fifo (
 .almost_empty(), .almost_full(), .data_valid(fifo_rd_valid), .dbiterr(),
 .dout(fifo_dout), .empty(fifo_empty), .full(fifo_full), .overflow(),
 .prog_empty(), .prog_full(), .rd_data_count(), .rd_rst_busy(fifo_rd_busy),
 .sbiterr(), .underflow(), .wr_ack(), .wr_data_count(), .wr_rst_busy(fifo_wr_busy),
 .din(bram_wdata_d), .injectdbiterr(1'b0), .injectsbiterr(1'b0),
 .rd_clk(gmii_rx_clk), .rd_en(udp_tx_req && !fifo_empty), .rst(fifo_rst),
 .sleep(1'b0), .wr_clk(s_axi_aclk), .wr_en(bram_we && !fifo_full)
);
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
 if(!sys_rst_n) tx_data_reg <= 32'd0;
 else if(fifo_rd_valid) tx_data_reg <= fifo_dout;
end

// AXI-Lite write capture, single owner for have_addr/have_data.
reg awready_r, wready_r;
reg [5:0] awaddr_d;
reg [31:0] wdata_d;
reg have_addr, have_data;
reg bvalid_r;
wire wr_fire = have_addr && have_data;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if(!s_axi_aresetn) begin awready_r<=0; wready_r<=0; have_addr<=0; have_data<=0; awaddr_d<=0; wdata_d<=0; end
 else begin
  awready_r<=0; wready_r<=0;
  if(wr_fire) begin have_addr<=0; have_data<=0; end
  if(s_axi_awvalid && !have_addr) begin awready_r<=1; have_addr<=1; awaddr_d<=s_axi_awaddr; end
  if(s_axi_wvalid && !have_data) begin wready_r<=1; have_data<=1; wdata_d<=s_axi_wdata; end
 end
end
assign s_axi_awready=awready_r; assign s_axi_wready=wready_r;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if(!s_axi_aresetn) bvalid_r<=0; else if(wr_fire) bvalid_r<=1; else if(s_axi_bready && bvalid_r) bvalid_r<=0;
end
assign s_axi_bvalid=bvalid_r; assign s_axi_bresp=2'b00;

// 寄存器写译码 (v5)
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        ram_wa_ps      <= 32'd0;
        bram_we        <= 1'b0;
        tx_bytes_ps    <= 16'd0;
        frame_req_clr  <= 1'b0;
        sweep_mode_ps  <= 2'd0;
        txc_phase_ps   <= 2'd0;
    end
    else begin
        bram_we       <= 1'b0;
        frame_req_clr <= 1'b0;
        if (wr_fire) begin
            case (awaddr_d[5:0])
                ADDR_CTRL: begin
                    if (wdata_d[0]) frame_req_clr <= 1'b1;
                    sweep_mode_ps <= wdata_d[2:1];
                    txc_phase_ps <= wdata_d[4:3];
                end
                ADDR_TXSTART: begin
                    /* tx_start_ps 由下方 TX-start CDC always 独占驱动 */
                end
                ADDR_TXBYTES: tx_bytes_ps <= wdata_d[15:0];
                ADDR_RAM_WA : ram_wa_ps   <= wdata_d;
                ADDR_RAM_WD : begin
                    bram_we      <= 1'b1;
                    bram_wdata_d <= wdata_d;
                    ram_wa_ps    <= ram_wa_ps + 32'd4;
                end
                default: ;
            endcase
        end
    end
end

// CDC: frame_req
reg rec_d1, rec_d2, rec_d3;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        rec_d1 <= 1'b0;  rec_d2 <= 1'b0;  rec_d3 <= 1'b0;
        frame_req_ps <= 1'b0;
    end
    else begin
        rec_d1 <= rec_pkt_done;
        rec_d2 <= rec_d1;
        rec_d3 <= rec_d2;
        if (rec_d2 && !rec_d3)
            frame_req_ps <= 1'b1;
        else if (frame_req_clr)
            frame_req_ps <= 1'b0;
    end
end

// CDC: tx_start
reg tx_start_d1, tx_start_d2, tx_start_d3;
wire tx_start_pulse = tx_start_d2 & ~tx_start_d3;
wire tx_start_ack_sync = tx_start_d2;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn)
        tx_start_ps <= 1'b0;
    else begin
        if (wr_fire && awaddr_d[5:0] == ADDR_TXSTART && wdata_d[0])
            tx_start_ps <= 1'b1;
        else if (tx_start_ack_sync)
            tx_start_ps <= 1'b0;
    end
end
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tx_start_d1 <= 1'b0;  tx_start_d2 <= 1'b0;  tx_start_d3 <= 1'b0;
    end
    else begin
        tx_start_d1 <= tx_start_ps;
        tx_start_d2 <= tx_start_d1;
        tx_start_d3 <= tx_start_d2;
    end
end

// CDC: tx_busy
reg tx_busy_d1, tx_busy_d2;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        tx_busy_d1 <= 1'b0;  tx_busy_d2 <= 1'b0;
    end
    else begin
        tx_busy_d1 <= tx_busy_eth;
        tx_busy_d2 <= tx_busy_d1;
    end
end

// AXI-Lite 读 (回到 BIN1 时序版 — BIN2 组合读致 AXI 死锁, 已定罪)
reg arready_r;
reg rvalid_r;
reg [31:0] rdata_r;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        arready_r <= 1'b0;  rvalid_r <= 1'b0;  rdata_r <= 32'd0;
        cam_diag_sync1 <= 0; cam_diag_sync2 <= 0;
        cam_fault_sync1 <= 0; cam_fault_sync2 <= 0;
    end
    else begin
        cam_diag_sync1 <= camera_axis_diag_counters;
        cam_diag_sync2 <= cam_diag_sync1;
        cam_fault_sync1 <= camera_axis_diag_faults;
        cam_fault_sync2 <= cam_fault_sync1;
        arready_r <= 1'b0;
        if (s_axi_arvalid && !rvalid_r) begin
            arready_r <= 1'b1;  rvalid_r <= 1'b1;
            case (s_axi_araddr[5:0])
                // bit4 lock, bit3:2 active phase, bit1 busy, bit0 RX request
                ADDR_STATUS : rdata_r <= {27'd0, txc_locked_d2, txc_phase_seen_d2, tx_busy_d2, frame_req_ps};
                ADDR_TXSTART: rdata_r <= gray_to_binary(cam_diag_sync2[31:0]);
                ADDR_TXBYTES: rdata_r <= gray_to_binary(cam_diag_sync2[63:32]);
                ADDR_RAM_WA : rdata_r <= gray_to_binary(cam_diag_sync2[95:64]);
                ADDR_RAM_WD : rdata_r <= gray_to_binary(cam_diag_sync2[127:96]);
                ADDR_DBG_IN_BEATS: rdata_r <= gray_to_binary(cam_diag_sync2[159:128]);
                /* 0x1C is board-proven readable.  Keep the DMA TLAST count
                   and export the live FIFO->packetizer handshake together. */
                ADDR_DBG_IN_LAST: rdata_r <= {27'd0, cam_fault_sync2};
                ADDR_DBG_IN_STALL: rdata_r <= dma_mon_stall_cycles;
                ADDR_DBG_HEART: rdata_r <= pkt_heart_d2;
                ADDR_DBG_PKT_BEATS: rdata_r <= pkt_beats_d2;
                ADDR_DBG_PKT_START: rdata_r <= pkt_start_d2;
                ADDR_DBG_UDP_REQ: rdata_r <= pkt_req_d2;
                ADDR_DBG_UDP_DONE: rdata_r <= pkt_done_d2;
                ADDR_DBG_STATE: rdata_r <= {pkt_state_d2,pkt_byte_d2[29:0]};
                ADDR_DBG_ETH: rdata_r <= {eth_rst_n, eth_clk_d2[14:0], eth_tx_d2[15:0]};
                default     : rdata_r <= 32'd0;
            endcase
        end
        else if (s_axi_rready && rvalid_r)
            rvalid_r <= 1'b0;
    end
end
assign s_axi_arready = arready_r;
assign s_axi_rvalid  = rvalid_r;
assign s_axi_rdata   = rdata_r;
assign s_axi_rresp   = 2'b00;

// Stage 3 packetizer owns udp TX when DMA stream mode is active.
// Old AXI-Lite FIFO path is retained until packetizer integration is validated.
wire pkt_tx_start;
wire [31:0] pkt_tx_data;
wire [15:0] pkt_tx_bytes;
wire pkt_frame_done;
reg [15:0] emitted_frame_id;
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) emitted_frame_id <= 16'd1;
    else if (pkt_frame_done) emitted_frame_id <= emitted_frame_id + 1'b1;
end
wire [1:0] pkt_dbg_state;
wire [15:0] pkt_dbg_axis_live;
wire [31:0] pkt_dbg_heartbeat,pkt_dbg_axis_beats,pkt_dbg_byte_steps,pkt_dbg_packet_starts,pkt_dbg_udp_reqs,pkt_dbg_udp_dones;
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
 if(!sys_rst_n) begin eth_clk_heartbeat<=0; eth_tx_active_cycles<=0; end
 else begin
   eth_clk_heartbeat <= eth_clk_heartbeat + 1'b1;
   if (gmii_tx_en) eth_tx_active_cycles <= eth_tx_active_cycles + 1'b1;
 end
end
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if(!s_axi_aresetn) begin pkt_heart_d1<=0;pkt_heart_d2<=0;pkt_beats_d1<=0;pkt_beats_d2<=0;pkt_byte_d1<=0;pkt_byte_d2<=0;pkt_start_d1<=0;pkt_start_d2<=0;pkt_req_d1<=0;pkt_req_d2<=0;pkt_done_d1<=0;pkt_done_d2<=0;pkt_state_d1<=0;pkt_state_d2<=0;pkt_live_d1<=0;pkt_live_d2<=0;eth_clk_d1<=0;eth_clk_d2<=0;eth_tx_d1<=0;eth_tx_d2<=0;end
 else begin pkt_heart_d1<=pkt_dbg_heartbeat;pkt_heart_d2<=pkt_heart_d1;pkt_beats_d1<=pkt_dbg_axis_beats;pkt_beats_d2<=pkt_beats_d1;pkt_byte_d1<=pkt_dbg_byte_steps;pkt_byte_d2<=pkt_byte_d1;pkt_start_d1<=pkt_dbg_packet_starts;pkt_start_d2<=pkt_start_d1;pkt_req_d1<=pkt_dbg_udp_reqs;pkt_req_d2<=pkt_req_d1;pkt_done_d1<=pkt_dbg_udp_dones;pkt_done_d2<=pkt_done_d1;pkt_state_d1<=pkt_dbg_state;pkt_state_d2<=pkt_state_d1;pkt_live_d1<=pkt_dbg_axis_live;pkt_live_d2<=pkt_live_d1;eth_clk_d1<=eth_clk_heartbeat;eth_clk_d2<=eth_clk_d1;eth_tx_d1<=eth_tx_active_cycles;eth_tx_d2<=eth_tx_d1;end
end
// Phase request/observation cross the same two clock domains as the existing
// packetizer diagnostics. The request is written before each DMA frame.
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
 if(!sys_rst_n) begin txc_phase_d1<=0; txc_phase_d2<=0; end
 else begin txc_phase_d1<=txc_phase_ps; txc_phase_d2<=txc_phase_d1; end
end
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if(!s_axi_aresetn) begin txc_phase_seen_d1<=0; txc_phase_seen_d2<=0; txc_locked_d1<=0; txc_locked_d2<=0; end
 else begin txc_phase_seen_d1<=txc_phase_active; txc_phase_seen_d2<=txc_phase_seen_d1; txc_locked_d1<=txc_locked; txc_locked_d2<=txc_locked_d1; end
end
wire stage3_dma_mode = 1'b1;
wire pkt_axis_tready;
wire packetizer_selected = (sweep_mode_d2 == 2'd0);
wire sweep_pulse_ready = (sweep_phase == 4'd0);
assign dma_axis_tready = packetizer_selected ? pkt_axis_tready :
                       (sweep_mode_d2 == 2'd1) ? 1'b1 : sweep_pulse_ready;

/* AXIS sweep consumers: mode 1 drains every beat; mode 2 accepts once per
   nine 125 MHz clocks, matching the old byte-at-a-time packetizer cadence. */
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
 if(!sys_rst_n) begin
   sweep_mode_d1<=0; sweep_mode_d2<=0; sweep_phase<=0;
   sweep_sink_beats<=0; sweep_sink_tlasts<=0; sweep_sink_stalls<=0;
 end else begin
   sweep_mode_d1 <= sweep_mode_ps;
   sweep_mode_d2 <= sweep_mode_d1;
   /* A deliberately finite modulo-9 period makes this test's external
      contract exact: one AXIS beat is accepted every nine read clocks. */
   if (sweep_phase == 4'd8)
     sweep_phase <= 4'd0;
   else
     sweep_phase <= sweep_phase + 1'b1;
   if(!packetizer_selected && dma_axis_tvalid && dma_axis_tready) begin
     sweep_sink_beats <= sweep_sink_beats + 1'b1;
     if(dma_axis_tlast) sweep_sink_tlasts <= sweep_sink_tlasts + 1'b1;
   end
   if(!packetizer_selected && dma_axis_tvalid && !dma_axis_tready)
     sweep_sink_stalls <= sweep_sink_stalls + 1'b1;
 end
end

dma_udp_packetizer u_dma_udp_packetizer (
 .clk(gmii_rx_clk), .rst_n(sys_rst_n), .frame_id(emitted_frame_id), .frame_done(pkt_frame_done),
 .s_axis_tdata(dma_axis_tdata), .s_axis_tkeep(dma_axis_tkeep), .s_axis_tvalid(dma_axis_tvalid && packetizer_selected), .s_axis_tready(pkt_axis_tready), .s_axis_tlast(dma_axis_tlast),
 .udp_tx_req(udp_tx_req), .udp_tx_data(pkt_tx_data), .udp_tx_start(pkt_tx_start), .udp_tx_bytes(pkt_tx_bytes), .udp_tx_done(udp_tx_done),
 .dbg_state(pkt_dbg_state),.dbg_axis_live(pkt_dbg_axis_live),.dbg_heartbeat(pkt_dbg_heartbeat),.dbg_axis_beats(pkt_dbg_axis_beats),.dbg_byte_steps(pkt_dbg_byte_steps),.dbg_packet_starts(pkt_dbg_packet_starts),.dbg_udp_reqs(pkt_dbg_udp_reqs),.dbg_udp_dones(pkt_dbg_udp_dones)
);

// TX 引擎 (v5)
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tx_start_en <= 1'b0;
        tx_byte_num <= 16'd0;
        tx_busy_eth <= 1'b0;
        rd_addr_eth <= {C_BRAM_AW{1'b0}};
    end
    else begin
        tx_start_en <= 1'b0;
        if (tx_start_pulse && !tx_busy_eth) begin
            tx_start_en <= 1'b1;
            tx_byte_num <= tx_bytes_ps;
            tx_busy_eth <= 1'b1;
            rd_addr_eth <= {C_BRAM_AW{1'b0}};
        end
        else begin
            if (udp_tx_done && tx_busy_eth)
                tx_busy_eth <= 1'b0;
        end
    end
end

udp #(
    .BOARD_MAC (P_BOARD_MAC),
    .BOARD_IP  (P_BOARD_IP ),
    .DES_MAC   (P_DES_MAC  ),
    .DES_IP    (P_DES_IP   )
) u_udp (
    .rst_n         (sys_rst_n    ),
    .gmii_rx_clk   (gmii_rx_clk  ),
    .gmii_rx_dv    (gmii_rx_dv   ),
    .gmii_rxd      (gmii_rxd     ),
    .gmii_tx_clk   (gmii_tx_clk  ),
    .gmii_tx_en    (gmii_tx_en   ),
    .gmii_txd      (gmii_txd     ),
    .rec_pkt_done  (rec_pkt_done ),
    .rec_en        (             ),
    .rec_data      (             ),
    .rec_byte_num  (             ),
    .tx_start_en   (stage3_dma_mode ? pkt_tx_start : tx_start_en),
    .tx_data       (stage3_dma_mode ? pkt_tx_data  : tx_data_reg),
    .tx_byte_num   (stage3_dma_mode ? pkt_tx_bytes : tx_byte_num),
    .tx_done       (udp_tx_done  ),
    .tx_req        (udp_tx_req   )
);

gmii_to_rgmii_phase_sweep u_gmii (
    .gmii_rx_clk   (gmii_rx_clk  ),
    .gmii_rx_dv    (gmii_rx_dv   ),
    .gmii_rxd      (gmii_rxd     ),
    .gmii_tx_clk   (gmii_tx_clk  ),
    .gmii_tx_en    (gmii_tx_en   ),
    .gmii_txd      (gmii_txd     ),
    .txc_phase_req (txc_phase_d2),
    .txc_phase_active(txc_phase_active),
    .txc_locked    (txc_locked),
    .rgmii_rxc     (rgmii_rxc    ),
    .rgmii_rx_ctl  (rgmii_rx_ctl ),
    .rgmii_rxd     (rgmii_rxd    ),
    .rgmii_txc     (rgmii_txc    ),
    .rgmii_tx_ctl  (rgmii_tx_ctl ),
    .rgmii_txd     (rgmii_txd    )
);

// Reusable board-level TX probe. The sample clock is the PHY-supplied RXC,
// so it keeps running before and during a TX burst and lets Hardware Manager
// arm on GMII TX_EN without changing the functional datapath.
generate if (ENABLE_RGMII_ILA) begin : g_rgmii_ila
ila_rgmii_tx u_ila_rgmii_tx (
    .clk   (gmii_rx_clk),
    .probe0(gmii_txd),           // GMII transmit byte
    // ODDR Q may only drive its OBUF. Probe the legal pre-ODDR GMII side;
    // loading rgmii_txd/rgmii_tx_ctl would make the physical output illegal.
    .probe1({gmii_tx_en, udp_tx_req, udp_tx_done, eth_rst_n, txc_phase_active, txc_locked}),
    .probe2({gmii_rx_dv, gmii_rxd}),
    .probe3(pkt_dbg_packet_starts),
    .probe4({pkt_dbg_udp_reqs[15:0], pkt_dbg_udp_dones[15:0]})
);
end endgenerate

endmodule
