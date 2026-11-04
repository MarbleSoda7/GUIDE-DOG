# success_five 双目接线与 Ethernet 帧源记录

## 发送源修改

`camremap` 仍配置并启动 camera1、camera2 两路 OV5640 和两路 3 帧 VDMA。用于 UDP 的 `latest_frame`、写槽/帧所有权检查、快照源地址均指定 camera2 (VDMA1)：DDR 缓冲为 `0x30400000`、`0x30519400`、`0x30632800`。输出仍复制到 `0x30800000`，保持原 800×480 RGB888 打包、UDP packetizer、目的 IP/端口和报文格式。Camera1 继续采集到自己的 ring，但不再选作以太网发送帧。软件硬件契约为 `dual-ov5640-independent-vdma-800x480-rgb888-camera2-to-udp`。

## 开发板规格书对照

依据用户提供的《[野火]皓月_开发板硬件规格书V1.1.pdf》第47–48页摄像头接口及第51–52页 J25 双目扩展口表，工程保留 `success_third` 的 J25 约束，哈希仍是 `5AA35309CDFA9ABE0C8412456B60C7DED7BABF4650E607F9D87B2186C3B2709C`。J25 表中摄像头 DVP/SCCB/同步信号的 FPGA pad 与 `dual_camera_j25.xdc` 映射相符；物理共享的复位/电源控制使用 R14、R19，对应 J25 22、37 脚。外部 XCLK 连接依照 J25 映射，不另改为单目 XDC。

本次仅修改软件发送帧的选择和验证逻辑，未改 BD、RTL、XDC、XSA 或引脚。

## 交付状态

目标产物为 `artifacts/BOOT.BIN`、`artifacts/image.ub`、`artifacts/boot.scr`。本次用户明确要求不写入 SD 卡；构建与校验期间不会复制到任何 SD 卡盘符。
