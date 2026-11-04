// Fixed 800x480, packed RGB888. One 64-bit AXI master (gmem).
// LUT nodes: little-endian {uint16_t sx, uint16_t sy}, unsigned Q10.6.
// step is 8 or 16; nodes lie at min(index * step, dimension - 1).
// src/dst: 1,152,000 bytes, 8-byte aligned, non-overlapping.
// LUT: 6161 (step8) or 1581 (step16) nodes; pad to a whole 64-bit word.
// status: 0 = success, 1 = unsupported step (no DDR access/output writes).
// invalid_count counts black-filled output pixels; cache_miss_count counts
// 128-byte source line fills; pixel_count counts all emitted pixels.
// crc is CRC-32/ISO-HDLC (IEEE), over all RGB888 output bytes in raster order.

#include <stdint.h>
#ifdef PL_REMAP_HOST
typedef uint64_t word_t;
typedef uint32_t node_t;
#else
#include <ap_int.h>
typedef ap_uint<64> word_t;
typedef ap_uint<32> node_t;
#endif

static const unsigned WIDTH = 800, HEIGHT = 480, FRAC_BITS = 6;
static const unsigned CHANNELS = 3, ROW_BYTES = WIDTH * CHANNELS;
static const unsigned ROW_WORDS = ROW_BYTES / 8;
static const unsigned FRAME_BYTES = ROW_BYTES * HEIGHT;
static const unsigned MAX_LUT_NODES = 6161, MAX_CELL_COLS = 100;
static const unsigned INVALID = 0xffff;
static const unsigned CACHE_LINES = 64, CACHE_LINE_BYTES = 128;
static const unsigned CACHE_LINE_WORDS = CACHE_LINE_BYTES / 8;
static_assert(CACHE_LINES * CACHE_LINE_BYTES >= 8192, "8KiB source cache required");
static_assert(FRAME_BYTES % CACHE_LINE_BYTES == 0, "full source cache lines");
static_assert(ROW_BYTES % 8 == 0, "whole output words per row");

static unsigned crc_byte(unsigned crc, unsigned byte) {
#pragma HLS INLINE
    crc ^= byte;
    for (unsigned bit = 0; bit < 8; ++bit) {
#pragma HLS UNROLL
        crc = (crc >> 1) ^ ((0u - (crc & 1u)) & 0xedb88320u);
    }
    return crc;
}

static unsigned node_x(node_t n) {
#pragma HLS INLINE
    return (unsigned)(n & 0xffffu);
}
static unsigned node_y(node_t n) {
#pragma HLS INLINE
    return (unsigned)(n >> 16);
}
static bool node_valid(node_t n) {
#pragma HLS INLINE
    return node_x(n) != INVALID && node_y(n) != INVALID;
}

// Only these actual spans occur: step 8/16, or the final cell 7/15.
// Constant divisors avoid a general variable divider in coordinate interpolation.
static unsigned divide_span(unsigned numerator, unsigned span) {
#pragma HLS INLINE
    if (span == 8) return numerator / 8u;
    if (span == 16) return numerator / 16u;
    if (span == 7) return numerator / 7u;
    if (span == 15) return numerator / 15u;
    return 0; // Unreachable for the validated geometry.
}
// Floor horizontally before the vertical floor, preserving the Q10.6 contract.
// Sampled numerators are nonnegative; signed storage permits decreasing slopes.
static unsigned interp_from_numerators(int32_t top_num, int32_t bot_num,
                                       unsigned dy, unsigned span_x, unsigned span_y) {
#pragma HLS INLINE
    const unsigned top = divide_span((unsigned)top_num, span_x);
    const unsigned bot = divide_span((unsigned)bot_num, span_x);
    return divide_span(top * (span_y - dy) + bot * dy, span_y);
}

// The ONLY source-DDR read site is this sequential 16 x 64-bit line fill.
// Byte extraction after the fill is from BRAM, never a random DDR byte load.
static unsigned cached_byte(const word_t *src, unsigned address,
                            word_t cache[CACHE_LINES][CACHE_LINE_WORDS],
                            unsigned tags[CACHE_LINES], bool valid[CACHE_LINES],
                            unsigned &misses) {
#pragma HLS INLINE
    const unsigned line = address / CACHE_LINE_BYTES;
    const unsigned slot = line & (CACHE_LINES - 1);
    if (!valid[slot] || tags[slot] != line) {
        const unsigned base_word = line * CACHE_LINE_WORDS;
        for (unsigned i = 0; i < CACHE_LINE_WORDS; ++i) {
#pragma HLS PIPELINE II=1
            cache[slot][i] = src[base_word + i];
        }
        tags[slot] = line;
        valid[slot] = true;
        ++misses;
    }
    const word_t w = cache[slot][(address % CACHE_LINE_BYTES) / 8];
    return (unsigned)((w >> ((address & 7u) * 8)) & 0xffu);
}

