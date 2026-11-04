/* Stage 3A board test: immutable DDR pattern -> AXI DMA -> UDP packetizer. */
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "sleep.h"
#include "xiltimer.h"

#define DMA_BASE             0x40400000U
#define DMA_MM2S_DMACR       (DMA_BASE + 0x00U)
#define DMA_MM2S_DMASR       (DMA_BASE + 0x04U)
#define DMA_MM2S_CURDESC     (DMA_BASE + 0x08U)
#define DMA_MM2S_TAILDESC    (DMA_BASE + 0x10U)
#define ETH_BASE             0x40000000U
#define ETH_DBG_IN_BEATS     (ETH_BASE + 0x18U)
#define ETH_DBG_IN_LAST      (ETH_BASE + 0x1CU)
#define ETH_DBG_IN_STALL     (ETH_BASE + 0x20U)
#define ETH_DBG_HEART        (ETH_BASE + 0x24U)
#define ETH_DBG_PKT_BEATS    (ETH_BASE + 0x28U)
#define ETH_DBG_PKT_START    (ETH_BASE + 0x2CU)
#define ETH_DBG_UDP_REQ      (ETH_BASE + 0x30U)
#define ETH_DBG_UDP_DONE     (ETH_BASE + 0x34U)
#define ETH_DBG_STATE        (ETH_BASE + 0x38U)

/* This region is outside the three VDMA capture buffers (0x11000000...). */
#define PATTERN_BASE         0x12000000U
#define FRAME_WIDTH          800U
#define FRAME_HEIGHT         480U
#define PAYLOAD_BYTES        1394U
#define TOTAL_PACKETS        827U
#define DMA_BYTES            (PAYLOAD_BYTES * TOTAL_PACKETS)
#define DMA_TRANSFER_BYTES   ((DMA_BYTES + 7U) & ~7U)
#define PACKETS_PER_BD       4U
#define SG_BD_COUNT          ((TOTAL_PACKETS + PACKETS_PER_BD - 1U) / PACKETS_PER_BD)
#define SG_BD_BYTES          64U
#define SG_BD_WORDS          (SG_BD_BYTES / sizeof(u32))
#define BD_NEXTDESC          0U
#define BD_BUFFER_ADDR       2U
#define BD_CONTROL           6U
#define BD_STATUS            7U
#define BD_CTRL_SOF          0x08000000U
#define BD_CTRL_EOF          0x04000000U
#define BD_CTRL_LENGTH_MASK  0x007FFFFFU
#define DMA_CR_RUNSTOP       0x00000001U
#define DMA_CR_RESET         0x00000004U
#define DMA_CR_IRQ_MASK      0x00007000U
#define DMA_SR_ERROR_MASK    0x00000070U
#define DMA_SR_IDLE          0x00000002U

/* Descriptors live in DDR via the standard linker script; 64-byte alignment
 * is an AXI DMA SG hardware requirement. */
static u32 sg_ring[SG_BD_COUNT][SG_BD_WORDS] __attribute__((aligned(SG_BD_BYTES)));

/* Performance mode deliberately avoids per-chunk UART output.  At 115200
 * baud that diagnostic traffic previously took seconds and starved the PS
 * command loop between 14-bit DMA commands. */
#define STAGE3A_PERF_MODE     1

static void fill_pattern(void)
{
    volatile u8 *dst = (volatile u8 *)PATTERN_BASE;
    u32 i;
    u32 pixel;

    /* Repeating, byte-accurate BGR bars make corruption and byte swaps visible. */
    for (pixel = 0U; pixel < FRAME_WIDTH * FRAME_HEIGHT; ++pixel) {
        u32 x = pixel % FRAME_WIDTH;
        u32 band = (x * 8U) / FRAME_WIDTH;
        i = pixel * 3U;
        dst[i + 0U] = (band & 1U) ? 0xffU : 0x00U;       /* B */
        dst[i + 1U] = (band & 2U) ? 0xffU : 0x00U;       /* G */
        dst[i + 2U] = (band & 4U) ? 0xffU : 0x00U;       /* R */
    }
    /* AXI DMA SG requires every BD length to be word aligned.  The final
       3-packet BD is 4182 B, so provide two zero pad bytes for 4184 B. */
    for (i = FRAME_WIDTH * FRAME_HEIGHT * 3U; i < DMA_TRANSFER_BYTES; ++i) dst[i] = 0U;
}

