# PL kernel host regression

No HLS/Vivado/SD build is started by these tests. The hardware resource, timing,
burst-inference and generated register-map reports remain UNVERIFIED until an
authorized HLS run. All edits for this task are limited to the kernel and tests.

## Run

From the repository root:

    python -B tests/test_pl_kernel.py -v

This checks the source-level ABI, single AXI bundle, cache access sites, LUT bound,
actual edge spans, and full raster coverage. It compiles/runs the standalone C++
reference test if g++/clang++ is on PATH, or if CXX names a compiler executable.
A missing compiler is reported as SKIP, never as a runtime-test PASS.

Alternatively, in zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy:

    g++ -std=c++14 -O2 -Wall -Wextra -Werror -Wno-unknown-pragmas pl_remap_accel_host_test.cpp -o test_pl_kernel
    ./test_pl_kernel

The test defaults to PL_REMAP_HOST (uint64_t/uint32_t; no HLS headers). To test the
ap_uint path with an installed HLS header toolchain, compile the same test with
-DPL_REMAP_TEST_AP_UINT and the appropriate ap_int.h include path. The HLS kernel
itself defaults to ap_uint; PL_REMAP_HOST is for host tests only. Optional host
sanitizers: -fsanitize=address,undefined -fno-omit-frame-pointer.

## Numeric and memory contract

* Fixed 800x480 RGB888, row-major RGB bytes, 1,152,000 bytes/frame.
* One gmem m_axi bundle; src/lut/dst are 64-bit words, 8-byte aligned and
  non-overlapping. Low byte lane is the first byte in DDR. Output is a contiguous
  sequence of 144,000 64-bit stores, buffered/issued 300 words per row.
* Runtime step=8: 101x61=6161 32-bit nodes, payload 24644 bytes, DMA-readable
  allocation at least 24648 bytes (last 4 bytes padding). step=16: 51x31=1581
  nodes, payload 6324 bytes, allocation at least 6328 bytes. No RMP header in LUT.
* Nodes are {sx:uint16, sy:uint16}, little endian, unsigned Q10.6; either
  component 0xffff invalidates all touching cells. Invalid pixels are black.
* A row of cell corners is loaded once from preloaded LUT BRAM, then reused
  across the whole cell height. No per-pixel LUT or source-DDR byte reads.
* Node positions are min(grid_index*step, dimension-1). Final spans are 15
  (step16) or 7 (step8), not the nominal step. Shared cell boundaries belong
  to the following cell; the final cell includes the last image coordinate.
* Grid interpolation floors each horizontal and vertical stage, preserving
  the prior Q10.6 convention. RGB bilinear interpolation rounds half up at /4096.
* Exact source x=799/y=479 is valid with replicated edge neighbor. Coordinates
  beyond those limits are invalid. Identity preserves the last row/column.
* Source cache: 64 direct-mapped lines x128 bytes=8192 bytes, cold per invocation;
  miss fills 16 contiguous 64-bit words. Identity produces 9000 line misses.
* CRC-32/ISO-HDLC (IEEE): reflected 0xedb88320, init/xorout 0xffffffff, over
  every output byte including black invalid pixels. Known vector: 123456789
  gives 0xcbf43926.

## Explicit AXI-Lite ABI

| Value | Data offset(s) | Meaning |
|---|---|---|
| src | 0x10/0x14 | 64-bit source address |
| lut | 0x1c/0x20 | 64-bit node-payload address |
| dst | 0x28/0x2c | 64-bit output address |
| step | 0x34 | 8 or 16 |
| status | 0x40 | 0 success; 1 unsupported step |
| invalid_count | 0x50 | Number of black-filled pixels |
| cache_miss_count | 0x60 | Number of 128-byte source line fills |
| pixel_count | 0x70 | 384000 on success, 0 on unsupported step |
| crc | 0x80 | IEEE output CRC |

Read diagnostics after AP_CTRL done. Unsupported step touches no DDR and zeros
all counters/CRC. Output references are scalar AXI-Lite registers, not extra
m_axi ports. Check the emitted register map after synthesis before deploying.

## Runtime cases

Sixteen full-frame reference comparisons: step8 and step16 each with identity,
integer shift, fractional affine map, all invalid, one invalid X node, fully
out-of-range mapping, invalid final Y node, and deterministic warped map. Checks
include exact output bytes, IEEE CRC, invalid/pixel counters, edge spans, output
guards, unchanged inputs, cold cache across repeated calls and cache misses.
Seven unsupported steps verify no DDR access, output preservation and diagnostics.