static unsigned sample_channel(const word_t *src, unsigned sx, unsigned sy, unsigned c,
                               word_t cache[CACHE_LINES][CACHE_LINE_WORDS],
                               unsigned tags[CACHE_LINES], bool valid[CACHE_LINES],
                               unsigned &misses) {
#pragma HLS INLINE
    const unsigned x0 = sx >> FRAC_BITS, y0 = sy >> FRAC_BITS;
    // Exact last-column/row coordinates are legal; repeat the edge neighbor.
    const unsigned x1 = x0 + (x0 + 1 < WIDTH ? 1u : 0u);
    const unsigned y1 = y0 + (y0 + 1 < HEIGHT ? 1u : 0u);
    const unsigned fx = sx & 63u, fy = sy & 63u;
    const unsigned a = cached_byte(src, (y0 * WIDTH + x0) * 3 + c, cache, tags, valid, misses);
    const unsigned b = cached_byte(src, (y0 * WIDTH + x1) * 3 + c, cache, tags, valid, misses);
    const unsigned d = cached_byte(src, (y1 * WIDTH + x0) * 3 + c, cache, tags, valid, misses);
    const unsigned e = cached_byte(src, (y1 * WIDTH + x1) * 3 + c, cache, tags, valid, misses);
    const unsigned top = a * (64 - fx) + b * fx;
    const unsigned bot = d * (64 - fx) + e * fx;
    return (top * (64 - fy) + bot * fy + 2048) >> 12;
}

