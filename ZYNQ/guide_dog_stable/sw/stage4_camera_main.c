/* Stage 4: OV5640 -> VDMA S2MM -> one PL-owned SG DMA frame -> UDP. */
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "sleep.h"
#include "sccb_init.h"
#include "ov5640_init.h"
#include "vdma_api.h"
#include "xparameters.h"
#include "xiltimer.h"

#define VDMA_BASE             0x43000000U
#define VDMA_PARKPTR          (VDMA_BASE + 0x28U)
#define VDMA_S2MM_CTRL        (VDMA_BASE + 0x30U)
#define VDMA_S2MM_STAT        (VDMA_BASE + 0x34U)
#define VDMA_S2MM_VSIZE       (VDMA_BASE + 0xA0U)
#define VDMA_S2MM_HSIZE       (VDMA_BASE + 0xA4U)
#define VDMA_S2MM_STRD        (VDMA_BASE + 0xA8U)
#define VDMA_S2MM_START0      (VDMA_BASE + 0xACU)

#define DMA_BASE              0x40400000U
#define DMA_MM2S_DMACR        (DMA_BASE + 0x00U)
#define DMA_MM2S_DMASR        (DMA_BASE + 0x04U)
#define DMA_MM2S_CURDESC      (DMA_BASE + 0x08U)
#define DMA_MM2S_TAILDESC     (DMA_BASE + 0x10U)

#define ETH_BASE              0x40000000U
#define ETH_DBG_IN_LAST       (ETH_BASE + 0x1CU)
#define ETH_DBG_PKT_START     (ETH_BASE + 0x2CU)
#define ETH_DBG_UDP_DONE      (ETH_BASE + 0x34U)
#define ETH_DBG_ETH           (ETH_BASE + 0x3CU)
#define ETH_DBG_HEART         (ETH_BASE + 0x24U)
#define ETH_DBG_PKT_BEATS     (ETH_BASE + 0x28U)
#define ETH_DBG_UDP_REQ       (ETH_BASE + 0x30U)
#define ETH_DBG_STATE         (ETH_BASE + 0x38U)
#define ETH_DBG_DMA_ACCEPTED  (ETH_BASE + 0x18U)
#define ETH_DBG_DMA_TLASTS    (ETH_BASE + 0x1CU)
#define ETH_DBG_DMA_STALLS    (ETH_BASE + 0x20U)
#define ETH_STATUS             (ETH_BASE + 0x00U)
#define ETH_SWEEP_CTRL         (ETH_BASE + 0x04U)
#define ETH_SWEEP_BEATS        (ETH_BASE + 0x08U)
#define ETH_SWEEP_TLASTS       (ETH_BASE + 0x0CU)
#define CAMERA_DBG_BASE       0x43C10000U

#define FRAME_BASE            0x11000000U
#define FRAME_WIDTH           800U
#define FRAME_HEIGHT          480U
#define FRAME_BYTES           (FRAME_WIDTH * FRAME_HEIGHT * 3U)
#define FRAME_COUNT           3U
#define PAYLOAD_BYTES         1394U
#define TOTAL_PACKETS         827U
#define WIRE_BYTES            (PAYLOAD_BYTES * TOTAL_PACKETS)
#define PACKETS_PER_BD        4U
#define FULL_BD_COUNT         (TOTAL_PACKETS / PACKETS_PER_BD)
#define IMAGE_BD_COUNT        (FULL_BD_COUNT + 1U)
#define SG_BD_COUNT           (IMAGE_BD_COUNT + 1U)
#ifdef STAGE5_CYCLIC_DMA
#define SG_RING_BD_COUNT      (SG_BD_COUNT * FRAME_COUNT)
#else
#define SG_RING_BD_COUNT      SG_BD_COUNT
#endif
#define SG_BD_BYTES           64U
#define SG_BD_WORDS           (SG_BD_BYTES / sizeof(u32))
#define BD_NEXTDESC           0U
#define BD_BUFFER_ADDR        2U
#define BD_CONTROL            6U
#define BD_STATUS             7U
#define BD_CTRL_SOF           0x08000000U
#define BD_CTRL_EOF           0x04000000U
#define BD_CTRL_LENGTH_MASK   0x007FFFFFU
#define DMA_CR_RUNSTOP        0x00000001U
#define DMA_CR_RESET          0x00000004U
#define DMA_CR_CYCLIC         0x00000010U
#define DMA_IRQ_CLEAR         0x00007000U
#define DMA_SR_ERROR_MASK     0x00000770U
#define DMA_SR_HALTED          0x00000001U
#define DMA_SR_IDLE           0x00000002U
#define DMA_SR_IOC_IRQ        0x00001000U
#define DIAG_BASE             0x00300000U
#define DDR_SENTINEL          0xA5A5A5A5U
#define SWEEP_BYTES            4096U
#define RUN_AXIS_SWEEP         0U
#define TXC_PHASES             4U
#define DIAG_FRAME_COUNT        8U
#define TXC_PHASE_SHIFT        3U
#define TXC_STATUS_LOCKED      0x10U
#define TXC_STATUS_PHASE_SHIFT 2U
#define PHASE_DIAG_BASE        50U

