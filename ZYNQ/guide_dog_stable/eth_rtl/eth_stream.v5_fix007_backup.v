`timescale 1ns/1ns
//////////////////////////////////////////////////////////////////////
// eth_stream.v — 纯 v5 语义 (二分第1轮: AXI + 单bank + v5引擎)
// 与 09-18 陈旧 dcp 行为对齐的最小完整发送链
//////////////////////////////////////////////////////////////////////
module eth_stream #(
    parameter integer C_BRAM_AW = 10,
    parameter [47:0] P_BOARD_MAC = 48'h12_34_56_78_9a_bc,
    parameter [31:0] P_BOARD_IP  = {8'd10, 8'd212, 8'd211, 8'd3},
    parameter [47:0] P_DES_MAC   = 48'hff_ff_ff_ff_ff_ff,
    parameter [31:0] P_DES_IP    = {8'd10, 8'd212, 8'd211, 8'd2}
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
    output wire        eth_rst_n
);

localparam [5:0] ADDR_STATUS   = 6'h00;
localparam [5:0] ADDR_CTRL     = 6'h04;
localparam [5:0] ADDR_TXSTART  = 6'h08;
localparam [5:0] ADDR_TXBYTES  = 6'h0C;
localparam [5:0] ADDR_RAM_WA   = 6'h10;
localparam [5:0] ADDR_RAM_WD   = 6'h14;

wire gmii_rx_clk;
wire gmii_rx_dv;
wire [7:0] gmii_rxd;
wire gmii_tx_clk;
wire gmii_tx_en;
wire [7:0] gmii_txd;
wire rec_pkt_done;
wire udp_tx_req;
wire udp_tx_done;
reg  tx_start_en;
reg  [15:0] tx_byte_num;

reg [15:0] tx_bytes_ps;
reg [31:0] ram_wa_ps;
reg        bram_we;
reg        frame_req_clr;
reg        tx_start_ps;
reg        frame_req_ps;

reg        tx_busy_eth;
reg [C_BRAM_AW-1:0] rd_addr_eth;
reg [31:0] tx_data_reg;

// PHY 复位
reg [26:0] rst_cnt;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn)
        rst_cnt <= 27'd0;
    else if (rst_cnt != {27{1'b1}})
        rst_cnt <= rst_cnt + 1'b1;
end
assign eth_rst_n = (rst_cnt == {27{1'b1}}) ? 1'b1 : 1'b0;

// 单 bank BRAM + off-by-one (v5 原语义)
(* ram_style = "block" *)
reg [31:0] mem [0:(1<<C_BRAM_AW)-1];
reg [C_BRAM_AW-1:0] bram_waddr_d;
reg [31:0]          bram_wdata_d;
always @(posedge s_axi_aclk) begin
    if (bram_we)
        mem[bram_waddr_d + 1'b1] <= bram_wdata_d;
end
always @(posedge gmii_rx_clk) begin
    if (udp_tx_req)
        tx_data_reg <= mem[rd_addr_eth];
end

// AXI-Lite 写捕获 (无死锁, v5 结构)
reg awready_r, wready_r;
reg [5:0]  awaddr_d;
reg [31:0] wdata_d;
reg have_addr, have_data;
reg bvalid_r;
// AXI-Lite 捕获/清零: have_addr/have_data 各只有一个时序驱动块
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        awready_r <= 1'b0;
        wready_r  <= 1'b0;
        have_addr <= 1'b0;
        have_data <= 1'b0;
        awaddr_d  <= 6'd0;
        wdata_d   <= 32'd0;
    end
    else begin
        awready_r <= 1'b0;
        wready_r  <= 1'b0;
        if (wr_fire) begin
            have_addr <= 1'b0;
            have_data <= 1'b0;
        end
        if (s_axi_awvalid && !have_addr) begin
            awready_r <= 1'b1;
            have_addr <= 1'b1;
            awaddr_d  <= s_axi_awaddr;
        end
        if (s_axi_wvalid && !have_data) begin
            wready_r  <= 1'b1;
            have_data <= 1'b1;
            wdata_d   <= s_axi_wdata;
        end
    end
end
assign s_axi_awready = awready_r;
assign s_axi_wready  = wready_r;
wire wr_fire = have_addr && have_data;

always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn)
        bvalid_r <= 1'b0;
    else if (wr_fire)
        bvalid_r <= 1'b1;
    else if (s_axi_bready && bvalid_r)
        bvalid_r <= 1'b0;
end
assign s_axi_bvalid = bvalid_r;
assign s_axi_bresp  = 2'b00;

// 寄存器写译码 (v5)
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        ram_wa_ps      <= 32'd0;
        bram_we        <= 1'b0;
        tx_bytes_ps    <= 16'd0;
        frame_req_clr  <= 1'b0;
    end
    else begin
        bram_we       <= 1'b0;
        frame_req_clr <= 1'b0;
        if (wr_fire) begin
            case (awaddr_d[5:0])
                ADDR_CTRL: begin
                    if (wdata_d[0]) frame_req_clr <= 1'b1;
                end
                ADDR_TXSTART: begin
                    /* tx_start_ps 由下方 TX-start CDC always 独占驱动 */
                end
                ADDR_TXBYTES: tx_bytes_ps <= wdata_d[15:0];
                ADDR_RAM_WA : ram_wa_ps   <= wdata_d;
                ADDR_RAM_WD : begin
                    bram_we      <= 1'b1;
                    bram_wdata_d <= wdata_d;
                    bram_waddr_d <= ram_wa_ps[C_BRAM_AW+1:2];
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
    end
    else begin
        arready_r <= 1'b0;
        if (s_axi_arvalid && !rvalid_r) begin
            arready_r <= 1'b1;  rvalid_r <= 1'b1;
            case (s_axi_araddr[5:0])
                ADDR_STATUS : rdata_r <= {30'd0, tx_busy_d2, frame_req_ps};
                ADDR_TXBYTES: rdata_r <= {16'd0, tx_bytes_ps};
                ADDR_RAM_WA : rdata_r <= ram_wa_ps;
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
            if (udp_tx_req)
                rd_addr_eth <= rd_addr_eth + 1'b1;
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
    .tx_start_en   (tx_start_en  ),
    .tx_data       (tx_data_reg  ),
    .tx_byte_num   (tx_byte_num  ),
    .tx_done       (udp_tx_done  ),
    .tx_req        (udp_tx_req   )
);

gmii_to_rgmii u_gmii (
    .gmii_rx_clk   (gmii_rx_clk  ),
    .gmii_rx_dv    (gmii_rx_dv   ),
    .gmii_rxd      (gmii_rxd     ),
    .gmii_tx_clk   (gmii_tx_clk  ),
    .gmii_tx_en    (gmii_tx_en   ),
    .gmii_txd      (gmii_txd     ),
    .rgmii_rxc     (rgmii_rxc    ),
    .rgmii_rx_ctl  (rgmii_rx_ctl ),
    .rgmii_rxd     (rgmii_rxd    ),
    .rgmii_txc     (rgmii_txc    ),
    .rgmii_tx_ctl  (rgmii_tx_ctl ),
    .rgmii_txd     (rgmii_txd    )
);

endmodule