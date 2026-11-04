# ov5640_hdmi 调试记录 (2026-09-18)

## 一、已解决的问题

### 1. HDMI 无信号 —— 分辨率不兼容 ✅ 已解决

```
800x480@60Hz  (33.0 MHz)   →  显示器"无信号"
1280x720@60Hz (74.25 MHz)  →  正常显示
```

**800×480 是非标准 HDMI 时序。** 修改 `hdmi_test/src/main.c`:
```c
#define TEST_WIDTH   1280
#define TEST_HEIGHT  720
DisplaySetMode(&Dispctrl, &VMODE_1280x720);
```

### 2. VDMA Gen-Lock 死锁 ✅ 已解决

**现象**: `MM2S_CR = 0x00010004` (RST=1, RS=0) —— 通道卡在复位状态。

**根因**: `StartTransfer()` 先启动 S2MM 再启动 MM2S，而 `XAxiVdma_DmaStart()`
内部会先 Reset。在 Gen-Lock 模式下，MM2S 的 Reset 需要等 S2MM 的帧同步
信号，而 S2MM 还在等 MM2S 复位完成 —— 互相等待，永久死锁。

**修复** (`ov56_hdmi/src/vdma_api/vdma_api.c`):
```c
L291: vdma_context->ReadCfg.EnableSync  = 0;  /* 原为 1 */
L373: vdma_context->WriteCfg.EnableSync = 0;  /* 原为 1 */
```

**辅助修复** (`ov56_hdmi/src/main.c`) —— VDMA 初始化前先硬复位:
```c
Xil_Out32(VDMA_ID + 0x30, 0x4);   /* S2MM CR: RESET */
Xil_Out32(VDMA_ID + 0x00, 0x4);   /* MM2S CR: RESET */
usleep(1000);
```

### 3. printf 参数缺失 ✅ 已修复
```c
// 原: xil_printf("[7] DisplayStart done, ret=%d\r\n");   → 打印栈垃圾值
// 改: xil_printf("[7] DisplayStart done, ret=%d\r\n", status);
```

## 二、未解决的问题

### HDMI 输出"间歇性失效"

**现象**: 相同代码、相同烧录流程，有时出彩条，有时"无信号"。

**已排除**:
- ❌ 分辨率（720p 已验证可显示）
- ❌ 显示器同步（拔插 HDMI 线无效）
- ❌ 供电（12V/2A 充足）
- ❌ 软件状态（VTC/DynClk/VDMA/帧缓冲全部正确）
- ❌ 引脚约束（io_placed.rpt 确认正确）

**可疑点**:
- `fpga -file` 只配置 PL，**不复位 PL 逻辑**
- `FPGA_RST_CTRL (0xF8000240)` 写入 0x01/0x00 可复位 PL（实测有效）
- 用户经验："烧完彩条再烧摄像头会成功" → 多烧一次能改变结果

## 三、摄像头通路状态

**已验证正常**:
```
cam_id = 0x5640          I2C/SCCB 通信正常
OV5640_Init ret=0        摄像头初始化成功
VDMA setup ret=0
DisplayInitialize ret=0
DisplayStart ret=0
```

**S2MM 报错**: `0x00015810` = ERR_INTERNAL + ERR_FSZ_MORE + IRQ_FRMCNT + IRQ_ERR
**帧缓冲**: 每次烧录内容不同，但只写一次就冻结

**怀疑**: `ov5640_to_lcd.v` 的 `pic_valid` 同步逻辑

```verilog
L88-94:  cnt_pic 从 0 加到 PIC_WAIT(10)，只需 10 个 PCLK（跨越多行）
L84-85:  pic_flag = VSYNC 上升沿，只维持 1 个 PCLK
L100:    pic_valid 需要 (cnt_pic == PIC_WAIT) && (pic_flag == 1) 同时成立
```

**两者同时成立的窗口极窄 → 能否置位取决于上电瞬间的巧合 → 解释间歇性**

## 四、关键寄存器参考值

### 720p 正常状态
```
VTC_CTRL    = 0x03F7EF06
VTC_STATUS  = 0x00013000
DynClk +0   = 0x00000001   (CTRL START)
DynClk +4   = 0x00000001   (STAT, bit0=MMCM enabled)
DynClk +8   = 0x00000041
DynClk +12  = 0x0000069A
DynClk +16  = 0x00000000
DynClk +20  = 0x000020C4
DynClk +24  = 0xCFAFA401
DynClk +28  = 0x00A300FF
MM2S_CR     = 0x00014083
```

### 地址映射
```
VDMA            0x43000000
VTC             0x43C00000
OV5640_TO_LCD   0x43C10000
DynClk          0x43C20000
hdmi_transmitter 0x43C30000
帧缓冲          0x11000000
```

### PS 时钟
```
PLL_STATUS    (0xF800010C) = 0x0000003F   三个PLL全锁定
FPGA0_CLK_CTRL(0xF8000170) = 0x00200500   FCLK_CLK0
FPGA_RST_CTRL (0xF8000240) = 0x00000000   PL复位控制
```

## 五、TMDS 引脚
```
tmds_data_p[0] W14    tmds_data_n[0] Y14
tmds_data_p[1] Y16    tmds_data_n[1] Y17
tmds_data_p[2] Y18    tmds_data_n[2] Y19
tmds_clk_p     V20    tmds_clk_n     W20
tmds_oen       T20    (LVCMOS33)
```

## 六、摄像头引脚
```
ov5640_pclk   L19      ov5640_vsync  M19
ov5640_href   M20      cam_xclk_0    L20
cam_rst_n     M18      cam_pdn_0     M17
ov5640_data[0..7]  N15 N16 L14 L15 M14 M15 L16 L17
cam_sccb[0,1]      T17 R18
```

## 七、编译与烧录

**编译** (Vitis 2026.1 手工 gcc):
```powershell
powershell -File _build_camfix.ps1      # 摄像头程序
powershell -File _build720.ps1          # 彩条程序
```

**烧录** (XSDB):
```tcl
connect
targets -set -nocase -filter {name =~ "*xc7z020*"}
fpga -file <bit>
targets -set -nocase -filter {name =~ "*A9*#0"}
rst -processor
source ps7_init.tcl
ps7_init
ps7_post_config
dow <elf>
con
```

## 八、教训

1. **"寄存器全对但无输出" 时，先试标准分辨率**
2. **VDMA 的 `IntErr` 位在 Gen-Lock 模式下可能无害**
3. **`FRMCNT` 静止 ≠ VDMA 停摆**（只在帧计数中断时更新）
4. **Gen-Lock 模式的 Reset 握手会死锁**，调试时先关掉
5. **`fpga -file` 不复位 PL 逻辑**，必要时用 `FPGA_RST_CTRL`