/* One extra, unreachable BD is the cyclic-mode TDESC sentinel. */
static u32 sg_ring[SG_RING_BD_COUNT + 1U][SG_BD_WORDS] __attribute__((aligned(SG_BD_BYTES)));
static u8 zero_pad[840] __attribute__((aligned(8)));
#ifdef STAGE5_CYCLIC_DMA
static u32 cyclic_base_start, cyclic_base_done, cyclic_base_last;
static XTime cyclic_start_time;
#endif

static void fail(const char *where, u32 a, u32 b);

static void sweep_record(u32 slot, u32 status, u32 beats, u32 tlasts, u32 aux)
{
    volatile u32 * const d = (volatile u32 *)DIAG_BASE;
    u32 const base = 38U + slot * 4U;
    d[base + 0U] = status;
    d[base + 1U] = beats;
    d[base + 2U] = tlasts;
    d[base + 3U] = aux;
    Xil_DCacheFlushRange(DIAG_BASE + base * sizeof(u32), 4U * sizeof(u32));
}

/* A completed SG BD raises IOC but is not required to assert Idle.  Each
   sweep leg must return the DMA to a known Halted state before its descriptor
   is reused, otherwise the next consumer's result is not attributable. */
static int sweep_dma_reset(void)
{
    u32 polls;

    Xil_Out32(DMA_MM2S_DMACR, 0U);
    for (polls = 0U; polls < 10000U; ++polls) {
        if ((Xil_In32(DMA_MM2S_DMASR) & DMA_SR_HALTED) != 0U) break;
        usleep(10U);
    }
    if (polls == 10000U) return -1;

    Xil_Out32(DMA_MM2S_DMACR, DMA_CR_RESET);
    for (polls = 0U; polls < 10000U; ++polls) {
        if ((Xil_In32(DMA_MM2S_DMACR) & DMA_CR_RESET) == 0U) break;
        usleep(10U);
    }
    if (polls == 10000U) return -2;

    Xil_Out32(DMA_MM2S_DMASR, DMA_IRQ_CLEAR);
    return 0;
}

static u32 eth_dma_tlasts(void)
{
    return Xil_In32(ETH_DBG_IN_LAST) >> 16;
}

static void diag_mark(u32 node, u32 frame, u32 source, u32 aux)
{
    volatile u32 * const d = (volatile u32 *)DIAG_BASE;
    d[0] = 0x53544735U; /* STG5 */
    d[1] = node;
    d[2] = frame;
    d[3] = source;
    d[4] = aux;
    Xil_DCacheFlushRange(DIAG_BASE, 5U * sizeof(u32));
}

/* Retain the latest four complete frames.  Each slot: absolute frame number,
   fixed-TXC status, DMA TLAST delta, packet-start delta, UDP-done delta. */
static void diag_frame_record(u32 frame_no, u32 status, u32 tlast_delta,
                              u32 start_delta, u32 done_delta)
{
    volatile u32 * const d = (volatile u32 *)DIAG_BASE;
    u32 const base = PHASE_DIAG_BASE + (frame_no % TXC_PHASES) * 5U;
    d[base + 0U] = frame_no;
    d[base + 1U] = status;
    d[base + 2U] = tlast_delta;
    d[base + 3U] = start_delta;
    d[base + 4U] = done_delta;
    Xil_DCacheFlushRange(DIAG_BASE + base * sizeof(u32), 5U * sizeof(u32));
}

/* Control bit 4 is the MMCM lock indication, and bits 3:2 report the phase
   that the idle-only TXC selector has actually accepted. */
static u32 select_txc_phase(u32 phase)
{
    u32 polls, status = 0U;
    Xil_Out32(ETH_SWEEP_CTRL, phase << TXC_PHASE_SHIFT);
    for (polls = 0U; polls < 10000U; ++polls) {
        status = Xil_In32(ETH_STATUS);
        if ((status & TXC_STATUS_LOCKED) != 0U &&
            ((status >> TXC_STATUS_PHASE_SHIFT) & 3U) == phase) {
            usleep(10000U); /* settle with GMII idle before DMA starts */
            return status;
        }
        usleep(10U);
    }
    diag_mark(93U, phase, status, polls);
    fail("TXC_PHASE_NOT_ACTIVE", phase, status);
    return status;
}