extern "C" void pl_remap_accel(const word_t *src, const word_t *lut, word_t *dst,
                               unsigned step, unsigned &status,
                               unsigned &invalid_count, unsigned &cache_miss_count,
                               unsigned &pixel_count, unsigned &crc) {
#pragma HLS INTERFACE m_axi port=src offset=slave bundle=gmem depth=144000 max_read_burst_length=16
#pragma HLS INTERFACE m_axi port=lut offset=slave bundle=gmem depth=3081 max_read_burst_length=16
#pragma HLS INTERFACE m_axi port=dst offset=slave bundle=gmem depth=144000 max_write_burst_length=16
#pragma HLS INTERFACE s_axilite port=src bundle=control offset=0x10
#pragma HLS INTERFACE s_axilite port=lut bundle=control offset=0x1c
#pragma HLS INTERFACE s_axilite port=dst bundle=control offset=0x28
#pragma HLS INTERFACE s_axilite port=step bundle=control offset=0x34
#pragma HLS INTERFACE s_axilite port=status bundle=control offset=0x40
#pragma HLS INTERFACE s_axilite port=invalid_count bundle=control offset=0x50
#pragma HLS INTERFACE s_axilite port=cache_miss_count bundle=control offset=0x60
#pragma HLS INTERFACE s_axilite port=pixel_count bundle=control offset=0x70
#pragma HLS INTERFACE s_axilite port=crc bundle=control offset=0x80
#pragma HLS INTERFACE s_axilite port=return bundle=control
    status = 0;
    invalid_count = 0;
    cache_miss_count = 0;
    pixel_count = 0;
    crc = 0;
    if (step != 8 && step != 16) {
        status = 1;
        return;
    }

    node_t nodes[MAX_LUT_NODES];
#pragma HLS BIND_STORAGE variable=nodes type=ram_2p impl=bram
    word_t cache[CACHE_LINES][CACHE_LINE_WORDS];
#pragma HLS BIND_STORAGE variable=cache type=ram_2p impl=bram
    unsigned tags[CACHE_LINES];
    bool valid[CACHE_LINES];
    word_t row_words[ROW_WORDS];
#pragma HLS BIND_STORAGE variable=row_words type=ram_2p impl=bram
    // Retain one row of cells while traversing its pixels in raster order.
    // Each cell's four corners are fetched from nodes exactly once per frame.
    node_t corners[MAX_CELL_COLS][4];
#pragma HLS ARRAY_PARTITION variable=corners complete dim=2
#pragma HLS BIND_STORAGE variable=corners type=ram_2p impl=bram
    bool cell_valid[MAX_CELL_COLS];
    const unsigned cols = WIDTH / step + 1;
    const unsigned rows = HEIGHT / step + 1;
    const unsigned count = cols * rows;
    for (unsigned i = 0; i < CACHE_LINES; ++i) {
#pragma HLS PIPELINE II=1
        valid[i] = false;
    }
    for (unsigned i = 0; i < (count + 1) / 2; ++i) {
#pragma HLS PIPELINE II=1
        const word_t w = lut[i];
        nodes[2 * i] = (node_t)w;
        if (2 * i + 1 < count) nodes[2 * i + 1] = (node_t)(w >> 32);
    }

    unsigned bad = 0, misses = 0, pixels = 0, running_crc = 0xffffffffu;
    for (unsigned gy = 0; gy < rows - 1; ++gy) {
        const unsigned y0 = gy * step;
        const unsigned y1 = (y0 + step < HEIGHT) ? y0 + step : HEIGHT - 1;
        const unsigned span_y = y1 - y0;
        const unsigned cell_height = (gy == rows - 2) ? span_y + 1 : span_y;
        for (unsigned gx = 0; gx < cols - 1; ++gx) {
            const unsigned i = gy * cols + gx;
            const node_t a = nodes[i], b = nodes[i + 1];
            const node_t c = nodes[i + cols], d = nodes[i + cols + 1];
            corners[gx][0] = a; corners[gx][1] = b;
            corners[gx][2] = c; corners[gx][3] = d;
            cell_valid[gx] = node_valid(a) && node_valid(b) && node_valid(c) && node_valid(d);
        }
        for (unsigned dy = 0; dy < cell_height; ++dy) {
            word_t packed = 0;
            unsigned byte_lane = 0, out_index = 0;
            for (unsigned gx = 0; gx < cols - 1; ++gx) {
                const unsigned x0 = gx * step;
                const unsigned x1 = (x0 + step < WIDTH) ? x0 + step : WIDTH - 1;
                const unsigned span_x = x1 - x0;
                const unsigned cell_width = (gx == cols - 2) ? span_x + 1 : span_x;
                const node_t a = corners[gx][0], b = corners[gx][1];
                const node_t c = corners[gx][2], d = corners[gx][3];
                // a*span + dx*(b-a), advanced by signed addition only.
                // At every sampled dx these four numerators are in [0, 65535*16].
                int32_t sx_top_num = (int32_t)node_x(a) * (int32_t)span_x;
                int32_t sx_bot_num = (int32_t)node_x(c) * (int32_t)span_x;
                int32_t sy_top_num = (int32_t)node_y(a) * (int32_t)span_x;
                int32_t sy_bot_num = (int32_t)node_y(c) * (int32_t)span_x;
                const int32_t sx_top_delta = (int32_t)node_x(b) - (int32_t)node_x(a);
                const int32_t sx_bot_delta = (int32_t)node_x(d) - (int32_t)node_x(c);
                const int32_t sy_top_delta = (int32_t)node_y(b) - (int32_t)node_y(a);
                const int32_t sy_bot_delta = (int32_t)node_y(d) - (int32_t)node_y(c);
                for (unsigned dx = 0; dx < cell_width; ++dx) {
                    unsigned sx = 0, sy = 0;
                    bool ok = cell_valid[gx];
                    if (ok) {
                        sx = interp_from_numerators(sx_top_num, sx_bot_num, dy, span_x, span_y);
                        sy = interp_from_numerators(sy_top_num, sy_bot_num, dy, span_x, span_y);
                        ok = sx <= ((WIDTH - 1) << FRAC_BITS) && sy <= ((HEIGHT - 1) << FRAC_BITS);
                    }
                    sx_top_num += sx_top_delta; sx_bot_num += sx_bot_delta;
                    sy_top_num += sy_top_delta; sy_bot_num += sy_bot_delta;
                    if (!ok) ++bad;
                    ++pixels;
                    for (unsigned channel = 0; channel < CHANNELS; ++channel) {
                        const unsigned v = ok ? sample_channel(src, sx, sy, channel, cache, tags, valid, misses) : 0;
                        packed |= (word_t)v << (byte_lane * 8);
                        running_crc = crc_byte(running_crc, v);
                        ++byte_lane;
                        if (byte_lane == 8) {
                            row_words[out_index++] = packed;
                            packed = 0;
                            byte_lane = 0;
                        }
                    }
                }
            }
            // Separate contiguous output loop permits AXI write bursts; no RMW.
            const unsigned output_base = (y0 + dy) * ROW_WORDS;
            for (unsigned i = 0; i < ROW_WORDS; ++i) {
#pragma HLS PIPELINE II=1
                dst[output_base + i] = row_words[i];
            }
        }
    }
    invalid_count = bad;
    cache_miss_count = misses;
    pixel_count = pixels;
    crc = running_crc ^ 0xffffffffu;
}
