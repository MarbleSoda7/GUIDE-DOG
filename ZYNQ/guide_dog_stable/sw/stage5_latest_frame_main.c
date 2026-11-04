/* One-time PS setup. Capture, slot ownership, MM2S pacing and UDP run in PL.
 * This firmware is paired only with latest_frame_project; it never starts
 * the historical AXI DMA cyclic descriptor ring. */
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xparameters.h"
#include "xaxivdma.h"
#include "xstatus.h"
#include "string.h"
#include "sleep.h"
#include "sccb_init.h"
#include "ov5640_init.h"
#include "vdma_api.h"

#define VDMA 0x43000000U
#define ETH  0x40000000U
#define FRAME_BASE  0x11000000U
#define FRAME_WIDTH 800U
#define FRAME_BYTES 1152000U
#define LINE_BYTES  2400U
#define LINES       480U
#define CAMERA_DBG_BASE 0x43C10000U
#define CR_RUN_CIRC_GENLOCK_INTERNAL 0x0000008BU
#define CR_RUN_CIRC_NO_SYNC          0x00000003U
#define SR_ERRORS 0x00000FF0U
#define DIAG_BASE 0x1F000000U
#define DDR_SENTINEL 0xA5A5A5A5U
#define CAM_DIAG_BASE 0x40000000U
#define CAM_DIAG_IN_PIXELS (CAM_DIAG_BASE + 0x08U)
#define CAM_DIAG_IN_SOF    (CAM_DIAG_BASE + 0x0CU)
#define CAM_DIAG_IN_EOL    (CAM_DIAG_BASE + 0x10U)
#define CAM_DIAG_OUT_BEATS (CAM_DIAG_BASE + 0x14U)
#define CAM_DIAG_OUT_TLAST (CAM_DIAG_BASE + 0x18U)
#define CAM_DIAG_FAULTS    (CAM_DIAG_BASE + 0x1CU)
#define CAM_DIAG_OWNER_STATUS (CAM_DIAG_BASE + 0x18U)
#define BUILD_ID "20261001T062420Z_owner_camera_baseline_v1"

static void print_s2mm_status_detail(u32 sr)
{
    xil_printf("DIAG_S2MM_STATUS sr=%08x halted=%u idle=%u internal=%u slave=%u decode=%u fsz_less=%u lsz_less=%u fsz_more=%u irq_frame=%u irq_err=%u\r\n",
               sr, (sr >> 0) & 1U, (sr >> 1) & 1U,
               (sr >> 4) & 1U, (sr >> 5) & 1U, (sr >> 6) & 1U,
               (sr >> 7) & 1U, (sr >> 8) & 1U, (sr >> 11) & 1U,
               (sr >> 12) & 1U, (sr >> 14) & 1U);
}

static void print_camera_snapshot(const char *tag)
{
    xil_printf("DIAG_CAMERA_%s href=%08x de=%08x ce=%08x lines=%08x\r\n",
               tag, Xil_In32(CAMERA_DBG_BASE + 0x00U),
               Xil_In32(CAMERA_DBG_BASE + 0x04U),
               Xil_In32(CAMERA_DBG_BASE + 0x08U),
               Xil_In32(CAMERA_DBG_BASE + 0x0CU));
}