static void diag_sample(u32 node, u32 frame, u32 source, u32 aux)
{
    volatile u32 * const d = (volatile u32 *)DIAG_BASE;
    diag_mark(node, frame, source, aux);
    d[5] = Xil_In32(VDMA_PARKPTR);
    d[6] = Xil_In32(VDMA_S2MM_STAT);
    d[7] = Xil_In32(DMA_MM2S_DMASR);
    d[8] = eth_dma_tlasts();
    d[9] = Xil_In32(ETH_DBG_PKT_START);
    d[10] = Xil_In32(ETH_DBG_UDP_DONE);
    d[25] = Xil_In32(ETH_DBG_ETH);
    d[26] = Xil_In32(ETH_DBG_HEART);
    d[27] = Xil_In32(ETH_DBG_PKT_BEATS);
    d[28] = Xil_In32(ETH_DBG_UDP_REQ);
    d[29] = Xil_In32(ETH_DBG_STATE);
    d[30] = Xil_In32(DMA_MM2S_DMACR);
    d[31] = Xil_In32(DMA_MM2S_DMASR);
    d[32] = Xil_In32(DMA_MM2S_CURDESC);
    d[33] = Xil_In32(DMA_MM2S_TAILDESC);
    /* FCLK-side monitor before the async FIFO; word 27 is its output sink. */
    d[34] = Xil_In32(ETH_DBG_DMA_ACCEPTED);
    d[35] = Xil_In32(ETH_DBG_DMA_TLASTS);
    d[36] = Xil_In32(ETH_DBG_DMA_STALLS);
    d[37] = Xil_In32(ETH_DBG_IN_LAST) & 0xffffU;
    Xil_DCacheFlushRange(DIAG_BASE, 38U * sizeof(u32));
}

static void diag_camera_observation(u32 node, u32 frame, u32 source, u32 aux)
{
    volatile u32 * const d = (volatile u32 *)DIAG_BASE;
    diag_mark(node, frame, source, aux);
    d[11] = Xil_In32(CAMERA_DBG_BASE + 0x00U);
    d[12] = Xil_In32(CAMERA_DBG_BASE + 0x04U);
    d[13] = Xil_In32(CAMERA_DBG_BASE + 0x08U);
    d[14] = Xil_In32(CAMERA_DBG_BASE + 0x0CU);
    Xil_DCacheInvalidateRange(FRAME_BASE, FRAME_COUNT * FRAME_BYTES);
    d[15] = Xil_In32(FRAME_BASE + 0U);
    d[16] = Xil_In32(FRAME_BASE + FRAME_BYTES);
    d[17] = Xil_In32(FRAME_BASE + 2U * FRAME_BYTES);
    /* Keep words 0..17 stable; append the S2MM programming evidence. */
    d[18] = Xil_In32(VDMA_S2MM_CTRL);
    d[19] = Xil_In32(VDMA_S2MM_VSIZE);
    d[20] = Xil_In32(VDMA_S2MM_HSIZE);
    d[21] = Xil_In32(VDMA_S2MM_STRD);
    d[22] = Xil_In32(VDMA_S2MM_START0 + 0U);
    d[23] = Xil_In32(VDMA_S2MM_START0 + 4U);
    d[24] = Xil_In32(VDMA_S2MM_START0 + 8U);
    d[25] = Xil_In32(ETH_DBG_ETH);
    d[26] = Xil_In32(ETH_DBG_HEART);
    d[27] = Xil_In32(ETH_DBG_PKT_BEATS);
    d[28] = Xil_In32(ETH_DBG_UDP_REQ);
    d[29] = Xil_In32(ETH_DBG_STATE);
    Xil_DCacheFlushRange(DIAG_BASE + 11U * sizeof(u32), 19U * sizeof(u32));
}

static void fail(const char *where, u32 a, u32 b)
{
    xil_printf("STAGE4_CAMERA_FAIL where=%s a=%08x b=%08x\r\n", where, a, b);
    while (1) sleep(1U);
}

static XAxiVdma vdma_instance;

