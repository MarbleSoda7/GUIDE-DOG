`timescale 1ns/1ps

// Streaming RGB24 -> AXI4-Stream RGB32 gearbox.
//
// The earlier revision stored a whole 2400-byte line in a register array and
// read four bytes per output beat.  Four read ports cannot be mapped to block
// RAM, so that structure was built from ~19k flip-flops plus a large mux tree
// (~14k LUT) per instance.  This revision keeps only a 32-bit accumulator and
// emits one word as soon as four bytes are available.  2400 bytes per line
// divide exactly into 600 words, so word boundaries stay aligned with line
// boundaries and TLAST/TUSER semantics are unchanged.
module axis_rgb24_to_32_node_diag #(
    parameter integer WIDTH = 800,
    parameter integer BPP = 3,
    parameter integer LINE_BYTES = WIDTH * BPP,
    parameter integer HEIGHT = 480
) (
    input wire aclk,
    input wire aresetn,
    input wire [23:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tuser,
    input wire s_axis_tlast,
    output wire [31:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tuser,
    output wire m_axis_tlast,
    output reg fault,
    output reg fault_sof,
    output reg fault_eol,
    output wire [159:0] diag_counters
);
    localparam integer WORDS_PER_LINE = LINE_BYTES / 4;
    localparam integer LAST_WORD = WORDS_PER_LINE - 1;
    localparam integer LAST_PIXEL = WIDTH - 1;
    localparam integer LAST_LINE = HEIGHT - 1;

    reg [31:0] acc;
    reg [2:0]  cnt;
    reg        out_valid;
    reg [31:0] out_data;
    reg        out_user;
    reg        out_last;
    reg [10:0] in_pixel;
    reg [10:0] frame_line;
    reg        synced;
    reg        sof_pending;
    reg [10:0] word_in_line;
    reg [31:0] diag_input_pixels, diag_input_sofs, diag_input_eols;
    reg [31:0] diag_output_beats, diag_output_tlasts;

    wire in_fire  = s_axis_tvalid && s_axis_tready;
    wire out_fire = out_valid && m_axis_tready;

    assign s_axis_tready = aresetn && !out_valid;
    assign m_axis_tvalid = out_valid;
    assign m_axis_tdata  = out_data;
    assign m_axis_tuser  = out_user;
    assign m_axis_tlast  = out_last;

    assign diag_counters = {
        (diag_output_tlasts ^ (diag_output_tlasts >> 1)),
        (diag_output_beats  ^ (diag_output_beats  >> 1)),
        (diag_input_eols    ^ (diag_input_eols    >> 1)),
        (diag_input_sofs    ^ (diag_input_sofs    >> 1)),
        (diag_input_pixels  ^ (diag_input_pixels  >> 1))};

    // A frame start discards any partially accumulated word so the gearbox
    // always begins a frame on a word boundary.
    wire [2:0]  base_cnt = s_axis_tuser ? 3'd0 : cnt;
    wire [31:0] base_acc = s_axis_tuser ? 32'd0 : acc;

    wire [63:0] byte0 = {56'd0, s_axis_tdata[7:0]}   << {base_cnt, 3'b000};
    wire [63:0] byte1 = {56'd0, s_axis_tdata[15:8]}  << ({base_cnt, 3'b000} + 6'd8);
    wire [63:0] byte2 = {56'd0, s_axis_tdata[23:16]} << ({base_cnt, 3'b000} + 6'd16);
    wire [63:0] stage = {32'd0, base_acc} | byte0 | byte1 | byte2;

    wire [3:0] next_cnt  = {1'b0, base_cnt} + 4'd3;
    wire       emit_now  = (next_cnt >= 4'd4);

    wire word_is_last  = (word_in_line == LAST_WORD);
    wire word_is_first = (word_in_line == 11'd0);
    wire pixel_is_last = (in_pixel == LAST_PIXEL);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            acc                <= 32'd0;
            cnt                <= 3'd0;
            out_valid          <= 1'b0;
            out_data           <= 32'd0;
            out_user           <= 1'b0;
            out_last           <= 1'b0;
            in_pixel           <= 11'd0;
            frame_line         <= 11'd0;
            synced             <= 1'b0;
            sof_pending        <= 1'b0;
            word_in_line       <= 11'd0;
            fault              <= 1'b0;
            fault_sof          <= 1'b0;
            fault_eol          <= 1'b0;
            diag_input_pixels  <= 32'd0;
            diag_input_sofs    <= 32'd0;
            diag_input_eols    <= 32'd0;
            diag_output_beats  <= 32'd0;
            diag_output_tlasts <= 32'd0;
        end else begin
            if (out_fire)
                out_valid <= 1'b0;

            if (in_fire) begin
                diag_input_pixels <= diag_input_pixels + 1'b1;

                if (s_axis_tuser) begin
                    diag_input_sofs <= diag_input_sofs + 1'b1;
                    if (synced && (in_pixel != 11'd0 || frame_line != 11'd0)) begin
                        fault     <= 1'b1;
                        fault_sof <= 1'b1;
                    end
                    frame_line   <= 11'd0;
                    in_pixel     <= 11'd1;
                    synced       <= !s_axis_tlast;
                    sof_pending  <= 1'b1;
                    word_in_line <= 11'd0;
                    if (s_axis_tlast) begin
                        fault     <= 1'b1;
                        fault_eol <= 1'b1;
                        in_pixel  <= 11'd0;
                    end
                end else if (synced) begin
                    if (s_axis_tlast != pixel_is_last) begin
                        // Never publish a line whose physical length is wrong.
                        fault     <= 1'b1;
                        fault_eol <= 1'b1;
                        synced    <= 1'b0;
                        in_pixel  <= 11'd0;
                    end else if (s_axis_tlast) begin
                        diag_input_eols <= diag_input_eols + 1'b1;
                        in_pixel        <= 11'd0;
                        if (frame_line == LAST_LINE) begin
                            synced     <= 1'b0;
                            frame_line <= 11'd0;
                        end else begin
                            frame_line <= frame_line + 1'b1;
                        end
                    end else begin
                        in_pixel <= in_pixel + 1'b1;
                    end
                end

                if (emit_now) begin
                    out_valid <= 1'b1;
                    out_data  <= stage[31:0];
                    out_user  <= sof_pending && word_is_first;
                    out_last  <= word_is_last;
                    acc       <= stage[63:32];
                    cnt       <= next_cnt - 4'd4;
                    if (word_is_last) begin
                        word_in_line <= 11'd0;
                        sof_pending  <= 1'b0;
                    end else begin
                        word_in_line <= word_in_line + 1'b1;
                    end
                end else begin
                    acc <= stage[31:0];
                    cnt <= next_cnt[2:0];
                end
            end

            if (out_fire && out_last)
                diag_output_tlasts <= diag_output_tlasts + 1'b1;
            if (out_fire)
                diag_output_beats <= diag_output_beats + 1'b1;
        end
    end
endmodule
