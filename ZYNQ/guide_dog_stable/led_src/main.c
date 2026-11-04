/**
  ******************************************************************************
  * main.c — OV5640 → DDR → PL UDP → RK3568 (v5 语义恢复版)
  *
  * 恢复自实测成功组合: bit E08F3130 + ELF 8A452210 (827/827, PC 有画面)
  *   - STATUS: bit0=frame_req, bit1=tx_busy
  *   - 每包等 tx_busy==0 再写下一包 (v5 节奏, CDC 天然安全)
  *   - PKT_WIRE=1404 + 牺牲字 (RTL off-by-one → RK SKIP=4 兼容)
  *   - BOTH + DisplayInitialize (A/B 实证: 否则 S2MM 不工作)
  ******************************************************************************
  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "xil_types.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "xaxivdma.h"
#include "xaxivdma_i.h"
#include "display_ctrl/display_ctrl.h"
#include "vdma_api/vdma_api.h"
#include "sccb/sccb_init.h"
#include "ov5640/ov5640_init.h"

/* ---------- LED ---------- */
#define LED_GPIO_BASEADDR   0x41200000
static void led_init(void)
{
	Xil_Out32(LED_GPIO_BASEADDR + 0x4, 0x0);
	Xil_Out32(LED_GPIO_BASEADDR + 0x0, 0x0);
}

#define NODE_MAIN_ENTRY       1
#define NODE_SCCB_PRE         2
#define NODE_SCCB_DONE        3
#define NODE_READ_ID_PRE      4
#define NODE_CAM_ID           5
#define NODE_OV_INIT_DONE     6
#define NODE_VDMA_DONE        7
#define NODE_ETH_REG_OK       8
#define NODE_WAIT_GIMME       9
#define NODE_TXING            10
#define NODE_TX_DONE          11
#define NODE_FRAMES_SENT      12
#define NODE_HEARTBEAT        13
#define NODE_ERR_ETH_REG      14
#define NODE_ERR_ZERO_FRAME   15

static inline void node_led(unsigned char node)
{
	Xil_Out32(LED_GPIO_BASEADDR + 0x0, node & 0xF);
}

static void busy_wait_us(unsigned int us)
{
	volatile unsigned int cnt = us * 60;
	while (cnt--) ;
}

static void show_node(unsigned char node)
{
	node_led(node);
	busy_wait_us(200000);
}

/* ---------- 摄像头 ---------- */
#define VDMA_ID       XPAR_AXI_VDMA_0_BASEADDR
unsigned int const FB_Base = (0x10000000 + 0x1000000);
XAxiVdma     vdma;
VideoMode    VIDEO_Mode;

/* ---------- eth_stream 寄存器 ---------- */
#define ETH_BASEADDR  0x40000000
#define ETH_STATUS    (ETH_BASEADDR + 0x00)
#define ETH_CTRL      (ETH_BASEADDR + 0x04)
#define ETH_TXSTART   (ETH_BASEADDR + 0x08)   /* bank0 */
#define ETH_TXSTART1  (ETH_BASEADDR + 0x18)   /* bank1 (one-hot) */
#define ETH_TXBYTES   (ETH_BASEADDR + 0x0C)
#define ETH_RAM_WA    (ETH_BASEADDR + 0x10)
#define ETH_RAM_WD    (ETH_BASEADDR + 0x14)

#define ST_FRAME_REQ  0x1
#define ST_TX_BUSY    0x2

/* ---------- 帧分块 ---------- */
#define FRAME_W       800
#define FRAME_H       480
#define FRAME_BYTES   (FRAME_W * FRAME_H * 3)
#define PAYLOAD       1394
#define TOTAL_PKTS    ((FRAME_BYTES + PAYLOAD - 1) / PAYLOAD)
#define PKT_BYTES     1400                                    /* 6头+1394 */
#define PKT_WIRE      1404   /* RTL off-by-one: 4B洞 + 1400, MTU内(≤1458) */

/* ---------- 发送缓冲 ---------- */
static u8 pb[PKT_BYTES + 4] __attribute__((aligned(4)));

/* ---------- 一键自检模式 (DIAG=1) ----------
   每包内容编码: [bank][pkt低8位][字位置递增] — 抓包直接判读
   正常线格式(应见): [4B零洞][fid=帧号][tot=033B][idx=包号][AAAA BBBB CCCC...]
   DIAG线格式(应见): [4B零洞][fid=帧号][tot=033B][idx=包号][bank][pkt][00 01 02..] */