static u32 start_capture_and_select_safe_slot(void)
{
    u32 park0, park1, slot, sample;
    u32 polls, advanced = 0U;

    xil_printf("STAGE4_CAMERA_INIT_BEGIN\r\n");
    diag_mark(10U, 0U, 0U, 0U);
    diag_mark(11U, 0U, 0U, 0U);
    SCCB_Init();
    if (OV5640_Init() != 0U) fail("OV5640_INIT", 0U, 0U);
    diag_mark(12U, 0U, 0U, 0U);

    /* Seed each frame-store head so a later changed value proves PL wrote DDR. */
    Xil_Out32(FRAME_BASE + 0U, DDR_SENTINEL);
    Xil_Out32(FRAME_BASE + FRAME_BYTES, DDR_SENTINEL);
    Xil_Out32(FRAME_BASE + 2U * FRAME_BYTES, DDR_SENTINEL);
    Xil_DCacheInvalidateRange(FRAME_BASE, FRAME_COUNT * FRAME_BYTES);

    /* Use the validated driver setup: it enables circular mode, programs all
       three frame-store addresses, and starts S2MM in the driver's order. */
    /* The captured video stream is RGB888: 800 pixels x 3 bytes = 2400 bytes
       per line.  The BSP's helper derives the byte count from its 24-bit
       stream configuration, so it must receive pixels, not DDR bus words. */
    diag_mark(20U, 0U, 0U, 0U);
    if (run_vdma_frame_buffer(&vdma_instance, 0, FRAME_WIDTH, FRAME_HEIGHT,
                              FRAME_BASE, 0, 0, ONLY_WRITE) != XST_SUCCESS)
        fail("VDMA_INIT", Xil_In32(VDMA_S2MM_STAT), Xil_In32(VDMA_PARKPTR));
    /* The helper enables VDMA error IRQs, but this polling application has no
       GIC handler. Disable all channel IRQs before the first frame completes. */
    XAxiVdma_IntrDisable(&vdma_instance, XAXIVDMA_IXR_ALL_MASK, XAXIVDMA_WRITE);
    XAxiVdma_IntrDisable(&vdma_instance, XAXIVDMA_IXR_ALL_MASK, XAXIVDMA_READ);
    diag_mark(23U, 0U, 0U, 0U);
    xil_printf("STAGE4_VDMA_READY ctrl=%08x stat=%08x park=%08x hsize=%u stride=%u\r\n",
               Xil_In32(VDMA_S2MM_CTRL), Xil_In32(VDMA_S2MM_STAT),
               Xil_In32(VDMA_PARKPTR), FRAME_WIDTH * 3U, FRAME_WIDTH * 3U);
    diag_sample(21U, 0U, 0U, 0U);

    /* Full FPGA configuration releases the Ethernet clock/reset later than
       PS startup. Let the PHY and packetizer settle before selecting/sending
       a frame, matching the proven Stage3B startup sequence. */
    xil_printf("STAGE4_LINK_SETTLE_WAIT_MS=5000\r\n");
    sleep(5U);
    diag_camera_observation(27U, 0U, 0U, 5000U);
    diag_camera_observation(28U, 0U, 0U, 5000U);

    /* Sample faster than a video frame so a rotating writer cannot alias to
       the same PARKPTR value after a whole three-frame cycle. */
    usleep(20000U);
    diag_mark(30U, 0U, 0U, 0U);
    park0 = Xil_In32(VDMA_PARKPTR);
    park1 = park0;
    for (polls = 0U; polls < 50U; ++polls) {
        usleep(10000U);
        diag_mark(31U, 0U, 0U, polls);
        sample = Xil_In32(VDMA_PARKPTR);
        diag_mark(32U, 0U, sample, polls);
        if (sample != park0) {
            park1 = sample;
            advanced = 1U;
            break;
        }
    }
    slot = (park1 >> 24) & 0x1fU;
    xil_printf("STAGE4_CAPTURE park0=%08x park1=%08x advanced=%u stat=%08x write_slot=%u\r\n",
               park0, park1, advanced, Xil_In32(VDMA_S2MM_STAT), slot);
    if (slot >= FRAME_COUNT) fail("S2MM_SLOT", park1, slot);

    /* Choose the oldest completed slot: with writer=w, w+1 is next to be
       overwritten and w+2 (equivalent to w-1) is the safe snapshot. */
    slot = (slot + FRAME_COUNT - 1U) % FRAME_COUNT;
    xil_printf("STAGE4_CAPTURE_SAFE_SLOT=%u base=%08x\r\n",
               slot, FRAME_BASE + slot * FRAME_BYTES);
    diag_sample(33U, 0U, FRAME_BASE + slot * FRAME_BYTES, polls);
    return FRAME_BASE + slot * FRAME_BYTES;
}

static u32 wait_next_safe_slot(u32 previous_base)
{
    u32 previous_slot = (previous_base - FRAME_BASE) / FRAME_BYTES;
    u32 sample, writer, safe;
    u32 polls;

    for (polls = 0U; polls < 2000U; ++polls) {
        diag_mark(70U, previous_slot, previous_base, polls);
        sample = Xil_In32(VDMA_PARKPTR);
        diag_mark(71U, previous_slot, sample, polls);
        writer = (sample >> 24) & 0x1fU;
        if (writer < FRAME_COUNT && writer == previous_slot) {
            /* Do not accept the first different writer slot.  Waiting until
               the writer reaches the slot just read gives the next oldest
               slot a full two-frame overwrite horizon. */
            safe = (writer + FRAME_COUNT - 1U) % FRAME_COUNT;
            xil_printf("STAGE4_NEXT_SLOT park=%08x writer=%u safe=%u\r\n",
                       sample, writer, safe);
            return FRAME_BASE + safe * FRAME_BYTES;
        }
        usleep(1000U);
    }
    diag_mark(79U, previous_slot, previous_base, polls);
    fail("S2MM_NO_NEXT_SLOT", Xil_In32(VDMA_PARKPTR), previous_base);
    return 0U;
}

