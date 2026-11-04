# Stage5 全链路探针

## 固定入口

- 源码：`ddr_pl_dma_udp/sw/stage4_camera_main.c`
- 构建：`ddr_pl_dma_udp/build_stage5_camera_continuous_elf.ps1`
- 烧录：`run_stage5_camera_continuous.ps1`
- 仅更新 ELF：`xsdb reload_stage5_elf.tcl`（RTL 未变时使用）
- 快照读取：`read_stage5_diag.tcl`
- 快照地址：DDR `0x00300000`
- DDR 样本读取：`read_stage5_frame_samples.tcl`（只读）
- 当前 ELF：`test_artifacts/stage5_camera_continuous_sg_udp.elf`
- 当前 bitstream：`test_artifacts/stage3b_sg_udp.bit`

## 快照格式

读取 50 个 32-bit word（word 0..49）：

| word | 含义 |
|---:|---|
| 0 | 固定 magic `0x53544735` (`STG5`) |
| 1 | 最后节点编号 |
| 2 | 帧号或节点上下文 |
| 3 | source/frame base 或 PARKPTR 返回值 |
| 4 | 节点辅助值，例如轮询次数 |
| 5 | PARKPTR |
| 6 | VDMA S2MM status |
| 7 | AXI DMA MM2S status |
| 8 | DMA 输入侧 TLAST 数（word 37 的高 16 位） |
| 9 | packetizer `pkt_start` |
| 10 | packetizer `udp_done` |
| 11 | `ov5640_to_lcd` 每帧 href 计数 |
| 12 | `ov5640_to_lcd` 每帧 tft_de 计数 |
| 13 | `ov5640_to_lcd` 每帧 tft_ce 计数 |
| 14 | `ov5640_to_lcd` 每帧 tft_de 行数 |
| 15 | 帧槽 0 首字（`0x11000000`） |
| 16 | 帧槽 1 首字（`0x11119400`） |
| 17 | 帧槽 2 首字（`0x11232800`） |
| 30 | AXI DMA MM2S control |
| 31 | AXI DMA MM2S status |
| 32 | AXI DMA MM2S current descriptor |
| 33 | AXI DMA MM2S tail descriptor |
| 34 | DMA 到异步 FIFO 输入侧已接受 AXIS beat 数 |
| 35 | DMA 到异步 FIFO 输入侧 TLAST 数 |
| 36 | DMA 到异步 FIFO 输入侧 TVALID 背压周期数 |
| 37 | `0x1C` 的低 16 位：packetizer AXIS 实时状态，bit9 `beat_last`、bit8 `beat_valid`、bit7:5 `beat_pos`、bit4:3 `state`、bit2 `TVALID`、bit1 `TREADY`、bit0 `TLAST`；高 16 位为 word 8 的 DMA TLAST 数 |
| 29 | packetizer `state` 位于 bit31:30，低 30 位为 `byte_steps`；它只在 packetizer 实际消费已锁存 AXIS beat 的一个字节时递增。 |
| 38..41 | AXIS sweep `always-ready`：DMA status、读侧 beat、读侧 TLAST、总轮询数（DMA IOC 加消费者排空）。 |
| 42..45 | AXIS sweep `1-in-9 ready`：DMA status、读侧 beat、读侧 TLAST、总轮询数（DMA IOC 加消费者排空）。 |
| 46..49 | AXIS sweep `packetizer`：DMA status、packetizer beat、byte_steps、总轮询数（DMA IOC 加消费者排空）。 |

## 节点编号

- `10`: 进入程序
- `11`: SCCB 初始化前
- `12`: OV5640 初始化完成
- `20`: VDMA 驱动配置前
- `21`: VDMA 配置完成并采样状态
- `22`: Ethernet/时钟 settle 前
- `23`: 当前 UDP bitstream 的 HDMI 对照分界点；不访问已删除的 VTC/dynamic-clock
- `27/28`: 等待 5 秒后的摄像头计数与三个 DDR 帧槽首字读取前/完成
- `30`: 初次 PARKPTR 读取前
- `31/32`: 初次 PARKPTR 轮询前/返回后
- `33`: 首个安全帧槽选定
- `40`: SG ring 构建完成
- `41`: AXI DMA reset 前
- `42`: AXI DMA 寄存器设置前
- `43`: AXI DMA 已启动
- `44`: AXI DMA status 轮询前
- `45`: AXI DMA 完成
- `46`: packetizer 计数器最终采样
- `70/71`: 下一帧 PARKPTR 读取前/返回后
- `79`: 下一帧安全槽等待超时
- `90`: 三种 AXIS consumer sweep 均记录完成
- `91`: sweep 停机或 reset 未在限定时间内完成；word 2 指明模式，word 4 为失败码
- `92`: 所有 sweep 通过后，真实生产描述符环的一帧发送及计数验收完成

## 维护规则

1. 新增节点只使用未占用编号，并保留已有编号语义。
2. 任何可能阻塞的 MMIO 访问前先写 `diag_mark()`；访问完成后再写返回节点。
3. 新增快照字段必须同步修改 `read_stage5_diag.tcl` 和本文档。
4. 不删除 `test_artifacts` 中的历史 ELF/bitstream；每次 ELF 变更更新烧录脚本 MD5 门禁。
5. 诊断结论必须同时记录到 `FIX_LEDGER.md`，包括节点值、寄存器值和 RK 计数证据。

## RGMII TXC physical sweep

- Node `93`: requested TXC phase was not observed as locked/active; word 2 is
  the requested phase and word 3 is the raw Ethernet status.
- Node `94`: four real-camera production sends completed. Words `50..69` are
  four five-word records for TXC phase `0/90/180/270` degrees: requested
  phase, raw status (`bit4=MMCM locked`, `bit3:2=active phase`), DMA TLAST
  delta, packet-start delta, UDP-done delta.
- This sweep changes only the TXC phase. TXD/TX_CTL ODDRs, camera DDR source,
  DMA geometry, packetizer, UDP parameters, and RK raw capture remain fixed.