#define DIAG 0  /* FIX-008: 关闭线上诊断图案，恢复真实帧协议 */

/* 自检结果 (存错误样本, 发送时画进画面顶部) */
static u32 dbg_n = 0;
static u32 dbg_bank0_errs = 0, dbg_bank1_errs = 0;
static u32 dbg_addr[4], dbg_got[4], dbg_exp[4];

/* ---------- 撕裂根治: 帧快照 (2026-09-20) ----------
   DDR 三帧环每帧 1.15MB 连续重写; PS 私有快照 2ms 拷出后发送,
   与 S2MM 写入彻底解耦。PARKPTR[12:8]=S2MM 当前写帧, 取 (W+2)%3 刚完帧 */
#define VDMA_S2MM_DMACR  (0x43000000 + 0x30)   /* S2MM_DMACR: bit0=RUN */
#define VDMA_S2MM_DMASR  (0x43000000 + 0x34)   /* S2MM_DMASR: bit0=Halted */
#define VDMA_PARKPTR     (0x43000000 + 0x28)   /* PARK_PTR: [12:8]=WR, [4:0]=RD */
#define VDMA_MM2S_DMACR  (0x43000000 + 0x00)   /* MM2S_DMACR: bit0=RUN */
static u8 snap[FRAME_BYTES] __attribute__((aligned(32)));

/* 组包: 6B 头 + PAYLOAD 数据 */
static void fill_pb(u8 *fb, u32 off, u16 fid, u16 idx)
{
	pb[0] = (fid >> 8) & 0xFF;
	pb[1] = fid & 0xFF;
	pb[2] = (TOTAL_PKTS >> 8) & 0xFF;
	pb[3] = TOTAL_PKTS & 0xFF;
	pb[4] = (idx >> 8) & 0xFF;
	pb[5] = idx & 0xFF;
	u32 copy = (off + PAYLOAD <= FRAME_BYTES) ? PAYLOAD : (FRAME_BYTES - off);
	memcpy(&pb[6], fb + off, copy);
	if (copy < PAYLOAD)
		memset(&pb[6 + copy], 0, PAYLOAD - copy);
}

/* 写 BRAM 到指定 bank: 每半区 512 字 = 2048 字节
   bank0: 字节 0x000-0x7FF, bank1: 字节 0x800-0xFFF (字地址 bit10=bank) */
/* XPM FIFO wire layout: 显式4B零洞 + 350个pb字，保持RK SKIP=4兼容。
   旧BRAM的+1隐式产生洞；FIFO不做地址偏移，必须在写端显式插洞。 */
static void write_bram_pb(u32 bank)
{
	u32 i;
	(void)bank;
	Xil_Out32(ETH_RAM_WA, 0);      /* 兼容寄存器：FIFO版不使用地址 */
	(void)Xil_In32(ETH_STATUS);
	Xil_Out32(ETH_RAM_WD, 0x00000000);  /* wire[0:3] = RK SKIP hole */
	for (i = 0; i < PKT_BYTES; i += 4)
		Xil_Out32(ETH_RAM_WD,
			((u32)pb[i]   << 24) |
			((u32)pb[i+1] << 16) |
			((u32)pb[i+2] <<  8) |
			 (u32)pb[i+3]);
}