static void build_sg_ring(u32 frame_base)
{
    u32 slot_count = SG_RING_BD_COUNT / SG_BD_COUNT;
    u32 first_slot = (frame_base - FRAME_BASE) / FRAME_BYTES;
    u32 slot_no, bd, packet, bytes, source;

    for (slot_no = 0U; slot_no < slot_count; ++slot_no) {
        /* In cyclic mode visit all three VDMA frame stores in write order.
           The previous ring permanently replayed the one startup slot. */
        source = FRAME_BASE + ((first_slot + slot_no) % FRAME_COUNT) * FRAME_BYTES;
        bd = slot_no * SG_BD_COUNT;
        for (packet = 0U; packet < FULL_BD_COUNT * PACKETS_PER_BD;
             packet += PACKETS_PER_BD, ++bd) {
            sg_ring[bd][BD_NEXTDESC] = (u32)(UINTPTR)&sg_ring[bd + 1U][0];
            sg_ring[bd][BD_BUFFER_ADDR] = source + packet * PAYLOAD_BYTES;
            sg_ring[bd][BD_CONTROL] = BD_CTRL_SOF | BD_CTRL_EOF |
                                      (PACKETS_PER_BD * PAYLOAD_BYTES);
            sg_ring[bd][BD_STATUS] = 0U;
        }

        /* 824 full packets are followed by the final image bytes. */
        bytes = FRAME_BYTES - packet * PAYLOAD_BYTES;
        sg_ring[bd][BD_NEXTDESC] = (u32)(UINTPTR)&sg_ring[bd + 1U][0];
        sg_ring[bd][BD_BUFFER_ADDR] = source + packet * PAYLOAD_BYTES;
        sg_ring[bd][BD_CONTROL] = BD_CTRL_SOF | BD_CTRL_EOF | bytes;
        sg_ring[bd][BD_STATUS] = 0U;
        ++bd;

        /* Exactly 838 pad bytes per wire frame; two extra bytes would remain
           in the packetizer and shift the next image's packet boundaries. */
        sg_ring[bd][BD_NEXTDESC] =
            (u32)(UINTPTR)&sg_ring[(bd + 1U) % SG_RING_BD_COUNT][0];
        sg_ring[bd][BD_BUFFER_ADDR] = (u32)(UINTPTR)zero_pad;
        sg_ring[bd][BD_CONTROL] = BD_CTRL_SOF | BD_CTRL_EOF |
                                  (WIRE_BYTES - FRAME_BYTES);
        sg_ring[bd][BD_STATUS] = 0U;
    }
    for (u32 word = 0U; word < SG_BD_WORDS; ++word)
        sg_ring[SG_RING_BD_COUNT][word] = 0U;
    Xil_DCacheFlushRange((UINTPTR)zero_pad, sizeof(zero_pad));
    Xil_DCacheFlushRange((UINTPTR)sg_ring, sizeof(sg_ring));
}

#ifdef STAGE5_CYCLIC_DMA
/* PS starts the SG engine exactly once.  In cyclic mode the last real BD
   points back to BD0, while TDESC must name a separate, unreachable dummy BD
   (the same arrangement used by Xilinx's SG-cyclic driver example). */
static void start_cyclic_stream(u32 frame_base)
{
    u32 status;
    build_sg_ring(frame_base);
    diag_mark(100U, 0U, frame_base, SG_RING_BD_COUNT);
    status = (u32)sweep_dma_reset();
    if ((s32)status < 0) fail("CYCLIC_DMA_RESET", status, frame_base);

    cyclic_base_start = Xil_In32(ETH_DBG_PKT_START);
    cyclic_base_done = Xil_In32(ETH_DBG_UDP_DONE);
    cyclic_base_last = eth_dma_tlasts();
    XTime_GetTime(&cyclic_start_time);
    Xil_Out32(DMA_MM2S_DMACR, DMA_CR_CYCLIC);
    Xil_Out32(DMA_MM2S_CURDESC, (u32)(UINTPTR)&sg_ring[0][0]);
    Xil_Out32(DMA_MM2S_DMACR, DMA_CR_RUNSTOP | DMA_CR_CYCLIC);
    Xil_Out32(DMA_MM2S_TAILDESC, (u32)(UINTPTR)&sg_ring[SG_RING_BD_COUNT][0]);
    status = Xil_In32(DMA_MM2S_DMACR);
    xil_printf("STAGE5_CYCLIC_STARTED source=%08x bds=%u cr=%08x tail_sentinel=%08x\r\n",
               frame_base, SG_RING_BD_COUNT, status,
               (u32)(UINTPTR)&sg_ring[SG_RING_BD_COUNT][0]);
    if ((status & (DMA_CR_RUNSTOP | DMA_CR_CYCLIC)) !=
        (DMA_CR_RUNSTOP | DMA_CR_CYCLIC))
        fail("CYCLIC_MODE_NOT_SET", status, frame_base);
    diag_sample(101U, 0U, frame_base, status);
}