static void dump_flow(const char *tag, u32 chunk, u32 poll)
{
    u32 dmacr = Xil_In32(DMA_MM2S_DMACR);
    u32 dmasr = Xil_In32(DMA_MM2S_DMASR);
    u32 curdesc = Xil_In32(DMA_MM2S_CURDESC);
    u32 taildesc = Xil_In32(DMA_MM2S_TAILDESC);
    u32 in_beats = Xil_In32(ETH_DBG_IN_BEATS);
    u32 in_last = Xil_In32(ETH_DBG_IN_LAST);
    u32 in_stall = Xil_In32(ETH_DBG_IN_STALL);
    u32 heart = Xil_In32(ETH_DBG_HEART);
    u32 pkt_beats = Xil_In32(ETH_DBG_PKT_BEATS);
    u32 pkt_start = Xil_In32(ETH_DBG_PKT_START);
    u32 udp_req = Xil_In32(ETH_DBG_UDP_REQ);
    u32 udp_done = Xil_In32(ETH_DBG_UDP_DONE);
    u32 state = Xil_In32(ETH_DBG_STATE);

    xil_printf("STAGE3B_FLOW %s bd=%u poll=%u cr=%08x sr=%08x cur=%08x tail=%08x in_beats=%u in_last=%u in_stall=%u heart=%08x pkt_beats=%u pkt_start=%u udp_req=%u udp_done=%u state=%u\r\n",
               tag, chunk, poll, dmacr, dmasr, curdesc, taildesc, in_beats, in_last, in_stall, heart,
               pkt_beats, pkt_start, udp_req, udp_done, state);
    if ((dmasr & 0x00000070U) != 0U)
        xil_printf("STAGE3A_LOC=DMA_MM2S_ERROR\r\n");
    else if ((dmacr & 0x00000001U) == 0U)
        xil_printf("STAGE3A_LOC=DMA_MM2S_NOT_RUNNING\r\n");
    else if (in_beats == 0U && in_stall != 0U)
        xil_printf("STAGE3A_LOC=FIFO_S_AXIS_NOT_READY\r\n");
    else if (in_beats == 0U)
        xil_printf("STAGE3A_LOC=DMA_TO_FIFO_NO_TVALID_OR_MONITOR_RESET\r\n");
    else if (in_beats != 0U && heart == 0U)
        xil_printf("STAGE3A_LOC=FIFO_M_AXIS_CLOCK_OR_RESET_STOPPED\r\n");
    else if (in_beats != 0U && pkt_beats == 0U)
        xil_printf("STAGE3A_LOC=FIFO_TO_PACKETIZER_BLOCKED\r\n");
    else if (pkt_beats != 0U && pkt_start == 0U)
        xil_printf("STAGE3A_LOC=PACKETIZER_FILLING_OR_TLAST_MISSING\r\n");
    else if (pkt_start != 0U && udp_req == 0U)
        xil_printf("STAGE3A_LOC=UDP_START_NOT_ACCEPTED\r\n");
    else if (udp_req != 0U && udp_done == 0U)
        xil_printf("STAGE3A_LOC=UDP_TX_NO_DONE\r\n");
    else if (udp_done != 0U)
        xil_printf("STAGE3A_LOC=FLOW_ACTIVE\r\n");
    else
        xil_printf("STAGE3A_LOC=NO_AXIS_ACTIVITY_OBSERVED\r\n");
    if (state == 0U) xil_printf("STAGE3A_PKT_STATE=FILL\r\n");
    else if (state == 1U) xil_printf("STAGE3A_PKT_STATE=START\r\n");
    else if (state == 2U) xil_printf("STAGE3A_PKT_STATE=SEND\r\n");
    else xil_printf("STAGE3A_PKT_STATE=WAIT_DONE\r\n");
}

static void build_sg_ring(void)
{
    u32 packet;
    u32 bd;
    u32 packets;
    u32 bytes;

    for (bd = 0U, packet = 0U; bd < SG_BD_COUNT; ++bd, packet += packets) {
        packets = TOTAL_PACKETS - packet;
        if (packets > PACKETS_PER_BD) packets = PACKETS_PER_BD;
        bytes = packets * PAYLOAD_BYTES;
        if (bd == SG_BD_COUNT - 1U)
            bytes = DMA_TRANSFER_BYTES - packet * PAYLOAD_BYTES;
        sg_ring[bd][BD_NEXTDESC] = (u32)(UINTPTR)&sg_ring[(bd + 1U) % SG_BD_COUNT][0];
        sg_ring[bd][BD_BUFFER_ADDR] = PATTERN_BASE + packet * PAYLOAD_BYTES;
        sg_ring[bd][BD_CONTROL] = BD_CTRL_SOF | BD_CTRL_EOF | (bytes & BD_CTRL_LENGTH_MASK);
        sg_ring[bd][BD_STATUS] = 0U;
    }
    Xil_DCacheFlushRange((UINTPTR)sg_ring, sizeof(sg_ring));
}

