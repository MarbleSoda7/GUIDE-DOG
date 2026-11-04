# latest_project_pl_rectify — 双目 PL 硬件矫正副本

## 当前状态：PL 矫正固件已构建、已封存、已打包进 SD 启动包

本目录从 D:/latest_project 独立复制，在副本加入单个共享 PL remap 核，处理两路 OV5640 的 800×480 RGB888。源目录没有作为本次修改目标。

2026-11-04 已实际执行完整构建链（不是源码交接状态）：

| 阶段 | 结果 |
|---|---|
| HLS 综合导出 | `xilinx.com:hls:pl_remap_accel:1.0`，估计 35 BRAM18 / 38 DSP / 6,748 FF / 9,394 LUT，目标 10ns |
| Vivado 集成 | BD 加入 pl_remap_accel_0 + remap_axi_guard_0，M07/M08→0x40000000/0x40020000，HLS gmem→S03→HP0 |
| 综合/实现/比特流 | 完成。routed WNS **+0.150ns**、TNS 0.000、0 failing endpoint（82,918）、WHS +0.029、WPWS +2.000；“All user specified timing constraints are met.” |
| 资源（placed） | LUT 19,144/53,200 = **35.98%**；FF 31,352/106,400 = 29.47%；Slice 10,033/13,300 = 75.44%；BRAM Tile 31.5/140 = 22.50%（RAMB36 28 + RAMB18 7）；DSP 50/220 = 22.73% |
| DRC | routed 140 项全部 Warning/Advisory（DPIP/DPOP 流水建议、REQP-1839/1840 RAMB 异步复位、PLCK-12），**0 Error**；methodology 43 项 Warning |
| 功耗 | 2.067 W（dynamic 1.910 + static 0.157），junction 48.8 °C，Confidence Low |
| 产物封存 | artifacts/pl_rectify 下 bit/HWH/XSA + manifest.json，seal 校验 XSA 内 bit/HWH 哈希一致且 HWH 含新核与 guard |
| SD 启动包 | 已重打包并部署到 sd_card_latest；旧包备份在 sd_card_original_backup |

默认运行模式仍是 `--rectify off`（原始图回退）。只有配套的新 bit/HWH 就位时才可 `--rectify pl`；应用会在启动时校验 HWH 是否含 pl_remap_accel_0 与 remap_axi_guard_0，不匹配直接拒绝。

**已证明**：HLS/RTL 可综合性、Vivado 时序收敛、资源与功耗、bit/HWH/XSA 同轮一致、启动包含新比特流与新应用、离线 58 项测试与 16 组全帧 C++ 数值比对。
**尚未证明**：上板图像质量、真实双目标定精度、≥10 pair/s 吞吐、曝光同步；本工程不含视差匹配或深度测距。

## SD 卡怎么用

`sd_card_latest` 是可写卡内容，直接整体复制到 SD 卡第一分区（FAT）：

| 文件 | 大小 | 说明 |
|---|---:|---|
| BOOT.BIN | 5,216,720 | FSBL + **新 led_test_wrapper.bit** + u-boot + system.dtb |
| image.ub | 41,990,516 | kernel + DTB + initramfs（内含新版 camremap 应用、LUT、bit/HWH 副本） |
| boot.scr | 3,473 | fatload image.ub → bootm |
| camremap/args | 18 | `--fps 5 --frames 0` |

启动脚本只从 SD 的 `camremap/` 读 args（不读代码），所以换参数改这里即可；应用和数据也能被 SD 覆盖（查找顺序 `/media/sd-mmcblk0p1/camremap` → `/run/media/mmcblk0p1/camremap` → `/usr/share/camremap`）。

上板步骤：

1. 断电写卡，插卡上电；串口/UART 观察 FSBL 是否加载新 bit。
2. 默认 args 为 raw 模式，先确认两路图像正常（`--rectify off` 回退）。
3. 停服务再手工跑 PL 烟测（合成 LUT，必须显式允许）：

~~~sh
/etc/init.d/camremap stop
python3 -u -m camremap --rectify pl --allow-synthetic-lut --frames 20 --fps 5 --verify-remap-crc
~~~

4. 通过后改用实测 LUT（见下节）并把 SD `camremap/args` 改成 `--rectify pl --fps 10`。
5. 失败时退出码 2/3 会写 `/run/camremap-fatal` 并停止自动重启；必须先重配 PL 或重启板卡，再 `/etc/init.d/camremap clear-fatal`。

RK 侧协议不变：UDP 1234、800×480 RGB888、12 字节 v1 头、827 包（826×1394+556），cam1/cam2 同一 pair_id。