/* Diagnostics observe the autonomous path; they never reprogram the DMA or
   choose a source slot after the initial configuration. */
static void monitor_cyclic_stream(u32 frame_base)
{
    const u32 base_start = cyclic_base_start;
    const u32 base_done = cyclic_base_done;
    const u32 base_last = cyclic_base_last;
    u32 next_report = 16U;
    u32 previous_done = base_done;
    u32 previous_report_lasts = base_last;
    XTime last_progress = cyclic_start_time, now;

    for (;;) {
        u32 status = Xil_In32(DMA_MM2S_DMASR);
        u32 done = Xil_In32(ETH_DBG_UDP_DONE);
        u32 starts = Xil_In32(ETH_DBG_PKT_START);
        u32 lasts = eth_dma_tlasts();
        XTime_GetTime(&now);
        if ((status & (DMA_SR_ERROR_MASK | DMA_SR_HALTED)) != 0U) {
            diag_sample(109U, done - base_done, frame_base, status);
            fail("CYCLIC_DMA_STOPPED", status, done - base_done);
        }
        if (done != previous_done) {
            previous_done = done;
            last_progress = now;
        }
        if (now - last_progress > (XTime)COUNTS_PER_SECOND * 3U) {
            diag_sample(108U, done - base_done, frame_base, status);
            fail("CYCLIC_NO_PROGRESS", done - base_done, starts - base_start);
        }
        if (done - base_done >= next_report * TOTAL_PACKETS) {
            u32 fps_x100;
            u32 report_frames = ((done - base_done) / TOTAL_PACKETS / 16U) * 16U;
            u64 elapsed = (u64)(now - cyclic_start_time);
            /* DMA TLAST is upstream of UDP_DONE. The sampled counters are
               not atomic: DMA may be several BDs ahead at one report and
               less far ahead at the next. A strict 16*208 delta therefore
               reports a false failure even while UDP_DONE advances. Require
               forward BD progress and no impossible DONE > START instead. */
            if (starts - base_start < done - base_done ||
                ((lasts - previous_report_lasts) & 0xffffU) < SG_RING_BD_COUNT) {
                diag_sample(107U, report_frames, frame_base, status);
                fail("CYCLIC_COUNT_MISMATCH", starts - base_start,
                     (lasts - previous_report_lasts) & 0xffffU);
            }
            fps_x100 = elapsed == 0U ? 0U :
                       (u32)(((u64)report_frames * 100U * COUNTS_PER_SECOND) / elapsed);
            xil_printf("STAGE5_CYCLIC_PROGRESS frames=%u pkt_start=%u udp_done=%u tlast=%u fps=%u.%02u sr=%08x\r\n",
                       report_frames, starts - base_start, done - base_done,
                       (lasts - base_last) & 0xffffU, fps_x100 / 100U,
                       fps_x100 % 100U, status);
            diag_sample(102U, report_frames, frame_base, fps_x100);
            previous_report_lasts = lasts;
            next_report = report_frames + 16U;
        }
        usleep(10000U);
    }
}
#endif

