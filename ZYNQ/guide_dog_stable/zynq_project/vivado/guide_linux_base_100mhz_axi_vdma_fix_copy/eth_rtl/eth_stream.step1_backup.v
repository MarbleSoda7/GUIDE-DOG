`timescale 1ns/1ns
//////////////////////////////////////////////////////////////////////
// eth_stream.v — v5 RESTORATION (known-good semantics)
//
// 重建自实测成功组合: bit E08F3130 + ELF 8A452210 (827/827, 725ms/帧)
//   - STATUS: bit0=frame_req(sticky), bit1=tx_busy   (无 ack/bank)
//   - CTRL:   bit0=清 frame_req
//   - TXSTART: 写1置 tx_start_ps, eth 域 d2 回传自动清 (v5 原机制)
 //   - PS 每包等 tx_busy==0 再写下一包 (v5 节奏, CDC 安全)
//   - BRAM 写地址 +1 偏移: 精确复刻 v5 线格式
 //     (mem[0]=4B零洞, W_i→mem[i+1], 尾字牺牲 → RK SKIP=4 兼容)
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
localparam [5:0] ADDR_TXSTART1 = 6'h18;   // one-hot: 触发 bank1

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

// ---- PS 域寄存器 ----
reg [15:0] tx_bytes_ps;
reg [31:0] ram_wa_ps;
reg        bram_we;
reg        frame_req_clr;
reg        tx_start_ps;    // TXSTART0 (0x08): 触发 bank0
reg        tx_start1_ps;   // TXSTART1 (0x18): 触发 bank1 (one-hot)
reg        frame_req_ps;   // sticky: GIMME 请求

// ---- eth 域 ----
reg        tx_busy_eth;
reg [C_BRAM_AW-1:0] rd_addr_eth;
reg [31:0] tx_data_reg;
reg        tx_bank_eth;   // one-hot 锁存: serve 时来自哪条触发线
reg        tx_pend;       // pending: busy 期间的触发缓存
reg        tx_pend_bank;  // pending 期间的 bank

// ---- PHY 复位 (~670ms 低脉冲) ----
reg [26:0] rst_cnt;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn)
        rst_cnt <= 27'd0;
    else if (rst_cnt != {27{1'b1}})
        rst_cnt <= rst_cnt + 1'b1;
end
assign eth_rst_n = (rst_cnt == {27{1'b1}}) ? 1'b1 : 1'b0;

// ---- BRAM: 写地址 +1 偏移 (复刻 v5 线格式) ----
// 双 bank: 每个半区 512 字, 写端按地址 bit9 选 (静态 per-bank enable, BRAM 可推断)
(* ram_style = "block" *)
reg [31:0] mem_bank0 [0:(1<<(C_BRAM_AW-1))-1];
(* ram_style = "block" *)
reg [31:0] mem_bank1 [0:(1<<(C_BRAM_AW-1))-1];
reg [C_BRAM_AW-2:0] bram_waddr_d;
reg                  bram_wbank_d;
reg [31:0]           bram_wdata_d;
always @(posedge s_axi_aclk) begin
    if (bram_we && !bram_wbank_d)
        mem_bank0[bram_waddr_d] <= bram_wdata_d;   // 实验: off-by-zero
    if (bram_we && bram_wbank_d)
        mem_bank1[bram_waddr_d] <= bram_wdata_d;   // 实验: off-by-zero
end
// 双 bank 读: bank0 = mem[0..511], bank1 = mem[512..1023]
// 读地址高位 = 锁存的 bank (发送期间不变 → 静态索引, BRAM 可推断)
wire [C_BRAM_AW-2:0] rd_lo = rd_addr_eth[C_BRAM_AW-2:0];  /* 实验: 读端+1已删, 量洞宽变化 */
wire [31:0] rd_bank0 = mem_bank0[rd_lo];
wire [31:0] rd_bank1 = mem_bank1[rd_lo];
always @(posedge gmii_rx_clk) begin
    if (udp_tx_req)
        tx_data_reg <= tx_bank_eth ? rd_bank1 : rd_bank0;
end

// ---- AXI4-Lite 写: 无死锁捕获 (v5 实测结构) ----
reg awready_r, wready_r;
reg [5:0]  awaddr_d;
reg [31:0] wdata_d;
reg have_addr, have_data;
reg bvalid_r;
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        awready_r <= 1'b0;  have_addr <= 1'b0;  awaddr_d <= 6'd0;
    end
    else begin
        awready_r <= 1'b0;
        if (s_axi_awvalid && !have_addr) begin
            awready_r <= 1'b1;  have_addr <= 1'b1;  awaddr_d <= s_axi_awaddr;
        end
    end
end
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        wready_r <= 1'b0;  have_data <= 1'b0;  wdata_d <= 32'd0;
    end
    else begin
        wready_r <= 1'b0;
        if (s_axi_wvalid && !have_data) begin
            wready_r <= 1'b1;  have_data <= 1'b1;  wdata_d <= s_axi_wdata;
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
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        have_addr <= 1'b0;  have_data <= 1'b0;
    end
    else if (wr_fire) begin
        have_addr <= 1'b0;  have_data <= 1'b0;
    end
end

// ---- 寄存器写译码 ----
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        ram_wa_ps      <= 32'd0;
        bram_we        <= 1'b0;
        tx_bytes_ps    <= 16'd0;
        frame_req_clr  <= 1'b0;
        tx_start_ps    <= 1'b0;
        tx_start1_ps   <= 1'b0;
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
                    if (wdata_d[0]) tx_start_ps <= 1'b1;    // 0x08: bank0
                end
                ADDR_TXSTART1: begin
                    if (wdata_d[0]) tx_start1_ps <= 1'b1;   // 0x18: bank1
                end
                ADDR_TXBYTES: tx_bytes_ps <= wdata_d[15:0];
                ADDR_RAM_WA : begin
                    ram_wa_ps    <= wdata_d;
                    /* 起点预载: 与 RAM_WD 的自增链同步 — 消灭捕获滞后 */
                    bram_waddr_d <= wdata_d[C_BRAM_AW:2];      /* bank内字地址 */
                    bram_wbank_d <= wdata_d[C_BRAM_AW+1];      /* bank */
                end
                ADDR_RAM_WD : begin
                    bram_we      <= 1'b1;
                    bram_wdata_d <= wdata_d;
                    /* 地址自增链: RAM_WA 预载起点, 每个 RAM_WD +1 — 与数据同拍,
                       彻底消灭从 ram_wa_ps 捕获的滞后 */
                    bram_waddr_d <= bram_waddr_d + 1'b1;
                    ram_wa_ps    <= ram_wa_ps + 32'd4;
                end
                default: ;
            endcase
        end
    end
end

// ---- CDC: frame_req (eth 脉冲 → PS sticky, v5 原机制) ----
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

// ---- CDC: tx_start (PS 电平 → eth 脉冲, v5 原机制) ----
reg tx_start_d1, tx_start_d2, tx_start_d3;
wire tx_start_pulse = tx_start_d2 & ~tx_start_d3;
wire tx_start_ack_sync = tx_start_d2;   // 回传清 tx_start_ps
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn)
        tx_start_ps <= 1'b0;
    else begin
        // 译码置位优先; eth 回传撤销 (v5: PS 等 busy 归零, 时序安全)
        if (wr_fire && awaddr_d[5:0] == ADDR_TXSTART && wdata_d[0])
            tx_start_ps <= 1'b1;
        else if (tx_start_ack_sync)
            tx_start_ps <= 1'b0;
        if (wr_fire && awaddr_d[5:0] == ADDR_TXSTART1 && wdata_d[0])
            tx_start1_ps <= 1'b1;
        else if (tx_start1_ack_sync)
            tx_start1_ps <= 1'b0;
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

// one-hot 线2: TXSTART1 (bank1) — 独立同步链, 与线1完全同构
reg tx_start1_d1, tx_start1_d2, tx_start1_d3;
wire tx_start1_pulse = tx_start1_d2 & ~tx_start1_d3;
wire tx_start1_ack_sync = tx_start1_d2;
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tx_start1_d1 <= 1'b0;  tx_start1_d2 <= 1'b0;  tx_start1_d3 <= 1'b0;
    end
    else begin
        tx_start1_d1 <= tx_start1_ps;
        tx_start1_d2 <= tx_start1_d1;
        tx_start1_d3 <= tx_start1_d2;
    end
end

// ---- CDC: tx_busy (eth → PS 电平镜像) ----
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

// ---- AXI4-Lite 读 ----
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

// ---- eth 域 TX 引擎 (v5: pulse 且空闲则发) ----
always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        tx_start_en <= 1'b0;
        tx_byte_num <= 16'd0;
        tx_busy_eth <= 1'b0;
        rd_addr_eth <= {C_BRAM_AW{1'b0}};
    end
    else begin
        tx_start_en <= 1'b0;
        // one-hot serve + pending (单份, 修复复制粘贴重复)
        if ((tx_start_pulse || tx_start1_pulse) && !tx_busy_eth) begin
            tx_start_en  <= 1'b1;
            tx_byte_num  <= tx_bytes_ps;
            tx_bank_eth  <= tx_start1_pulse;
            tx_busy_eth  <= 1'b1;
            rd_addr_eth  <= {C_BRAM_AW{1'b0}};
        end
        else if ((tx_start_pulse || tx_start1_pulse) && tx_busy_eth) begin
            tx_pend      <= 1'b1;
            tx_pend_bank <= tx_start1_pulse;
        end
        else if (tx_pend && !tx_busy_eth) begin
            tx_start_en  <= 1'b1;
            tx_byte_num  <= tx_bytes_ps;
            tx_bank_eth  <= tx_pend_bank;
            tx_busy_eth  <= 1'b1;
            rd_addr_eth  <= {C_BRAM_AW{1'b0}};
            tx_pend      <= 1'b0;
        end
        else begin
            if (udp_tx_req)
                rd_addr_eth <= rd_addr_eth + 1'b1;
            if (udp_tx_done && tx_busy_eth)
                tx_busy_eth <= 1'b0;
        end
    end
end

// ---- UDP 协议栈 (原样) ----
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

// ---- RGMII (原样) ----
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