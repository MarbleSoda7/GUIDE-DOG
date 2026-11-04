# Phase C Packetizer Detailed Contract

## Input

- Source: AXI DMA MM2S raw frame AXIS, generated in FCLK 100MHz.
- Before packetizer, cross through AXIS async FIFO into packetizer/UDP clock domain, or run packetizer in FCLK and cross completed packet stream safely. Do not reintroduce raw RGMII-clocked RAMB.
- Each frame command must supply immutable frame data and frame_id.

## Output packet sequence

For every idx from 0 to 826:

1. bytes 0..3: zero
2. bytes 4..5: frame_id, big endian
3. bytes 6..7: total packets=827, big endian
4. bytes 8..9: packet idx, big endian
5. bytes 10..1403: exactly 1394 source bytes

The existing RK receiver uses SKIP=4 and must not change for Phase C.

## Existing UDP TX adapter

Existing udp_tx requests 32-bit words through tx_req and accepts tx_data. Packetizer must hold a word stable until the request edge and must not pop a FIFO word except when fulfilling tx_req. Packet payload transfer remains word-aligned: 1404 bytes equals 351 words.

## Correctness checks

- First pattern frame must produce fid/total/idx sequence observed by rk_hdr_v6.py.
- RK must report 827/827 before real camera source is enabled.
- Byte order must be validated by a deterministic DDR test pattern before image color diagnosis.