static void send_one_frame(u32 frame_base, u32 frame_no, u32 phase_status)
{
    u32 status, polls, now_last, now_start, now_done;
    u32 base_last = eth_dma_tlasts();
    u32 base_start = Xil_In32(ETH_DBG_PKT_START);
    u32 base_done = Xil_In32(ETH_DBG_UDP_DONE);

    build_sg_ring(frame_base);
    diag_mark(40U, frame_no, frame_base, 0U);

    diag_mark(41U, frame_no, frame_base, 0U);
    status = (u32)sweep_dma_reset();
    if ((s32)status < 0)
        fail("MM2S_RESET", status, frame_no);
    diag_mark(42U, frame_no, frame_base, 0U);
    Xil_Out32(DMA_MM2S_CURDESC, (u32)(UINTPTR)&sg_ring[0][0]);
    /* Polling-only operation: do not enable IOC/error IRQs without a GIC handler. */
    Xil_Out32(DMA_MM2S_DMACR, DMA_CR_RUNSTOP);
    Xil_Out32(DMA_MM2S_TAILDESC, (u32)(UINTPTR)&sg_ring[SG_BD_COUNT - 1U][0]);
    diag_sample(43U, frame_no, frame_base, 0U);
    if (frame_no == 0U)
        xil_printf("STAGE4_SG_STARTED descriptors=%u source=%08x\r\n", SG_BD_COUNT, frame_base);

    for (polls = 0U; polls < 30000U; ++polls) {
        diag_mark(44U, frame_no, frame_base, polls);
        status = Xil_In32(DMA_MM2S_DMASR);
        if ((status & (DMA_SR_ERROR_MASK | DMA_SR_HALTED)) != 0U) {
            diag_sample(44U, frame_no, frame_base, status);
            fail("MM2S_HALTED_OR_ERROR", status, polls);
        }
        /* In SG mode, IOC marks this BD ring complete even while downstream
           FIFO backpressure delays Idle.  Idle here made a completed frame
           look like a timeout and prevented the real drain check below. */
        if ((status & DMA_SR_IOC_IRQ) != 0U) break;
        usleep(100U);
    }
    if (polls == 30000U) fail("MM2S_NO_IOC", Xil_In32(DMA_MM2S_DMASR), polls);
    diag_sample(45U, frame_no, frame_base, polls);

    for (polls = 0U; polls < 3000U; ++polls) {
        if (eth_dma_tlasts() >= base_last + SG_BD_COUNT &&
            Xil_In32(ETH_DBG_PKT_START) >= base_start + TOTAL_PACKETS &&
            Xil_In32(ETH_DBG_UDP_DONE) >= base_done + TOTAL_PACKETS)
            break;
        usleep(1000U);
    }
    /* The three counters are independent registers; sample once after the
       loop so a final increment between reads cannot create a false timeout. */
    now_last = eth_dma_tlasts();
    now_start = Xil_In32(ETH_DBG_PKT_START);
    now_done = Xil_In32(ETH_DBG_UDP_DONE);
    xil_printf("STAGE4_FRAME frame=%u source=%08x s2mm_stat=%08x in_last=%u pkt_start=%u udp_done=%u polls=%u\r\n",
               frame_no, frame_base, Xil_In32(VDMA_S2MM_STAT), now_last,
               now_start, now_done, polls);
    diag_sample(46U, frame_no, frame_base, polls);
    if (now_last < base_last + SG_BD_COUNT ||
        now_start < base_start + TOTAL_PACKETS ||
        now_done < base_done + TOTAL_PACKETS)
        fail("UDP_DRAIN", now_done, polls);
    diag_frame_record(frame_no, phase_status, now_last - base_last,
                      now_start - base_start, now_done - base_done);
}

/* One program run enumerates FIFO consumers before any production frame.
   slot 0: always-ready drain; slot 1: 1-in-9 ready drain; slot 2: packetizer. */
static void run_axis_sweep(u32 source)
{
    u32 mode, slot, polls, drain_polls, status;
    u32 base_beats, base_tlasts, base_pkt, base_steps;

    xil_printf("STAGE5_AXIS_SWEEP_BEGIN bytes=%u\r\n", SWEEP_BYTES);
    for (mode = 1U; mode <= 3U; ++mode) {
        slot = mode - 1U;
        Xil_Out32(ETH_SWEEP_CTRL, (mode == 3U) ? 0U : (mode << 1U));
        usleep(1000U); /* synchronizer into the 125 MHz consumer domain */
        base_beats = Xil_In32(ETH_SWEEP_BEATS);
        base_tlasts = Xil_In32(ETH_SWEEP_TLASTS);
        base_pkt = Xil_In32(ETH_DBG_PKT_BEATS);
        base_steps = Xil_In32(ETH_DBG_STATE) & 0x3fffffffU;

        sg_ring[0][BD_NEXTDESC] = (u32)(UINTPTR)&sg_ring[0][0];
        sg_ring[0][BD_BUFFER_ADDR] = source;
        sg_ring[0][BD_CONTROL] = BD_CTRL_SOF | BD_CTRL_EOF | SWEEP_BYTES;
        sg_ring[0][BD_STATUS] = 0U;
        Xil_DCacheFlushRange((UINTPTR)sg_ring, SG_BD_BYTES);

        status = (u32)sweep_dma_reset();
        if ((s32)status < 0) {
            sweep_record(slot, 0xDEAD0000U | mode, 0U, 0U, 0U);
            diag_mark(91U, mode, source, status);
            while (1) sleep(1U);
        }
        Xil_Out32(DMA_MM2S_CURDESC, (u32)(UINTPTR)&sg_ring[0][0]);
        Xil_Out32(DMA_MM2S_DMACR, DMA_CR_RUNSTOP);
        Xil_Out32(DMA_MM2S_TAILDESC, (u32)(UINTPTR)&sg_ring[0][0]);
        for (polls = 0U; polls < 30000U; ++polls) {
            status = Xil_In32(DMA_MM2S_DMASR);
            if ((status & (DMA_SR_ERROR_MASK | DMA_SR_HALTED | DMA_SR_IOC_IRQ)) != 0U)
                break;
            usleep(100U);
        }
        status = Xil_In32(DMA_MM2S_DMASR);
        for (drain_polls = 0U; drain_polls < 30000U; ++drain_polls) {
            if (mode < 3U) {
                if (Xil_In32(ETH_SWEEP_BEATS) - base_beats >= SWEEP_BYTES / 8U &&
                    Xil_In32(ETH_SWEEP_TLASTS) - base_tlasts >= 1U)
                    break;
            } else if (Xil_In32(ETH_DBG_PKT_BEATS) - base_pkt >= SWEEP_BYTES / 8U &&
                       (Xil_In32(ETH_DBG_STATE) & 0x3fffffffU) - base_steps >= SWEEP_BYTES) {
                break;
            }
            usleep(100U);
        }
        if (mode < 3U)
            sweep_record(slot, status, Xil_In32(ETH_SWEEP_BEATS) - base_beats,
                         Xil_In32(ETH_SWEEP_TLASTS) - base_tlasts, polls + drain_polls);
        else
            sweep_record(slot, status, Xil_In32(ETH_DBG_PKT_BEATS) - base_pkt,
                         (Xil_In32(ETH_DBG_STATE) & 0x3fffffffU) - base_steps,
                         polls + drain_polls);
        xil_printf("STAGE5_AXIS_SWEEP mode=%u sr=%08x dma_polls=%u drain_polls=%u\r\n",
                   mode, status, polls, drain_polls);
    }
    diag_mark(90U, 0U, source, SWEEP_BYTES);
    xil_printf("STAGE5_AXIS_SWEEP_COMPLETE\r\n");
}

