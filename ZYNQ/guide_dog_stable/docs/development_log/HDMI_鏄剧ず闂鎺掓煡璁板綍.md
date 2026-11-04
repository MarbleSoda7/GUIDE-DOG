# 25_ov5640_hdmi / hdmi_test 显示问题排查记录

**日期**: 2026-09-18
**结论**: HDMI"无信号"的根因是**分辨率不兼容**，不是硬件或软件故障。

---

## 问题现象

- 板子: LubanCat-2 / 野火 ZYNQ-7020 (`xc7z020clg400-1`)
- 现象: 运行彩条测试程序后，HDMI 显示器显示 **"无信号输入"**
- 所有 PS 侧寄存器读数**完全正常**

## 排查过程（全部为"正常"的项）

| 检查项 | 读数 | 结论 |
|---|---|---|
| MM2S_CR | `0x00014083` | RS=1，读通道运行中 |
| MM2S_SR | `0x00010000` | Halted=0, Idle=0，正在搬运 |
| MM2S_ADDR1 | `0x11000000` | 帧缓冲地址正确 |
| VTC_CTRL | `0x03F7EF06` | 时序发生器运行中 |
| DynClk STAT | `0x00000001` | MMCM 已使能（穿过 WAIT_LOCKED，证明 locked=1）|
| 帧缓冲内容 | `0xFFFFFFFF 0x00FFFF00 ...` | 彩条数据正确 |
| PS PLL_STATUS | `0x0000003F` | ARM/DDR/IO PLL 全部锁定 |
| TMDS 引脚 | 见 io_placed.rpt | 差分对 + TMDS_33 全部正确 |

**软件侧没有任何问题。**

## 根因

```
VMODE_800x480  = 800x480@60Hz,  像素时钟 33.0 MHz   →  显示器"无信号"  ❌
VMODE_1280x720 = 1280x720@60Hz, 像素时钟 74.25 MHz  →  正常显示彩条    ✅
```

**800×480 是非标准 HDMI 时序**。显示器如果不支持该分辨率，会直接报无信号，
即使 FPGA 侧的 VTC / VDMA / TMDS 全部工作正常。

## 解决方案

修改 `hdmi_test/src/main.c`:

```c
#define TEST_WIDTH   1280                                  /* 原 800  */
#define TEST_HEIGHT  720                                   /* 原 480  */
...
DisplaySetMode(&Dispctrl, &VMODE_1280x720);                /* 原 VMODE_800x480 */
```

## 编译方法（Vitis 2026.1，手工 gcc）

BSP 路径: `ov5640_hdmi/Test_ov_hdmi/export/Test_ov_hdmi/sw/standalone_ps7_cortexa9_0`
编译器: `D:\Software\AMDDesignTools\2026.1\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe`

编译脚本: `_build720.ps1`（工作区根目录）
输出: `ov5640_hdmi/hdmi_test/build/m720/hdmi_test_720p.elf`

## 加载方法（XSDB）

```tcl
connect
targets -set -nocase -filter {name =~ "*xc7z020*"}
fpga -file <zynq_wrapper.bit>
targets -set -nocase -filter {name =~ "*A9*#0"}
rst -processor
source ps7_init.tcl
ps7_init
ps7_post_config
dow <elf>
con
```

脚本: `25_ov5640_hdmi/ov5640_hdmi/run_720p.tcl`

## 720p 下的正确寄存器值（供以后比对）

```
VTC_CTRL    = 0x03F7EF06
DynClk +0   = 0x00000001   CTRL START
DynClk +4   = 0x00000001   STAT (MMCM enabled)
DynClk +8   = 0x00000041   CLK_L
DynClk +12  = 0x0000069A   FB_L
DynClk +16  = 0x00000000   FB_H
DynClk +20  = 0x000020C4   DIV
DynClk +24  = 0xCFAFA401   LOCK_L
DynClk +28  = 0x00A300FF   FLTR
MM2S_CR     = 0x00014083
MM2S_ADDR1  = 0x11000000
```

## 重要注意事项

1. **HDMI 分辨率必须用标准时序**（720p / 1080p / 640x480），
   非标准分辨率（如 800x480）多数电脑显示器不认。
2. **JTAG 被占用**会导致 `targets` 为空 —— 检查残留的 `hw_server.exe` 进程。
3. **板子断电重启后** JTAG 可能短暂连不上，重新插拔 USB 下载器可恢复。
4. 备份文件: `hdmi_test/src/main_800x480.c.bak`（原始 800×480 版本）
