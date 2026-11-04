#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

/* VDMA S2MM (correct addresses from v5) */
#define VDMA_BASE       0x43000000U
#define S2MM_CTRL       (VDMA_BASE + 0x30)
#define S2MM_STAT       (VDMA_BASE + 0x34)
#define PARKPTR         (VDMA_BASE + 0x28)
#define S2MM_VSIZE      (VDMA_BASE + 0xA0)
#define S2MM_HSIZE      (VDMA_BASE + 0xA4)
#define S2MM_STRD       (VDMA_BASE + 0xA8)
#define S2MM_START1     (VDMA_BASE + 0xAC)
#define S2MM_START2     (VDMA_BASE + 0xB0)
#define S2MM_START3     (VDMA_BASE + 0xB4)

/* AXI DMA (axi_dma_udp_0, simple mode MM2S) PG021 */
#define DMA_BASE        0x40400000U
#define DMA_DMACR       (DMA_BASE + 0x00)
#define DMA_DMASR       (DMA_BASE + 0x04)
#define DMA_SA          (DMA_BASE + 0x18)  /* MM2S source addr */
#define DMA_LENGTH      (DMA_BASE + 0x28)  /* MM2S length */

/* Test region (away from capture frames) */
#define TEST_REGION     0x11000000U  /* VDMA frame 1 - actively written */
#define TEST_LEN        4096

extern unsigned char OV5640_Init(void);
extern void SCCB_Init(void);

static void dump_vdma(const char* tag){
    xil_printf("[%s] VDMA: PARK=%08x STAT=%08x\r\n", tag,
        Xil_In32(PARKPTR), Xil_In32(S2MM_STAT));
}

static void dump_dma(const char* tag){
    u32 cr = Xil_In32(DMA_DMACR);
    u32 sr = Xil_In32(DMA_DMASR);
    xil_printf("[%s] DMA: CR=%08x SR=%08x\r\n", tag, cr, sr);
    xil_printf("  halted=%d idle=%d ioc=%d err_int=%d err_slv=%d err_dec=%d\r\n",
        sr&1, (sr>>1)&1, (sr>>12)&1, (sr>>6)&1, (sr>>5)&1, (sr>>4)&1);
    xil_printf("  (bit decode: b0=halted b1=idle b12=ioc b6=interr b5=slverr b4=decerr)\r\n");
}

int main(void)
{
    xil_printf("\r\n=== STAGE 2: DMA READ TEST ===\r\n");

    /* --- Part 1: Start capture (proven sequence from v5) --- */
    SCCB_Init();
    OV5640_Init();
    Xil_Out32(S2MM_CTRL, 0x00000004);
    usleep(10000);
    Xil_Out32(S2MM_HSIZE, 2400);
    Xil_Out32(S2MM_STRD, 2400);
    Xil_Out32(S2MM_START1, 0x11000000);
    Xil_Out32(S2MM_START2, 0x11119400);
    Xil_Out32(S2MM_START3, 0x11232800);
    Xil_Out32(S2MM_CTRL, 0x00000003);
    Xil_Out32(S2MM_VSIZE, 480);  /* triggers start */
    usleep(2000000);  /* let frames flow */
    dump_vdma("capture_running");

    /* --- Part 2: DMA register evidence only --- */
    xil_printf("\r\n=== DMA REGISTER EVIDENCE ===\r\n");
    #define DUMP_DMA_OFF(off) xil_printf("DMA[0x%02x]=0x%08x\r\n", (off), Xil_In32(DMA_BASE+(off)))
    xil_printf("DMA base=0x%08x\r\n", DMA_BASE);
    for (int j=0; j<=0x40; j+=4) DUMP_DMA_OFF(j);

    xil_printf("write DMA_DMACR reset=0x00000004\r\n");
    Xil_Out32(DMA_DMACR, 0x00000004);
    usleep(10000);
    DUMP_DMA_OFF(0x00); DUMP_DMA_OFF(0x04);

    xil_printf("write source address [0x18]=0x%08x\r\n", TEST_REGION);
    Xil_Out32(DMA_SA, TEST_REGION);
    xil_printf("readback source [0x18]=0x%08x\r\n", Xil_In32(DMA_SA));

    xil_printf("write run [0x00]=0x00000001\r\n");
    Xil_Out32(DMA_DMACR, 0x00000001);
    xil_printf("readback CR=0x%08x SR=0x%08x\r\n", Xil_In32(DMA_DMACR), Xil_In32(DMA_DMASR));

    xil_printf("write length [0x28]=0x%08x\r\n", TEST_LEN);
    Xil_Out32(DMA_LENGTH, TEST_LEN);
    xil_printf("readback length [0x28]=0x%08x\r\n", Xil_In32(DMA_LENGTH));

    for (int tmo=0; tmo<20; tmo++) {
        usleep(100000);
        xil_printf("DMA_POLL_%02d: CR=0x%08x SR=0x%08x SA=0x%08x LEN=0x%08x\r\n", tmo,
          Xil_In32(DMA_DMACR), Xil_In32(DMA_DMASR), Xil_In32(DMA_SA), Xil_In32(DMA_LENGTH));
    }
    xil_printf("=== DMA REGISTER EVIDENCE END ===\r\n");

    xil_printf("=== STAGE 2 DONE ===\r\n");
    while(1){sleep(1);}
    return 0;
}