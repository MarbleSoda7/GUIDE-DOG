/* frame_dma_ctrl.c - Phase-B AXI DMA simple-mode implementation template. */
#include "frame_dma_ctrl.h"
#include "xaxidma.h"
#include "xil_cache.h"

/* This file is intentionally not compiled before BD creates XPAR_AXIDMA_0_* definitions. */
int frame_dma_start_mm2s(frame_dma_ctrl_t *ctx, u32 source_phys_addr, u32 byte_count)
{
  (void)ctx;
  /*
   * Tomorrow implementation requirements:
   * 1. Verify source_phys_addr is an immutable DDR region.
   * 2. Xil_DCacheFlushRange(source_phys_addr, byte_count) only for PS-written test patterns.
   * 3. Use XAxiDma_SimpleTransfer(&AxiDma, source_phys_addr, byte_count, XAXIDMA_DMA_TO_DEVICE).
   * 4. Never start from the live 3-store capture ring until frame ownership is solved.
   */
  return XST_FAILURE;
}

int frame_dma_is_done(frame_dma_ctrl_t *ctx)
{
  (void)ctx;
  return 0;
}