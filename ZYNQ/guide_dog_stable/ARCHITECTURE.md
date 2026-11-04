# Architecture Decision

Use AXI DMA MM2S as the DDR burst reader. Do not integrate custom frame_dma_reader_axi as tomorrow's primary reader.

Path:

PS frame command -> AXI DMA MM2S -> AXIS async FIFO -> UDP packetizer -> RGMII.

HP0 is a 64-bit PS AXI slave endpoint, not a DMA engine. Existing VDMA already uses it, so AXI DMA MM2S through HP0 is feasible.

Do not let RGMII RXC fabric directly manage raw dual-clock RAMB. Use AXIS async FIFO or XPM FIFO at the FCLK to RGMII boundary.

Frame ownership warning: a raw 1,152,000 byte frame requires about 92ms at 100Mbps. A 30fps, 3-store capture ring can recycle a frame in about 66ms. First DMA proof must use immutable DDR test pattern, not live capture. Camera source needs extra stores, immutable DDR staging copy, second DDR3, or reduced/compressed rate.