static void print_vdma_snapshot(void)
{
    u32 slot;
    xil_printf("DIAG_BUILD id=%s\r\n", BUILD_ID);
    xil_printf("DIAG_CAMERA id=%04x\r\n",
               ((u32)sccb_read_reg16(0x300A) << 8) | sccb_read_reg16(0x300B));
    print_camera_snapshot("LATCHED");
    xil_printf("DIAG_OWNER write_count=%u commit_count=%u fsync_count=%u done_count=%u status=%08x\r\n",
               Xil_In32(CAM_DIAG_IN_PIXELS), Xil_In32(CAM_DIAG_IN_SOF),
               Xil_In32(CAM_DIAG_IN_EOL), Xil_In32(CAM_DIAG_OUT_BEATS),
               Xil_In32(CAM_DIAG_OUT_TLAST));
    {
        u32 owner_status = Xil_In32(CAM_DIAG_OWNER_STATUS);
        xil_printf("DIAG_OWNER_STATUS bits=%08x latest_slot=%u requested_gen=%u\r\n",
                   owner_status, (owner_status >> 4) & 3U,
                   (owner_status >> 16) & 255U);
    }
    xil_printf("DIAG_S2MM cr=%08x sr=%08x park=%08x vsize=%08x hsize=%08x stride=%08x\r\n",
               Xil_In32(VDMA + 0x30U), Xil_In32(VDMA + 0x34U),
               Xil_In32(VDMA + 0x28U), Xil_In32(VDMA + 0xA0U),
               Xil_In32(VDMA + 0xA4U), Xil_In32(VDMA + 0xA8U));
    print_s2mm_status_detail(Xil_In32(VDMA + 0x34U));
    for (slot = 0U; slot < 3U; ++slot) {
        u32 base = FRAME_BASE + slot * FRAME_BYTES;
        Xil_DCacheInvalidateRange(base, 32U);
        Xil_DCacheInvalidateRange(base + FRAME_BYTES - 32U, 32U);
        xil_printf("DIAG_DDR slot=%u fb=%08x head=%08x tail=%08x\r\n",
                   slot, Xil_In32(VDMA + 0xACU + slot * 4U),
                   Xil_In32(base), Xil_In32(base + FRAME_BYTES - 4U));
    }
    xil_printf("DIAG_MM2S cr=%08x sr=%08x park=%08x vsize=%08x hsize=%08x stride=%08x\r\n",
               Xil_In32(VDMA), Xil_In32(VDMA + 0x04U),
               Xil_In32(VDMA + 0x28U), Xil_In32(VDMA + 0x50U),
               Xil_In32(VDMA + 0x54U), Xil_In32(VDMA + 0x58U));
    xil_printf("DIAG_MM2S_FB0=%08x ETH_dma_stall=%u pkt_beats=%u pkt_start=%u\r\n",
               Xil_In32(VDMA + 0x5CU), Xil_In32(0x40000020U),
               Xil_In32(0x40000028U), Xil_In32(0x4000002CU));
    xil_printf("DIAG_NODE_ETH_PACKETIZER beats=%u starts=%u req=%u done=%u state=%08x\r\n",
               Xil_In32(0x40000028U), Xil_In32(0x4000002CU),
               Xil_In32(0x40000030U), Xil_In32(0x40000034U),
               Xil_In32(0x40000038U));
    xil_printf("DIAG_NODE_RGMII reset_clk_tx=%08x\r\n",
               Xil_In32(0x4000003CU));
}

static void halt(const char *where, u32 a, u32 b)
{
    xil_printf("LATEST_FATAL where=%s a=%08x b=%08x\r\n", where, a, b);
    for (;;) sleep(1U);
}

static void reset_channel(u32 control)
{
    u32 i;
    Xil_Out32(VDMA + control, 4U);
    for (i = 0; i < 1000000U; ++i)
        if ((Xil_In32(VDMA + control) & 4U) == 0U) return;
    halt("VDMA_RESET_TIMEOUT", control, Xil_In32(VDMA + control));
}

/* The checked-in BSP describes a different historical VDMA (24/64-bit
 * stream widths) than the latest-frame hardware, whose XCI is 32/32-bit.
 * Do not call run_vdma_frame_buffer(): its width-derived HSIZE would program
 * the wrong geometry before the PL owner starts.  Program the current IP's
 * documented registers directly, with byte geometry explicit. */
