# Frame DMA Reader Contract v0

## AXI-Lite registers

| Offset | Register | Access | Meaning |
|---|---|---|---|
| 0x00 | CTRL | W | bit0 START, bit1 ABORT, bit2 CLEAR_STATUS |
| 0x04 | STATUS | R | bit0 BUSY, bit1 DONE, bit2 ERROR, bit3 FIFO_FULL |
| 0x08 | FRAME_BASE | W | 32-bit aligned physical PS DDR address |
| 0x0C | BYTE_COUNT | W | frame bytes, MVP 0x00119400 |
| 0x10 | WORDS_ISSUED | R | accepted 64-bit AXI beats |
| 0x14 | ERROR_CODE | R | error reason |

## AXI HP0

- 64-bit M_AXI read master.
- ARSIZE=3, ARLEN=15 initially: 16 beats / 128 bytes per burst.
- Reader begins only for a software-selected completed VDMA slot.
- FIFO backpressure controls RREADY.

## Legacy RK wire compatibility

Packetizer must emit: [4B zero][fid BE 2][total BE 2][idx BE 2][1394 data]. Reader transports raw frame bytes only.