int main(void)
{
	int status;
	u16 cam_id = 0;
	u32 st;
	u32 frame_no = 0;

	led_init();
	show_node(NODE_MAIN_ENTRY);

	/* ---------- 摄像头 ---------- */
	VIDEO_Mode = VMODE_800x480;

	show_node(NODE_SCCB_PRE);
	SCCB_Init();
	show_node(NODE_SCCB_DONE);

	show_node(NODE_READ_ID_PRE);
	cam_id  = sccb_read_reg16(0x300b);
	cam_id |= sccb_read_reg16(0x300a) << 8;
	show_node(NODE_CAM_ID);
	node_led(cam_id & 0xF);
	busy_wait_us(1000000);

	status = OV5640_Init();
	show_node(NODE_OV_INIT_DONE);

	/* BOTH + Display 初始化 (A/B 实证: 否则 S2MM 不工作) */
	status = run_vdma_frame_buffer(&vdma, VDMA_ID, VIDEO_Mode.width,
			VIDEO_Mode.height, FB_Base, 0, 0, BOTH);
	show_node(NODE_VDMA_DONE);

	{
		DisplayCtrl Dispctrl;
		status = DisplayInitialize(&Dispctrl, XPAR_XVTC_0_BASEADDR, XPAR_AXI_DYNCLK_0_BASEADDR);
		DisplaySetMode(&Dispctrl, &VIDEO_Mode);
		status = DisplayStart(&Dispctrl);
	}

	/* ---------- eth 探测 ---------- */
	/* (探针已退役: 真凶=陈旧dcp 已根治) */
	{} /* 探针模式: 不报LED */

	/* ---------- eth 探测(原) ---------- */
	st = Xil_In32(ETH_STATUS);
	if (st == 0xFFFFFFFF) {
		while (1) { node_led(NODE_ERR_ETH_REG); busy_wait_us(500000); }
	}
	show_node(NODE_ETH_REG_OK);

	/* ---------- 主循环 (v5 节奏) ---------- */
	while (1) {
		/* 1. 等 GIMME：正常基线显示固定节点码 1001 */
		node_led(NODE_WAIT_GIMME);
		do { st = Xil_In32(ETH_STATUS); } while (!(st & ST_FRAME_REQ));
		Xil_Out32(ETH_CTRL, 1);

		/* 2. 安全快照：S2MM/MM2S持续运行，PS绝不停止或重置VDMA。
		   PARKPTR[28:24] = 当前S2MM写槽；取(write_slot+2)%3的完整安全槽。 */
		{
			u32 park = Xil_In32(VDMA_PARKPTR);
			u32 write_slot = (park >> 24) & 0x1F;
			u32 safe_slot;
			u32 safe_addr;

			if (write_slot >= 3) write_slot = 0;
			safe_slot = (write_slot + 2) % 3;
			safe_addr = FB_Base + safe_slot * FRAME_BYTES;

			/* S2MM DMA直接写DDR；丢弃CPU对该源帧保留的旧缓存行。 */
			Xil_DCacheInvalidateRange((UINTPTR)safe_addr, FRAME_BYTES);
			memcpy(snap, (const void *)safe_addr, FRAME_BYTES);
		}

			/* 3. 纯 v5 单bank发送：每包写完、触发、等待发送结束 */
			node_led(NODE_TXING);
			for (u32 pkt = 0; pkt < TOTAL_PKTS; pkt++) {
				u32 bank = pkt & 1;   /* 0,1,0,1... */
#if DIAG
				pb[6] = (u8)('A' + bank);
				pb[7] = (u8)(pkt & 0xFF);
				if (pkt == 0) {
					/* 包0数据区头部 = 自检结果报告 (bank0/bank1错数 + 首个错误样本) */
					pb[8]  = (u8)(dbg_bank0_errs & 0xFF);
					pb[9]  = (u8)(dbg_bank1_errs & 0xFF);
					pb[10] = (u8)(dbg_n & 0xFF);
					for (u32 k = 0; k < 4 && k < dbg_n; k++) {
						pb[12 + k*8 + 0] = (u8)dbg_addr[k];
						pb[12 + k*8 + 1] = 0;
						pb[12 + k*8 + 2] = (u8)(dbg_got[k] >> 24);
						pb[12 + k*8 + 3] = (u8)(dbg_got[k] >> 16);
						pb[12 + k*8 + 4] = (u8)(dbg_got[k] >> 8);
						pb[12 + k*8 + 5] = (u8)dbg_got[k];
						pb[12 + k*8 + 6] = (u8)(dbg_exp[k] >> 24);
						pb[12 + k*8 + 7] = (u8)(dbg_exp[k] >> 16);
					}
					for (u32 k = 50; k < 114; k++)
						pb[8 + k] = (u8)k;      /* 校准图案: 50..113 */
				}
				for (u32 k = 114; k < 178; k++)
					pb[8 + k] = (u8)(k - 114); /* 图案2: 00..63 */
				for (u32 k = 178; k < PAYLOAD; k += 1)
					pb[8 + k] = 0x5A;
#else
				fill_pb(snap, pkt * PAYLOAD, (u16)frame_no, (u16)pkt);
#endif
				write_bram_pb(bank);                    /* 单bank固定基址写入 */
				Xil_Out32(ETH_TXBYTES, PKT_WIRE);
				Xil_Out32(ETH_TXSTART, 1);          /* v5 单触发 */
				/* 单bank铁律：必须确认本包发送已完成后才覆写BRAM */
				do { st = Xil_In32(ETH_STATUS); } while (!(st & ST_TX_BUSY));
				do { st = Xil_In32(ETH_STATUS); } while ( st & ST_TX_BUSY);
			}
		/* 本帧全部827包已完成 */

		frame_no++;
		node_led(NODE_TX_DONE);
	}

	return 0;
}