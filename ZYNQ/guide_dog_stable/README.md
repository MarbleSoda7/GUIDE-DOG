# guide_dog_stable

这是当前已完成板级验收的 OV5640 → Zynq PL/VDMA 三槽 DDR → PL owner/slot scheduler → AXI DMA → UDP/RGMII → RK3568 接收版本。

## 已验证版本

- Build ID: `20261001T084500Z_commit_restart_v1`
- Vivado: 2026.1
- Part: `xc7z020clg400-1`
- 板级长测约 610 秒：9447 个完整帧、9447 个不同图像 SHA-256、速率约 15.56 fps、FPGA fault=0。
- 本版本修复了短帧提交后 sticky fault 导致永久停止发包的问题；保留 ILA（5 probes）用于后续复核。

## 工程与工件

Vivado 工程入口：`latest_frame_project/latest_frame_project.xpr`

最终下载文件集中在 `test_artifacts/`：

- `commit_restart_v1.bit`：FPGA bitstream
- `commit_restart_v1.ltx`：与该 bit 同一次实现生成的 ILA probes
- `stage5_latest_frame_pl_owner_camera_baseline_v1.elf`：已验证 PS 程序
- `commit_restart_v1_routed.dcp`：实现后的 routed checkpoint
- `20261001T084500Z_commit_restart_v1/`：构建清单、源快照、时序/DRC/route 报告

工件 SHA-256 和构建门禁见 `test_artifacts/20261001T084500Z_commit_restart_v1/build_manifest.json`。

## 使用方法

1. 在 Vivado 2026.1 打开 `latest_frame_project/latest_frame_project.xpr`。
2. Hardware Manager 中下载 `test_artifacts/commit_restart_v1.bit`；需要 ILA 时加载同目录的 `commit_restart_v1.ltx`。
3. 通过 Vitis/XSDB 将 `test_artifacts/stage5_latest_frame_pl_owner_camera_baseline_v1.elf` 下载到 Cortex-A9 并运行。
4. RK 端使用 `../../RK/src/rk_frame_recv.cpp` 对应的接收程序；部署脚本位于 `../../RK/scripts/`。

## 重新构建注意事项

源文件、IP module-ref 和生成的 BD wrapper 必须来自本目录；修改 RTL 后必须重新生成相关 OOC/IP 产物，并重新核对 bit、ELF、LTX 的 SHA-256。不要将旧的 `.runs`、`.cache` 或临时抓包文件混入交付目录。

## 保留的历史工程

`ZYNQ/guide_dog_main` 和 `ZYNQ/guide_dog_cyclic_baseline` 保留在仓库中，作为原始主工程与调试基线；本目录是独立的稳定交付副本。
