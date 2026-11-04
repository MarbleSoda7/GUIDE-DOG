`timescale 1ns/1ps
// Independent live-rate test. Source never observes TREADY.
// 72 MHz PCLK / two bytes per pixel -> 36 Mpixel/s; zero blanking.
// Behavioral 4096-entry FIFO adds 40 ns visibility latency to model CDC.
// This tests converter throughput, not Xilinx FIFO implementation/metastability.
module tb_axis_live;
  localparam integer WIDTH = 800;
  localparam integer HEIGHT = 480;
  localparam integer FRAMES = 2;
  localparam integer DEPTH = 4096;
  localparam integer PIXELS = WIDTH * HEIGHT * FRAMES;
  localparam integer WORDS_LINE = WIDTH * 3 / 4;
  localparam integer WORDS = WORDS_LINE * HEIGHT * FRAMES;
  localparam realtime PIXEL_PERIOD = 1000.0 / 36.0;
  localparam integer STALL_PERIOD = 1600;
  localparam integer STALL_CYCLES = 200;

  reg aclk = 0;
  always #5 aclk = ~aclk;
  reg aresetn = 0;
  reg [23:0] sdata = 0;
  reg svalid = 0, suser = 0, slast = 0;
  wire sready;
  wire [31:0] mdata;
  wire mvalid, muser, mlast;
  reg mready = 0;
  wire fault, fault_sof, fault_eol;
  wire [159:0] diag;
  axis_rgb24_to_32_node_diag #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axis_tdata(sdata), .s_axis_tvalid(svalid), .s_axis_tready(sready),
    .s_axis_tuser(suser), .s_axis_tlast(slast),
    .m_axis_tdata(mdata), .m_axis_tvalid(mvalid), .m_axis_tready(mready),
    .m_axis_tuser(muser), .m_axis_tlast(mlast),
    .fault(fault), .fault_sof(fault_sof), .fault_eol(fault_eol),
    .diag_counters(diag));

  reg [23:0] qdata [0:DEPTH-1];
  reg quser [0:DEPTH-1];
  reg qlast [0:DEPTH-1];
  realtime visible_at [0:DEPTH-1];
  // Each pointer has one owner. Data is presented on AXI falling edges,
  // held across rising-edge handshakes; source uses independent real time.
  integer wr_count = 0;
  integer rd_count = 0;
  integer max_occupancy = 0;
  integer overflow_count = 0;
  integer beat_count = 0;
  integer output_sofs = 0;
  integer output_eols = 0;
  integer axis_cycles = 0;
  integer stalled_valid_cycles = 0;
  integer producer_index;
  integer slot;
  reg producer_done = 0;
  reg previous_stalled = 0;
  reg [33:0] previous_payload;
  reg [31:0] expected_word;
  integer lane;

  function automatic [7:0] expected_byte(input integer byte_index);
    integer pixel_index, channel;
    begin
      pixel_index = byte_index / 3;
      channel = byte_index % 3;
      expected_byte = (pixel_index * 37 + channel * 71 +
                       (pixel_index >> 8) * 13) & 255;
    end
  endfunction
  function automatic [23:0] source_pixel(input integer pixel_index);
    begin
      source_pixel = {expected_byte(pixel_index*3+2),
                      expected_byte(pixel_index*3+1),
                      expected_byte(pixel_index*3)};
    end
  endfunction
  function automatic [31:0] gray(input integer value);
    begin gray = value ^ (value >> 1); end
  endfunction

  initial begin
    #102 aresetn = 1;
  end

  initial begin
    wait(aresetn);
    #1;
    for (producer_index = 0; producer_index < PIXELS;
         producer_index = producer_index + 1) begin
      if (wr_count - rd_count >= DEPTH) begin
        overflow_count = overflow_count + 1;
        $fatal(1, "LIVE_FAIL FIFO_OVERFLOW pixel=%0d occupancy=%0d time=%0t",
               producer_index, wr_count-rd_count, $time);
      end
      slot = wr_count % DEPTH;
      qdata[slot] = source_pixel(producer_index);
      quser[slot] = (producer_index % (WIDTH*HEIGHT) == 0);
      qlast[slot] = (producer_index % WIDTH == WIDTH-1);
      visible_at[slot] = $realtime + 40.0;
      wr_count = wr_count + 1;
      if (wr_count-rd_count > max_occupancy)
        max_occupancy = wr_count-rd_count;
      #(PIXEL_PERIOD);
    end
    producer_done = 1;
  end

  always @(negedge aclk) begin
    if (!aresetn) begin
      svalid = 0;
      mready = 0;
    end else begin
      // 200 consecutive cycles of backpressure every 1600 cycles.
      mready = (axis_cycles % STALL_PERIOD >= STALL_CYCLES);
      if (wr_count > rd_count &&
          $realtime >= visible_at[rd_count % DEPTH]) begin
        sdata = qdata[rd_count % DEPTH];
        suser = quser[rd_count % DEPTH];
        slast = qlast[rd_count % DEPTH];
        svalid = 1;
      end else begin
        svalid = 0;
        suser = 0;
        slast = 0;
      end
    end
  end

  always @(posedge aclk) begin
    if (aresetn) begin
      axis_cycles = axis_cycles + 1;
      if (previous_stalled &&
          (!mvalid || {muser,mlast,mdata} !== previous_payload))
        $fatal(1, "LIVE_FAIL output changed while stalled beat=%0d", beat_count);
      previous_stalled = mvalid && !mready;
      previous_payload = {muser,mlast,mdata};
      if (previous_stalled) stalled_valid_cycles = stalled_valid_cycles + 1;
      if (svalid && sready) rd_count = rd_count + 1;
      if (mvalid && mready) begin
        if (beat_count >= WORDS)
          $fatal(1, "LIVE_FAIL extra output beat");
        for (lane = 0; lane < 4; lane = lane + 1)
          expected_word[lane*8 +: 8] = expected_byte(beat_count*4+lane);
        if (mdata !== expected_word)
          $fatal(1, "LIVE_FAIL data beat=%0d got=%08x expected=%08x",
                 beat_count, mdata, expected_word);
        if (muser !== (beat_count % (WORDS_LINE*HEIGHT) == 0))
          $fatal(1, "LIVE_FAIL SOF beat=%0d value=%b", beat_count, muser);
        if (mlast !== (beat_count % WORDS_LINE == WORDS_LINE-1))
          $fatal(1, "LIVE_FAIL EOL beat=%0d value=%b", beat_count, mlast);
        if (muser) output_sofs = output_sofs + 1;
        if (mlast) output_eols = output_eols + 1;
        beat_count = beat_count + 1;
        if (beat_count == WORDS) begin
          #1;
          if (wr_count != PIXELS || rd_count != PIXELS ||
              wr_count != rd_count || overflow_count != 0 ||
              output_sofs != FRAMES || output_eols != FRAMES*HEIGHT ||
              stalled_valid_cycles == 0 ||
              fault !== 0 || fault_sof !== 0 || fault_eol !== 0)
            $fatal(1, "LIVE_FAIL final counts/faults wr=%0d rd=%0d sof=%0d eol=%0d faults=%b%b%b",
                   wr_count,rd_count,output_sofs,output_eols,fault,fault_sof,fault_eol);
          if (diag !== {gray(FRAMES*HEIGHT),gray(WORDS),gray(FRAMES*HEIGHT),
                        gray(FRAMES),gray(PIXELS)})
            $fatal(1, "LIVE_FAIL diagnostic counts mismatch got=%040x", diag);
          $display("LIVE_PASS frames=%0d pixels=%0d output_beats=%0d bytes=%0d SOF=%0d EOL=%0d max_queue=%0d/%0d overflow=%0d stalled_valid_cycles=%0d time_ns=%0.3f",
                   FRAMES,rd_count,beat_count,beat_count*4,output_sofs,output_eols,
                   max_occupancy,DEPTH,overflow_count,stalled_valid_cycles,$realtime);
          $finish;
        end
      end
    end
  end

  initial begin
    #50000000;
    $fatal(1, "LIVE_FAIL TIMEOUT produced=%0d consumed=%0d beats=%0d occupancy=%0d done=%b",
           wr_count,rd_count,beat_count,wr_count-rd_count,producer_done);
  end
endmodule
