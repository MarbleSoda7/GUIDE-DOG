# guide_linux_base 完整工程集成记录

## 工程基线
- Vivado 2024.1, 器件 xc7z020clg400-2
- 从已成功 SD-Linux 启动的 pynq_led_test 克隆, 原工程未修改
- PS: Bank0=3.3V, Bank1=1.8V, DDR MT41K256M16 RE-125, SD0 MIO40..45, UART0 MIO14..15
- FCLK_CLK0 = 100MHz (当前工程 PS FCLK)
- HP0 启用, 64bit

## Block Design 组件 (15个, validate 通过)
PS 与基础:
- processing_system7_0, axi_gpio_0, ps7_0_axi_periph, rst_ps7_0_50M

畸变矫正 (新增):
- remap_accel_0 (xilinx.com:hls:remap_accel:1.0, Vitis Vision RGB888)
- remap_hp_smc (SmartConnect, 6路SI汇流到 HP0)

摄像头采集 (移植自 guide_dog):
- ov5640_to_lcd_0 (自定义IP)
- v_vid_in_axi4s_0 5.0 (C_HAS_ASYNC_CLK=1)
- const_axis_en (xlconstant)
- axi_vdma_0 (S2MM only, 3 fstores, linebuffer 2048, burst 64)

UDP/RGMII 发送 (移植自 guide_dog):
- axi_dma_udp_0 (MM2S only, 64bit)
- axis_flow_monitor_0 (module_ref)
- axis_fifo_udp_0 (axis_data_fifo, 异步, 8byte, depth 2048)
- eth_stream_0 (module_ref eth_stream_stage3_diag)
- u_clk_phase (clk_wiz 6.0, 125MHz in/out)

## 数据通路
采集: OV5640引脚 -> ov5640_to_lcd_0 -> v_vid_in_axi4s_0 -> axi_vdma_0 -> HP0 -> DDR
矫正: DDR -> remap_accel_0 (4个 m_axi) -> DDR
发送: DDR -> axi_dma_udp_0 -> axis_flow_monitor_0 -> axis_fifo_udp_0 -> eth_stream_0 -> RGMII -> PHY

## AXI 地址
- remap_accel_0 控制: 0x40000000 (64KB)
- axi_vdma_0: M02
- ov5640_to_lcd_0: M03
- axi_dma_udp_0: M04
- eth_stream_0: M05
- HP0 DDR 窗口: 0x00000000..0x3fffffff (6个master共享)

## 时钟域
- FCLK_CLK0 100MHz: PS, VDMA, DMA, monitor, FIFO写, eth_stream AXI-Lite
- ov5640_pclk (约72MHz): ov5640_to_lcd, 视频桥输入域
- u_clk_phase 125MHz: eth_stream RGMII域, FIFO读
- 跨时钟: 视频桥内异步 (采集域->FCLK), FIFO内异步 (FCLK->125MHz)

## 约束文件 (constrs_1/new)
- led_constr.xdc
- eth_pins.xdc (RGMII引脚, 来自已验证参考)
- ov5640_camera.xdc (摄像头DVP引脚, SCCB暂未约束)

## 外部端口
rgmii_rxc(I,clk,125MHz), rgmii_rx_ctl(I), rgmii_rxd[3:0](I),
rgmii_txc(O), rgmii_tx_ctl(O), rgmii_txd[3:0](O), eth_rst_n(O),
ov5640_pclk(I), ov5640_href(I), ov5640_vsync(I), ov5640_data[7:0](I),
cam_rst_n(O), cam_pdn_0(O), cam_xclk_0(O),
cam_sccb (interface, 接 PS EMIO GPIO), led_4bits

## 源文件清理
工程内曾有 18 个文件都定义 module eth_stream (guide_dog历史调试副本),
全部加入会导致重复定义。已移除 28 个重复/无关文件, 保留最小依赖集:
- eth_rtl/eth_stream.v (真实实现)
- eth_rtl/eth_stream_stage3_diag.v (BD module_ref)
- eth_rtl/udp/{udp.v,udp_tx.v,udp_rx.v,crc32_d8.v}
- rtl/dma_udp_packetizer.v (被 eth_stream 实例化)
- rtl/axis_flow_monitor.v (BD module_ref)

## 已知风险
1. 当前工程已用 cam_xclk_wiz 从 100MHz FCLK 产生 24MHz 输出到 cam_xclk_0；生成的实现网表必须保持该连接。
2. remap_accel 单独占 206 BRAM (73%)。加上 VDMA/FIFO/eth_stream 后资源可能紧张,
   需看综合报告确认。
3. SCCB (T17/R18) 走 PS EMIO GPIO, 顶层需要 IOBUF 或改为 PS I2C, 尚未完成。
4. 综合首次失败: 残留 Vivado 进程 + 8并发读 21MB zynq.rtd 冲突
   (ERROR Device 21-988 Unexpected end of input reading rtd file)。
   已清理残留进程并改用 -jobs 2 重试。

## 待完成
- 综合结果确认 (资源/时序/DRC)
- 实现 + bitstream
- 导出 xsa -> PetaLinux 2024.1
- PYNQ 运行时脚本 (DDR地址规划, VDMA/Remap/UDP 参数下发)
- SCCB 物理连接
- 上板验证
