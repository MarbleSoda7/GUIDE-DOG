// AXI-Lite error monitor for the PL remap master. It never backpressures the master.
// Software polls REG_FLAGS/REG_*_COUNT and must poison the frame and reconfigure
// the PL after a fault; this monitor does not abort outstanding transfers.
module remap_axi_guard #(
  parameter integer C_S_AXI_ADDR_WIDTH = 6,
  parameter integer C_S_AXI_DATA_WIDTH = 32
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
  input wire aclk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
  input wire aresetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 6, FREQ_HZ 100000000" *)
  input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
  input wire s_axi_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
  output reg s_axi_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
  input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
  input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
  input wire s_axi_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
  output reg s_axi_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
  output reg [1:0] s_axi_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
  output reg s_axi_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
  input wire s_axi_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
  input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
  input wire s_axi_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
  output reg s_axi_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
  output reg [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
  output reg [1:0] s_axi_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
  output reg s_axi_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
  input wire s_axi_rready,

  // Observation-only taps on pl_remap_accel_0/m_axi_gmem. These MUST stay
  // inputs: the HLS master already drives RVALID/RRESP/BVALID/BRESP, so the
  // guard is a load on the same net and never a second driver.
  input wire rvalid,
  input wire rready,
  input wire [1:0] rresp,
  input wire bvalid,
  input wire bready,
  input wire [1:0] bresp
);
  localparam [5:0] REG_ID         = 6'h00;
  localparam [5:0] REG_FLAGS      = 6'h04;
  localparam [5:0] REG_RERR_COUNT = 6'h08;
  localparam [5:0] REG_BERR_COUNT = 6'h0c;
  localparam [5:0] REG_FIRST_RESP = 6'h10;
  localparam [5:0] REG_W1C        = 6'h14;
  localparam [5:0] REG_ABI        = 6'h1c;

  reg aw_hold, w_hold;
  reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_hold;
  reg [C_S_AXI_DATA_WIDTH-1:0] wdata_hold;
  reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_hold;
  reg [1:0] flags, flags_next;
  reg [31:0] rerr_count, berr_count;
  reg [31:0] first_resp;
  reg first_fault_valid;

  wire write_fire = aw_hold && w_hold && !s_axi_bvalid;
  wire r_fault = rvalid && rready && (rresp != 2'b00);
  wire b_fault = bvalid && bready && (bresp != 2'b00);

  function [31:0] read_reg;
    input [C_S_AXI_ADDR_WIDTH-1:0] addr;
    begin
      case (addr[5:0])
        REG_ID:         read_reg = 32'h524d5032;
        REG_FLAGS:      read_reg = {30'd0, flags};
        REG_RERR_COUNT: read_reg = rerr_count;
        REG_BERR_COUNT: read_reg = berr_count;
        REG_FIRST_RESP: read_reg = first_resp;
        REG_ABI:        read_reg = 32'd1;
        default:        read_reg = 32'd0;
      endcase
    end
  endfunction

  // A fault wins over a simultaneous W1C write, so an error cannot be cleared
  // in the same clock in which it is observed.
  always @(*) begin
    flags_next = flags;
    if (write_fire && (awaddr_hold[5:0] == REG_W1C) && wstrb_hold[0])
      flags_next = flags_next & ~wdata_hold[1:0];
    if (r_fault) flags_next[0] = 1'b1;
    if (b_fault) flags_next[1] = 1'b1;
  end

  always @(*) begin
    s_axi_awready = !aw_hold && !s_axi_bvalid;
    s_axi_wready  = !w_hold && !s_axi_bvalid;
    s_axi_arready = !s_axi_rvalid;
  end

  always @(posedge aclk) begin
    if (!aresetn) begin
      aw_hold <= 1'b0;
      w_hold <= 1'b0;
      awaddr_hold <= {C_S_AXI_ADDR_WIDTH{1'b0}};
      wdata_hold <= {C_S_AXI_DATA_WIDTH{1'b0}};
      wstrb_hold <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
      s_axi_bvalid <= 1'b0;
      s_axi_bresp <= 2'b00;
      s_axi_rvalid <= 1'b0;
      s_axi_rresp <= 2'b00;
      s_axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
      flags <= 2'b00;
      rerr_count <= 32'd0;
      berr_count <= 32'd0;
      first_resp <= 32'd0;
      first_fault_valid <= 1'b0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) begin
        aw_hold <= 1'b1;
        awaddr_hold <= s_axi_awaddr;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        w_hold <= 1'b1;
        wdata_hold <= s_axi_wdata;
        wstrb_hold <= s_axi_wstrb;
      end
      if (write_fire) begin
        aw_hold <= 1'b0;
        w_hold <= 1'b0;
        s_axi_bvalid <= 1'b1;
        s_axi_bresp <= 2'b00;
      end
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

      if (s_axi_arvalid && s_axi_arready) begin
        s_axi_rdata <= read_reg(s_axi_araddr);
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b1;
      end
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

      flags <= flags_next;
      if (r_fault) rerr_count <= rerr_count + 1'b1;
      if (b_fault) berr_count <= berr_count + 1'b1;
      if (!first_fault_valid && r_fault) begin
        first_resp[1:0] <= rresp;
        first_fault_valid <= 1'b1;
      end else if (!first_fault_valid && b_fault) begin
        first_resp[9:8] <= bresp;
        first_fault_valid <= 1'b1;
      end
    end
  end
endmodule
