/* phase_a_dma_smoke.c - compile after regenerated xparameters.h exposes AXI DMA UDP instance */
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_types.h"

#define DMA_PATTERN_BASE 0x12000000U
#define DMA_PATTERN_BYTES 0x00119400U

/* Generated symbol names are intentionally not guessed. After BD generation, replace DMA_DEVICE_ID with the emitted AXI DMA UDP device id. */
int phase_a_dma_pattern_smoke(u16 dma_device_id)
{
  XAxiDma dma;
  XAxiDma_Config *cfg = XAxiDma_LookupConfig(dma_device_id);
  if (!cfg) return XST_FAILURE;
  if (XAxiDma_CfgInitialize(&dma, cfg) != XST_SUCCESS) return XST_FAILURE;
  if (XAxiDma_HasSg(&dma)) return XST_FAILURE;
  /* Source must be PS-written immutable pattern, therefore flush source cache before PL reads DDR. */
  Xil_DCacheFlushRange((UINTPTR)DMA_PATTERN_BASE, DMA_PATTERN_BYTES);
  return XAxiDma_SimpleTransfer(&dma, DMA_PATTERN_BASE, DMA_PATTERN_BYTES, XAXIDMA_DMA_TO_DEVICE);
}