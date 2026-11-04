# Static Design Review

Date: 2026-09-21

## Review outcome

Architecture selected: AXI DMA MM2S -> AXIS async FIFO -> legacy UDP packetizer.

## Assertions verified from existing project

- PS HP0 is enabled and 64-bit.
- Existing VDMA already has 64-bit MM2S/S2MM memory data width and uses HP0 path.
- Frame bytes 0x00119400 divides exactly by 8, so initial 64-bit DMA reads have no final partial beat.
- Adapter accepts 64-bit AXIS beat and supplies legacy UDP 32-bit words in high-word then low-word order.
- Adapter retains TLAST and raises frame_done only after second 32-bit word.

## Known unresolved integration items

- AXI DMA IP and SmartConnect connection are not yet added to the BD; tomorrow Phase A does this.
- Existing UDP TX does not use AXIS. Adapter must be extended with explicit 4B hole and per-packet 6B header, not directly wired as current skeleton.
- Live camera source is blocked by frame ownership: three 30fps stores are insufficient for 92ms raw 100Mbps send without immutable staging or more stores.
- AXI DMA simple-mode validation starts only from PS-written immutable DDR test pattern.

## No-go conditions

- No custom AXI HP0 burst master tomorrow.
- No raw RGMII-clocked BRAM management.
- No direct DMA from a currently-written VDMA slot.
- No performance claims before pattern DMA and RK packet correctness pass.