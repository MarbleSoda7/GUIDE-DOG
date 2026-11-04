# success_five 交付记录

工程基于 `success_four` 克隆，新的 Ethernet 源已切换为 **camera2 (axi_vdma_1)**。只把 camera2 的已完成帧经原快照/AXI DMA/PL UDP 发送；camera1 仍维持独立采集和三帧 VDMA 环。

## 配置与硬件保留

- 摄像头1、摄像头2继续初始化并采集；800×480 RGB888，32-bit S2MM 输入，独立三帧 circular ring。
- camera2 Ethernet 帧源地址为 `0x30400000`、`0x30519400`、`0x30632800`；输出仍在 `0x30800000`，快照区域 `0x30920000`。UDP packetizer、网络端点和包格式均未改。
- 保留 `success_third` 的 `dual_camera_j25.xdc`。success_five 与 success_four 的约束文件 SHA-256 相同：`5AA35309CDFA9ABE0C8412456B0C7DED7BABF4650E607F9D87B2186C3B2709C`。摄像头连接器 pin 约束未改。
- 根据提供的《[野火]皓月_开发板硬件规格书V1.1.pdf》第47–48页及51–52页核对 J25 camera 和双目扩展口定义；相关 FPGA pin 对应与该双目 XDC 一致。
- XSA 沿用 success_four 已验证硬件，XSA SHA-256 `7E6637A86C4B373452F69490C260867136BCD79B8124B55C53E4E8B4EE4861DA`。
- Linux hostname/product 已更名 `success_five`。camremap 的硬件契约标为 `dual-ov5640-independent-vdma-800x480-rgb888-camera2-to-udp`。

## 构建与验证

PetaLinux 2024.1 构建成功；所有 4764 个 BitBake tasks 均完成，重新从 success_five FSBL、U-Boot、XSA bitstream 和新设备树打包 BOOT.BIN。TFTP `/tftpboot` 不可用仅影响 TFTP 拷贝，不影响 SD 文件生成。

已校验：

- `image.ub` FIT 内 kernel、FDT、ramdisk 三项 SHA-256。
- 设备树预留 DDR `0x30000000`、`0x01000000`。
- initramfs 中的 camera2 选择版 Python 模块与 success_five 源码逐文件完全一致；HWH 与 success_five XSA 完全一致；camremap 自启动服务与 `S99camremap` 链接存在；Linux hostname 为 success_five。
- BOOT.BIN 分区结构有效且包含 XSA 中的 bitstream及生成的设备树。
- boot.scr magic、CRC 和对 `image.ub` 的引用正确。

## 交付文件（尚未复制到 SD 卡）

文件位于 `D:/distortion_correction/success_five/artifacts/`。验证报告为 `artifacts/validation.json`。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `BOOT.BIN` | 5216720 | `17d1a27610e6cbde991906d973763e705feecff1550943d9d0c6d9eec08ab7a6` |
| `image.ub` | 42499176 | `59d084a2e841d1e96cb43396040173575c2a0574878c5390dadfe848f941911e` |
| `boot.scr` | 3473 | `3b9b939dfab95e26e69855ab23fc84e6e2ab9431ab71998aece3db7f2a8c37cd` |

**按用户要求，本任务没有向任何 SD 卡写入或复制文件。** 实际上板运行及 camera2 UDP 抓包验证尚未执行。
