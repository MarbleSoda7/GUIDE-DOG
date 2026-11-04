# PL 双目矫正副本：构建与验证记录

记录时间：2026-11-04（Asia/Shanghai）。对应本轮实际构建产物（bit/HWH/XSA + 新 SD 启动包）。

## 完成范围

- 修改范围为独立副本 D:/latest_project_pl_rectify；源目录 D:/latest_project 未作为写入目标。
- 已实现面向 HLS 的真实 DDR→PL 网格插值/双线性 RGB888→DDR 源码，单核顺序复用左右眼；不是 PS 逐像素软件矫正，也不是 AXIS bypass。
- 已实际执行：HLS 综合导出 → Vivado BD 集成 → 全设计综合 → 实现 → write_bitstream → 同轮 XSA → 产物封存 → image.ub 重打包 → BOOT.BIN 重生成 → 部署到 sd_card_latest。
- 未执行 PetaLinux 重建（工具链缺失），改用 FIT/cpio 原位重打包，内核与 DTB 保持原样。

## 构建实测（不是估计）

| 项目 | 结果 |
|---|---|
| HLS csynth | 目标 10ns；BRAM_18K 35、DSP 38、FF 6,748、LUT 9,394 |
| 实现后资源 | LUT 19,144 (35.98%)、FF 31,352 (29.47%)、Slice 10,033 (75.44%)、BRAM Tile 31.5 (22.50%)、DSP 50 (22.73%)、BUFGCTRL 5、MMCM 1 |
| 时序 | WNS **+0.150ns**、TNS 0.000、0 failing / 82,918 endpoints；WHS +0.029；WPWS +2.000；约束全部满足 |
| 布线 | 66,395 逻辑网，45,667 可布网全部布通，**routing errors 0** |
| DRC (routed) | 140 项，全部 Warning/Advisory，**0 Error**：DPIP-1 31、DPOP-1 31、DPOP-2 42、REQP-1839 20、REQP-1840 9、PLCK-12 2、CHECK-3 1、REQP-165/181 各 1/3 |
| Methodology DRC | 43 项 Warning：TIMING-9 ×1、TIMING-10 ×1、TIMING-18 ×34、TIMING-24 ×6、ULMTCS-2 ×1 |
| 功耗 | 2.067 W（dynamic 1.910 + static 0.157），junction 48.8 °C，Confidence Low |

首轮实现曾出现 WNS −0.141ns，14 条违例全在 pl_remap_accel 内部、源于 HLS 高扇出选择网络（sel_tmp7_reg_4011_reg → reg_1161/1153）。改用 PLACE/PHYS_OPT/ROUTE Explore 后收敛到 +0.150ns。post-route phys_opt 在本机内存下会 bad allocation 失败，已显式关闭（STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED=false），关闭后时序仍达标。

## 交付产物

| 文件 | 大小 | SHA256 前缀 |
|---|---:|---|
| artifacts/pl_rectify/led_test_wrapper.bit | 4,045,676 | 99019848356204d6 |
| artifacts/pl_rectify/led_test_wrapper.hwh | 824,126 | a7204550f68b8231 |
| artifacts/pl_rectify/led_test_wrapper.xsa | 1,289,097 | 005395a7b745facb |
| sd_card_latest/BOOT.BIN | 5,216,720 | b4408a9212234bd4 |
| sd_card_latest/image.ub | 41,990,516 | a477b366f8296291 |

交叉校验结论：XSA 内 bit/HWH 哈希与 artifacts 一致；新 bit 载荷（word-swap 后）确实出现在 BOOT.BIN 偏移 104,304；image.ub 的 ramdisk 内 5,031 条目无重复，新版应用 10 个 .py、3 份 LUT/manifest、新 bit/HWH 与源文件哈希逐一相符；打包可复现（重复打包得到同一 SHA256）。

## 离线验证（本轮重跑）

| 检查 | 结果 |
|---|---|
| 全部 Python unittest | **58/58 通过，0 跳过，14.192 秒** |
| 主机 C++ 核数值比对 | 实际用 Xilinx MinGW g++ 9.3.0 编译，step8/16 共 16 组 800×480 全帧与独立参考逐字节/CRC 比对，含边界、无效节点、cache 重置、7 种非法 step |
| 静态预检 | BUILD_PL_RECTIFY.ps1 输出 PASS、ACTIVE_COPY_LOCAL_SOURCES=126、exit 0 |

## 已知边界

- 随包 LUT 为 calibration_valid=false 的合成参数（170°→100°，40mm 基线假设），PL 模式必须显式 --allow-synthetic-lut；图像质量未验收。
- 快照仍是“停两路 VDMA → 复制 → 恢复并等 3 次 writer 轮转”的保守策略，吞吐受限；≥10 pair/s 未在板上实测。
- 两 OV5640 自由曝光，pair_id 不是共同曝光时间戳；未实现视差匹配、深度图或测距。
- 本机没有 PetaLinux，因此没有重建 rootfs，只对既有 initramfs 做原位替换；内核/DTB 未改。