static void start_capture_write_direct(void)
{
    u32 i;
    reset_channel(0x00U);
    reset_channel(0x30U);
    Xil_Out32(VDMA + 0x18U, 3U);
    Xil_Out32(VDMA + 0x48U, 3U);
    for (i = 0; i < 3U; ++i) {
        u32 addr = FRAME_BASE + i * FRAME_BYTES;
        Xil_Out32(VDMA + 0x5CU + i * 4U, addr);
        Xil_Out32(VDMA + 0xACU + i * 4U, addr);
        Xil_Out32(addr, DDR_SENTINEL);
        Xil_Out32(addr + FRAME_BYTES - 4U, DDR_SENTINEL);
        Xil_DCacheFlushRange(addr, 32U);
        Xil_DCacheFlushRange(addr + FRAME_BYTES - 32U, 32U);
    }
    /* MM2S geometry (32-bit stream) and S2MM geometry (32-bit stream). */
    /* S2MM free-runs from camera TUSER/TLAST; MM2S is PL-fsync driven. */
    /* The latest-frame VDMA is a dynamic-genlock pair: S2MM is the dynamic
     * master (XCI c_s2mm_genlock_mode=2), while MM2S is the dynamic slave
     * driven by PL mm2s_fsync (XCI c_mm2s_genlock_mode=3).  The driver and
     * successful cyclic reference both leave SYNC_EN clear on the master.
     * The previous code forced 0x8b on S2MM as well, enabling SYNC_EN on the
     * master and producing S2MM 0x15810 (internal/SOF-late) at first frame.
     * Keep internal-genlock selection on the MM2S slave only; run S2MM as a
     * plain circular capture channel so camera VSYNC is its frame boundary. */
    Xil_Out32(VDMA + 0x30U, (Xil_In32(VDMA + 0x30U) & 0xFFFF0000U) |
                           CR_RUN_CIRC_NO_SYNC);
    /* The current VDMA configuration has no MM2S frame-pointer input.  In
     * dynamic-slave mode an external FSYNC restarts the same read pointer
     * (confirmed by ARADDR slot 0 on the board).  Run MM2S as a plain
     * circular channel so its hardware frame-store pointer advances through
     * all three slots; the PL gate still rejects a slot unless it is the
     * newest committed generation. */
    Xil_Out32(VDMA + 0x00U, (Xil_In32(VDMA + 0x00U) & 0xFFFF0000U) |
                           CR_RUN_CIRC_NO_SYNC);
    Xil_Out32(VDMA + 0x54U, LINE_BYTES);
    Xil_Out32(VDMA + 0x58U, LINE_BYTES);
    Xil_Out32(VDMA + 0xA4U, LINE_BYTES);
    Xil_Out32(VDMA + 0xA8U, LINE_BYTES);
    /* In direct-register mode VSIZE is the start command.  It must be the
     * final geometry write, after control, addresses, HSIZE and STRIDE. */
    Xil_Out32(VDMA + 0x50U, LINES);
    Xil_Out32(VDMA + 0xA0U, LINES);
    if ((Xil_In32(VDMA + 0x34U) & SR_ERRORS) != 0U) {
        xil_printf("DIAG_VDMA_WRITE_START_ERROR sr=%08x hsize=%08x vsize=%08x\r\n",
                   Xil_In32(VDMA + 0x34U), Xil_In32(VDMA + 0xA4U),
                   Xil_In32(VDMA + 0xA0U));
        print_vdma_snapshot();
        halt("VDMA_WRITE_START", Xil_In32(VDMA + 0x34U),
             Xil_In32(VDMA + 0xA4U));
    }
}

static void wait_camera_input_stable(void)
{
    /* Do not leave the AXIS video stream running while S2MM is stopped.
     * v_vid_in_axi4s cannot replay the pixels that arrive during this wait;
     * starting VDMA immediately after camera init keeps the first accepted
     * SOF and the S2MM frame boundary in the same startup window. */
    xil_printf("LATEST_CAMERA_INPUT_START_NOW lines=%08x activity=%08x\r\n",
               Xil_In32(CAMERA_DBG_BASE + 0x0CU),
               Xil_In32(CAMERA_DBG_BASE + 0x08U));
}

static void wait_capture_write(void)
{
    u32 poll, slot, changed = 0U, first_error = 0U;
    u32 heads[3], tails[3];
    /* Keep sampling after the first error. The first-error sample identifies
     * the failing boundary; later samples show whether S2MM recovered or
     * stopped, all in one board run. */
    for (poll = 0U; poll < 20U; ++poll) {
        u32 status;
        usleep(100000U);
        status = Xil_In32(VDMA + 0x34U);
        if (first_error == 0U && (status & SR_ERRORS) != 0U)
            first_error = poll + 1U;
        for (slot = 0U; slot < 3U; ++slot) {
            u32 addr = FRAME_BASE + slot * FRAME_BYTES;
            Xil_DCacheInvalidateRange(addr, 32U);
            Xil_DCacheInvalidateRange(addr + FRAME_BYTES - 32U, 32U);
            heads[slot] = Xil_In32(addr);
            tails[slot] = Xil_In32(addr + FRAME_BYTES - 4U);
            if (heads[slot] != DDR_SENTINEL && tails[slot] != DDR_SENTINEL)
                changed |= 1U << slot;
        }
        xil_printf("DIAG_SAMPLE n=%u s2mm=%08x pkt_start=%u udp_done=%u written=%x head=%08x,%08x,%08x tail=%08x,%08x,%08x\r\n",
                   poll + 1U, status, Xil_In32(ETH + 0x2CU),
                   Xil_In32(ETH + 0x34U), changed,
                   heads[0], heads[1], heads[2], tails[0], tails[1], tails[2]);
        if (poll == 0U)
            print_camera_snapshot("SAMPLE");
    }
    xil_printf("LATEST_DDR_EVIDENCE heads=%08x,%08x,%08x tails=%08x,%08x,%08x written_mask=%x s2mm=%08x\r\n",
               heads[0], heads[1], heads[2], tails[0], tails[1], tails[2],
               changed, Xil_In32(VDMA + 0x34U));
    print_s2mm_status_detail(Xil_In32(VDMA + 0x34U));
    if (first_error != 0U)
        xil_printf("DIAG_ROOT_CANDIDATE first_s2mm_error_sample=%u\r\n", first_error);
    if (changed == 0U) {
        print_vdma_snapshot();
        halt("CAPTURE_DDR_NOT_READY", changed, Xil_In32(VDMA + 0x34U));
    }
}