int main(void)
{
    u32 status;
    u32 polls;
    XTime start_ticks;
    XTime end_ticks;

    xil_printf("\r\nSTAGE3A_PATTERN_BEGIN bytes=%u packets=%u\r\n",
               DMA_BYTES, TOTAL_PACKETS);
    fill_pattern();
    Xil_DCacheFlushRange((UINTPTR)PATTERN_BASE, DMA_TRANSFER_BYTES);
    build_sg_ring();
    xil_printf("STAGE3A_PATTERN_READY base=%08x\r\n", PATTERN_BASE);
    xil_printf("STAGE3B_SG_RING descriptors=%u packets_per_bd=%u ring=%08x\r\n",
               SG_BD_COUNT, PACKETS_PER_BD, (u32)(UINTPTR)sg_ring);

    Xil_Out32(DMA_MM2S_DMACR, DMA_CR_RESET);
    usleep(10000U);
    /* eth_rst_n and the RGMII clock are generated after PS reset.  Starting
       before they settle caused the first DMA chunk to absorb several seconds
       of backpressure and split one test frame across RK receive windows. */
    xil_printf("STAGE3A_LINK_SETTLE_WAIT_MS=5000\r\n");
    sleep(5U);
    xil_printf("STAGE3B_DMA_SG_START descriptors=%u\r\n", SG_BD_COUNT);
    dump_flow("BASELINE", 0U, 0U);
    Xil_Out32(DMA_MM2S_DMASR, DMA_CR_IRQ_MASK);
    Xil_Out32(DMA_MM2S_CURDESC, (u32)(UINTPTR)&sg_ring[0][0]);
    Xil_Out32(DMA_MM2S_DMACR, DMA_CR_RUNSTOP | DMA_CR_IRQ_MASK);
    XTime_GetTime(&start_ticks);
    Xil_Out32(DMA_MM2S_TAILDESC, (u32)(UINTPTR)&sg_ring[SG_BD_COUNT - 1U][0]);
    dump_flow("START", 0U, 0U);
    for (polls = 0U; polls < 30000U; ++polls) {
        status = Xil_In32(DMA_MM2S_DMASR);
        if ((status & DMA_SR_ERROR_MASK) != 0U) {
            dump_flow("DMA_ERROR", 0U, polls);
            xil_printf("STAGE3B_DMA_SG_ERROR sr=%08x\r\n", status);
            while (1) { sleep(1U); }
        }
        if ((status & DMA_SR_IDLE) != 0U) break;
        usleep(100U);
    }
    if (polls == 30000U) {
        dump_flow("DMA_TIMEOUT", 0U, polls);
        xil_printf("STAGE3B_DMA_SG_TIMEOUT sr=%08x\r\n", Xil_In32(DMA_MM2S_DMASR));
        while (1) { sleep(1U); }
    }
    xil_printf("STAGE3B_DMA_SG_COMPLETE descriptors=%u\r\n", SG_BD_COUNT);
    /* MM2S can finish after the last FIFO write while the final UDP packet is
       still being serialized.  Do not claim frame completion before the
       packetizer's independently synchronized counters reach their targets. */
    for (polls = 0U; polls < 3000U; ++polls) {
        if ((Xil_In32(ETH_DBG_IN_LAST) == SG_BD_COUNT) &&
            (Xil_In32(ETH_DBG_PKT_START) == TOTAL_PACKETS) &&
            (Xil_In32(ETH_DBG_UDP_DONE) == TOTAL_PACKETS))
            break;
        usleep(1000U);
    }
    XTime_GetTime(&end_ticks);
    dump_flow("FINAL", SG_BD_COUNT, polls);
    if (polls == 3000U)
        xil_printf("STAGE3B_FINAL_DRAIN_TIMEOUT expected_last=%u expected_packets=%u\r\n",
                   SG_BD_COUNT, TOTAL_PACKETS);
    else
        xil_printf("STAGE3B_FINAL_DRAIN_COMPLETE packets=%u elapsed_us=%u\r\n", TOTAL_PACKETS,
                   (u32)(((end_ticks - start_ticks) * 1000000U) / COUNTS_PER_SECOND));
    xil_printf("STAGE3B_WAIT_RK_827_OF_827\r\n");
    while (1) { sleep(1U); }
}
