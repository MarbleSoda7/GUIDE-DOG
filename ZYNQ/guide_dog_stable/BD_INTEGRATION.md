# BD Integration Checklist

## New IP

- AXI DMA: MM2S enabled, S2MM disabled, simple mode first.
- AXI Stream Data FIFO: asynchronous clock option enabled.
- frame DMA control may use AXI DMA native AXI-Lite; custom control not needed for Phase A.

## Connections

1. AXI DMA M_AXI_MM2S -> new SmartConnect MI -> PS S_AXI_HP0.
2. AXI DMA M_AXIS_MM2S -> AXIS async FIFO S_AXIS.
3. FIFO M_AXIS remains unconnected in Phase A/B, then connects to packetizer in Phase C.
4. AXI DMA S_AXI_LITE -> PS GP0 peripheral interconnect.
5. DMA memory clock and AXI-Lite clock = FCLK 100MHz.
6. FIFO write clock = DMA AXIS clock; read clock will be UDP/RGMII TX clock only in Phase C.

## Do not change

- Existing AXI VDMA HP0 path.
- Existing OV5640/video AXIS links.
- Existing HDMI clocking.
- Existing frame stores until frame ownership design is approved.

## Generated evidence to save

- Updated zynq.bd and wrapper.
- AXI DMA xci/DCP.
- Dedicated Phase-A BIT/DCP/MD5.
- Address map from generated xparameters.h.