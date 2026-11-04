# success_four 交付记录

已生成并复制到 F:（PETALINUX，USB Mass Storage Device，约 32 GB）的三个启动文件，复制后 SHA-256 全部一致。

工程：D:/distortion_correction/success_four
WSL Linux 构建目录：/home/caitlyn/workdir/success_four
最终文件目录：D:/distortion_correction/success_four/sd_card
SD 旧文件备份：D:/distortion_correction/success_four/sd_backup_20261021_075635

## 配置

- 保留 success_third 的 dual_camera_j25.xdc，SHA-256：5AA35309CDFA9ABE0C8412456B60C7DED7BABF4650E607F9D87B2186C3B2709C。未同步旧 success 摄像头引脚。
- 两路：OV5640 → ov5640_to_lcd → v_vid_in_axi4s → axis_rgb24_to_32_node_diag → 32-bit AXI VDMA S2MM。
- 分辨率 800×480，DDR RGB888；每帧 1152000 字节，HSIZE/STRIDE 2400，VSIZE 480。
- 每路 VDMA 三帧独立循环缓冲；复位、配置帧地址/步长/行宽、启动循环、最后写 VSIZE 触发。
- 两个摄像头依次初始化、两路 VDMA 启动并检查几何参数，启动时检查摄像头2帧缓存推进。
- 自启动服务 /etc/init.d/camremap，S99camremap；日志 /var/log/camremap.log。
- 保留原双摄软件的数据发送行为：两路采集，摄像头1经 PL UDP 发送。

| 用途 | 物理地址 |
|---|---|
| 预留 DDR | 0x30000000–0x30FFFFFF（16 MiB，no-map） |
| 摄像头1三帧 | 0x30000000、0x30119400、0x30232800 |
| 摄像头2三帧 | 0x30400000、0x30519400、0x30632800 |
| 发送输出 | 0x30800000 |
| 快照 | 0x30920000 |

## 验证

- Vivado 2024.1 synthesis、implementation、bitstream、XSA 导出完成。
- 最终 WNS +0.151 ns，WHS +0.040 ns，TNS/THS 0；报告显示满足所有用户时序约束。
- 保留的摄像头 PCLK 引脚仍有专用时钟路由/布局告警（CLOCK_DEDICATED_ROUTE FALSE）；未改动已确认的引脚。
- PetaLinux 2024.1 构建成功，BOOT.BIN 重新打包。TFTP 目录不可用不影响 SD 启动交付。
- 已直接解析最终 image.ub，验证 kernel/FDT/ramdisk 三部分 SHA-256；验证内嵌设备树 DDR 预留区、全部相机 Python 源文件、来自新 XSA 的 HWH 和自启动链接。
- 已直接解析 BOOT.BIN 分区，确认包含新 XSA bitstream 和新设备树；boot.scr 数据 CRC 正确。
- F: 三文件读回 SHA-256 与交付源一致。
- 尚未进行板卡上电、双摄出图验证；编译及文件验证不代表实机测试已完成。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| BOOT.BIN | 5216720 | 17d1a27610e6cbde991906d973763e705feecff1550943d9d0c6d9eec08ab7a6 |
| image.ub | 42498964 | 4a775a1ac593e2ba422c17de4e4b7d00b1988a2b4d71e82e5c03a7e16565003f |
| boot.scr | 3473 | 3b9b939dfab95e26e69855ab23fc84e6e2ab9431ab71998aece3db7f2a8c37cd |

板上检查：启动后执行 `tail -n 80 /var/log/camremap.log`，应看到两路初始化、camera2 VDMA captured a frame 和两组三帧地址；运行时检查两路 VDMA 无错误位。