int main(void)
{
    u32 prev_udp, prev_start, camera_id;
    xil_printf("\r\nLATEST_FRAME_PL_OWNER_BEGIN frame=800x480 rgb888 slots=3\r\n");
    /* The generated camera IP holds cam_rst_n high; +0x0C is a line-count
     * readback, not a hardware reset command. OV5640_Init resets via SCCB. */
    SCCB_Init();
    if (OV5640_Init() != 0U) halt("CAMERA_INIT", 0, 0);
    camera_id = ((u32)sccb_read_reg16(0x300A) << 8) |
                sccb_read_reg16(0x300B);
    if (camera_id != 0x5640U) halt("CAMERA_ID", camera_id, 0x5640U);
    xil_printf("LATEST_CAMERA_READY id=%02x%02x mode=%02x hts=%02x%02x vts=%02x%02x\r\n",
               sccb_read_reg16(0x300A), sccb_read_reg16(0x300B),
               sccb_read_reg16(0x3008),
               sccb_read_reg16(0x380C), sccb_read_reg16(0x380D),
               sccb_read_reg16(0x380E), sccb_read_reg16(0x380F));
    wait_camera_input_stable();
    Xil_Out32(VDMA + 0x28U, 0U);
    start_capture_write_direct();
    xil_printf("LATEST_VDMA_STARTED mm2s=%08x/%08x s2mm=%08x/%08x park=%08x hsize=%u\r\n",
               Xil_In32(VDMA), Xil_In32(VDMA + 4U),
               Xil_In32(VDMA + 0x30U), Xil_In32(VDMA + 0x34U),
               Xil_In32(VDMA + 0x28U), LINE_BYTES);
    wait_capture_write();
    /* Always emit the full node snapshot after the first DDR write evidence,
     * not only on a fatal path. This lets one board run distinguish camera /
     * RGB packer / VDMA S2MM / MM2S / packetizer / RGMII without interpretation
     * from aggregate frame counts alone. */
    print_vdma_snapshot();
    prev_start = Xil_In32(ETH + 0x2CU);
    prev_udp = Xil_In32(ETH + 0x34U);
    Xil_Out32(DIAG_BASE + 0x00U, 0x4C415445U);
    Xil_Out32(DIAG_BASE + 0x04U, Xil_In32(VDMA + 4U));
    Xil_Out32(DIAG_BASE + 0x08U, Xil_In32(VDMA + 0x34U));
    Xil_Out32(DIAG_BASE + 0x0CU, Xil_In32(ETH + 0x2CU));
    Xil_Out32(DIAG_BASE + 0x10U, Xil_In32(ETH + 0x34U));
    Xil_Out32(DIAG_BASE + 0x14U, Xil_In32(ETH + 0x00U));
    Xil_Out32(DIAG_BASE + 0x18U, Xil_In32(ETH + 0x38U));
    Xil_Out32(DIAG_BASE + 0x1CU, Xil_In32(ETH + 0x3CU));
    for (;;) {
        u32 rs, ws, starts, done;
        sleep(5U);
        rs = Xil_In32(VDMA + 4U);
        ws = Xil_In32(VDMA + 0x34U);
        starts = Xil_In32(ETH + 0x2CU);
        done = Xil_In32(ETH + 0x34U);
        xil_printf("LATEST_PROGRESS mm2s=%08x s2mm=%08x park=%08x pkt_start=%u udp_done=%u delta=%u/%u\r\n",
                   rs, ws, Xil_In32(VDMA + 0x28U), starts, done,
                   starts - prev_start, done - prev_udp);
        prev_start = starts; prev_udp = done;
        Xil_Out32(DIAG_BASE + 0x04U, rs);
        Xil_Out32(DIAG_BASE + 0x08U, ws);
        Xil_Out32(DIAG_BASE + 0x0CU, starts);
        Xil_Out32(DIAG_BASE + 0x10U, done);
        Xil_Out32(DIAG_BASE + 0x14U, Xil_In32(ETH + 0x00U));
        Xil_Out32(DIAG_BASE + 0x18U, Xil_In32(ETH + 0x38U));
        Xil_Out32(DIAG_BASE + 0x1CU, Xil_In32(ETH + 0x3CU));
        if ((rs & SR_ERRORS) || (ws & SR_ERRORS) ||
            (rs & 1U) || (ws & 1U)) halt("VDMA_STOP_OR_ERROR", rs, ws);
    }
}