## 换摄像头参数 / 重新标定（不重综合）

参数入口 [tools/camera_params.json](<D:/latest_project_pl_rectify/tools/camera_params.json>)：左右眼 K/D/R/rectified_K 与 step。当前随包 LUT 是 `calibration_valid=false` 的合成烟测参数（170°→100° 视场、40mm 基线假设），不能当实测精度。

只改标定参数或 step 时，硬件不用动，重新生成两份 LUT + manifest 并部署到应用的 data 目录（或 SD 的 camremap/）即可：

~~~sh
python3 tools/stereo_calibrate.py --left-dir calibration/left --right-dir calibration/right \
    --square-mm 20 --cols 9 --rows 6 --out tools/camera_params_measured.json --grid-dir calibration/luts
python3 tools/generate_remap_lut.py --config tools/camera_params_measured.json --step 16 \
    --output-dir zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data
~~~

改分辨率/像素格式/位宽才需要改 RTL 并重综合。

## 重建（仅在需要时）

~~~powershell
./BUILD_PL_RECTIFY.ps1                 # 只做静态预检，不启动硬件工具
./BUILD_PL_RECTIFY.ps1 -Build -Force   # HLS → 集成 → 综合/实现/bit → 封存
~~~

构建后有专门的续跑脚本，避免重复综合未变化的 OOC IP：`tools/finish_impl_pl_rectify.tcl`（route 后校验 WNS，再 write_bitstream 并出 XSA）。

SD 打包（无需 PetaLinux）：

~~~powershell
python tools/pack_sd_image.py --ub sd_card_original_backup/image.ub --out .tmp_pack/image.ub.new \
    --app zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/camremap \
    --data zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data
bootgen -image .tmp_pack/boot.bif -o BOOT.BIN -arch zynq
~~~

## 先读这些入口

- [离线验证与构建记录](<D:/latest_project_pl_rectify/PL_RECTIFY_VERIFICATION.md>)：58/58 测试、C++ 全帧比对、构建实测数据。
- [PL 矫正完整实施与交接说明](<D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/PL_REMAP_README.md>)：数据路径、DDR 布局、寄存器 ABI、RMP2 格式、运行与验收边界。
- [PL 矫正核源码](<D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/pl_remap_accel.cpp>)：单 AXI master、Q10.6 网格、8KiB 源图 cache、双线性 RGB888、输出 CRC。
- [构建产物与清单](<D:/latest_project_pl_rectify/artifacts/pl_rectify/manifest.json>)：bit/HWH/XSA 哈希与源码快照。

## 文件夹用途

| 目录 | 当前含义 |
|---|---|
| artifacts/pl_rectify | 本次构建的 bit/HWH/XSA 与封存清单 |
| sd_card_latest | **可写卡的新启动包**（BOOT.BIN + image.ub + boot.scr + camremap/args） |
| sd_card_original_backup | 替换前的旧启动包备份 |
| zynq_project/vivado | Vivado 工程、PL 源码、guard、HLS 与集成脚本 |
| zynq_project/petalinux_key | Linux 应用源码与随包数据（LUT/manifest/bit/HWH） |
| rk_receiver | RK 双目接收源码及部署脚本 |
| tools | 参数、标定、LUT 生成、FIT/cpio 打包与软件参考模型 |
| tests | 离线单元测试与主机 C++ 核验证 |

## 数据链路

双 OV5640 → 两路 VDMA/DDR 三槽 → 停写入后复制快照 → 同一 PL 核先左后右矫正 → 两眼均完成 → cam1 全帧 UDP → cam2 全帧 UDP → RK 显示。

PS 负责控制、快照与调度，不做逐像素 remap。两摄像头仍自由曝光，pair_id 只是软件配对序号，不是共同曝光时间戳。

## 不变的 UDP 协议

~~~text
[D2][C2][ver=01][camera_id][pair_id BE16][total=827 BE16][idx BE16][plen BE16][RGB888]
~~~

单物理网口、UDP 1234；每眼 1,152,000 字节，826 包×1394 字节加尾包 556 字节；cam1 与 cam2 使用同一 pair_id。RK 原双目显示链可继续使用。

## 后续待做

1. 真实双目标定（棋盘格 ≥15 组）→ 生成实测 LUT → 精度与极线误差验收。
2. 板级验证 ≥10 pair/s；当前“停 VDMA + 等 3 次 writer 轮转”的保守快照策略会限制吞吐，必要时实现硬件 frame ownership。
3. 需要测距时再加视差匹配（StereoBM/SGM）与深度换算，PL 侧可选做 remap 加速之外的匹配加速。