int main(void)
{
    u32 frame_base;
    u32 txc_status;
    volatile u32 * const diag = (volatile u32 *)DIAG_BASE;

    /* Make every run self-identifying; DDR contents survive processor reset. */
    for (u32 i = 0U; i < PHASE_DIAG_BASE + TXC_PHASES * 5U; ++i)
        diag[i] = 0U;
    Xil_DCacheFlushRange(DIAG_BASE, (PHASE_DIAG_BASE + TXC_PHASES * 5U) * sizeof(u32));
    diag_mark(1U, 0U, 0U, 0U);

    xil_printf("\r\nSTAGE4_CAMERA_CONTINUOUS_BEGIN frame_bytes=%u wire_bytes=%u packets=%u\r\n",
               FRAME_BYTES, WIRE_BYTES, TOTAL_PACKETS);
    frame_base = start_capture_and_select_safe_slot();
    xil_printf("STAGE4_SG_READY descriptors=%u image_descriptors=%u source=%08x\r\n",
               SG_BD_COUNT, IMAGE_BD_COUNT, frame_base);
    /* The FIFO consumer sweep has already been validated.  Production
       transport tests must contain only camera packets, with no sweep BDs
       or partially buffered test payload preceding packet zero. */
    if (RUN_AXIS_SWEEP) run_axis_sweep(frame_base);
#ifdef STAGE5_CYCLIC_DMA
#ifdef STAGE5_SAFE_CYCLIC_DMA
    /* Safe cyclic mode keeps the high-level continuous loop but performs a
       complete ownership handoff before every frame.  The DMA is restarted
       for one frame, so it can never follow a stale three-slot ring. */
    txc_status = select_txc_phase(0U);
    xil_printf("STAGE5_SAFE_CYCLIC_READY frame_base=%08x\r\n", frame_base);
    for (u32 frame_no = 0U;; ++frame_no) {
        if (frame_no != 0U)
            frame_base = wait_next_safe_slot(frame_base);
        send_one_frame(frame_base, frame_no, txc_status);
    }
#else
    select_txc_phase(0U);
    start_cyclic_stream(frame_base);
    monitor_cyclic_stream(frame_base);
#endif
#else
    /* This bitstream wires TXC directly to the loop-proven GMII clock.
       It cannot accept phase 1..3; the previous ELF stopped after frame 0. */
    txc_status = select_txc_phase(0U);
    xil_printf("STAGE5_DIRECT_TXC status=%08x frames=%u\r\n",
               txc_status, DIAG_FRAME_COUNT);
    for (u32 frame_no = 0U; frame_no < DIAG_FRAME_COUNT; ++frame_no) {
        send_one_frame(frame_base, frame_no, txc_status);
        /* PARKPTR remains zero on this capture-only BD, so it cannot serve as
           evidence of a rotating writer.  Reuse the observed real-camera DDR
           slot for this bounded transport test; the 100 ms gap keeps each
           frame attributable in the RK pcap. */
        if (frame_no + 1U < DIAG_FRAME_COUNT)
            usleep(100000U);
    }
    diag_mark(94U, DIAG_FRAME_COUNT - 1U, frame_base,
              TOTAL_PACKETS * DIAG_FRAME_COUNT);
    while (1) sleep(1U);
#endif
}
