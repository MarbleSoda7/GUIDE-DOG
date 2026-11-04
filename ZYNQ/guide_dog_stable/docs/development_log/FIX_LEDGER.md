# 修复台账 (FIX LEDGER)

> **制度: 2026-09-20 起生效。每次修复必须记录在案, 无例外。**
> 记录时点: 修复验证通过后立即写入; 失败的尝试记入"尝试"栏, 不删除。
> 文件: 本文件 (eth_dbg_bit/FIX_LEDGER.md), 按时间正序追加。

## 格式规范

```markdown
### FIX-NNN [日期 时间] 一句话标题
- 问题: (现象 + 证据)
- 根因: (机制, 不是猜测)
- 修复: (改了什么文件哪里)
- 验证: (板上实测数据)
- 状态: ✅已验证 / 🔬待验证 / ❌失败回退
- 关联: STEP1_DEBUG_LOG.md 轮次 Rn / BUILD_LESSONS.md 条目
```

---

## 台账正文

### FIX-001 [2026-09-20 早] X11 viewer 通道顺序 (紫偏)
- 问题: 画面紫色, 金→青/黄→蓝/蓝→红
- 根因: viewer 做了 R↔B 交换, 但 DDR 实际已是 BGR (VDMA 小端落字节)
- 修复: rk_frame_recv.cpp 删交换改 memcpy 直拷; 6宫格法一次定案 (#1 格正确)
- 验证: 用户确认颜色正常
- 状态: ✅已验证
- 关联: 6宫格方法论 (多假设一帧成像) 已录入 BUILD_LESSONS

### FIX-002 [2026-09-20] 快照防撕裂
- 问题: 横条噪点 (读帧期间 DDR 被重写)
- 根因: PS 从 FB_Base 读 725ms 期间 S2MM 连续重写同一帧区
- 修复: main.c 收 GIMME 后 memcpy 1.15MB 到 PS 私有 snap 缓冲 (~2ms), 发送全部从 snap 取
- 验证: 冷启动后画面活且无撕裂
- 状态: ✅已验证 (依赖冷启动, 见 FIX-003)
- 备注: PARKPTR 选帧版本失败 (循环模式不跟踪), 改用固定帧0快照

### FIX-003 [2026-09-20] 画面冻结根因 = ELF-only 热重烧
- 问题: 快照版画面定格; 仪表盘显示 S2MM RUN=1 但 4 错误位 + 写指针冻结
- 根因: rst -processor 杀 CPU 但 PL(摄像头+VDMA)继续跑; 新 ELF 的
  OV5640_Init/run_vdma_frame_buffer 对运行中硬件重编程 → PL 损坏锁死
- 修复: 流程性 — 摄像头流水线测试必须断电重启 + 完整烧录 (flash_eth.tcl)
- 验证: 冷启动后一切正常 (画面活/无撕裂/无错误位)
- 状态: ✅已验证 (制度性修复, 录入 BUILD_LESSONS 铁律)

### FIX-004 [2026-09-20] 通道顺序二次翻案
- 问题: FIX-001 后用户重启程序报告颜色仍错 (金→青)
- 根因: 用户未重启进程跑了旧二进制; 我误判为修复方向错误, 错误地恢复了交换
- 修复: 恢复直拷 (第二次); 建立 MD5 对账部署流程
- 验证: 6宫格 + 新进程重启后颜色正确
- 状态: ✅已验证
- 教训: 改代码后必须确认"跑的进程是新二进制" (RK时间戳是假2024, 只信MD5)

---

## 进行中 (Step1 提速战, 详见 STEP1_DEBUG_LOG.md)

### FIX-010 [2026-09-21] Stage 3 packetizer 消除综合展开热点
- 问题: Stage 3A 专属构建在 OOC 综合 `dma_udp_packetizer` 时停滞，日志最后为 `synthesizing module 'dma_udp_packetizer'`；随后运行被 `^C^C` 中断。
- 根因: packetizer 复位时展开 1404 次 RAM 写，末包补零又以变量起点展开最多 1393 次 RAM 写，形成过大的综合写使能/选择逻辑。
- 修复: 删除两处循环；以 `packet_valid_bytes` 记录包内有效字节数，发送阶段通过 `packet_byte()` 对无效位置输出零。
- 验证: 🔬待重新综合；验收为 OOC 日志越过 packetizer elaboration、`SYNTH_PROGRESS=100%`，随后实现完成。
- 状态: 🔬待验证
- 关联: `ddr_pl_dma_udp/rtl/dma_udp_packetizer.v`、`build_stage3a.tcl`

### FIX-010 验证结果 [2026-09-22 00:02]
- 构建: ✅ `STAGE3A_IMPL_PROGRESS=100%`，`STAGE3A_BUILD_COMPLETE`。
- 专属工件: `test_artifacts/stage3a_dma_udp.bit`，MD5=`3D5C0FB51FDAA48E458C6B3ABC719169`；综合 DCP MD5=`887A788732CF99C8724C5982CE205CC1`。
- 时序对照: 新设计的同域时序全部通过（100MHz WNS=1.704ns，125MHz WNS=0.222ns）。报告中的 `ov5640_pclk ↔ clk_fpga_0` CDC 违例为既有相机观测寄存器路径：当前最差 -6.924/-7.888ns；Phase A 已知 HDMI 正常参考为 -6.903ns，属于原有、未由 Stage 3 引入的路径。
- 状态: 🔬待冷启动完整烧录与板测验证
- 关联: `phase_b_project.runs/impl_1/zynq_wrapper_timing_summary_routed.rpt`

### TEST-STAGE3A-001 [2026-09-22] 不可变DDR图样全帧端到端验证工件
- 问题: 现有 `phase_b_test.elf` 只启动4096B DMA，不能满足packetizer固定827包的接收协议，不能作为Stage 3A端到端验收。
- 根因: packetizer协议固定每帧827包、每包1394B；4096B传输只会产生3包，接收端必然不完整。
- 修复: 新增 `ddr_pl_dma_udp/sw/stage3a_pattern_main.c`、确定性ELF构建脚本、BIT+ELF完整烧录TCL和MD5门禁入口；源区固定为0x12000000，不与0x11000000三帧采集环重叠。
- 验证: 🔬待冷启动板测；UART验收标志为`STAGE3A_DMA_COMPLETE`，网络验收标志为RK端`827/827`。
- 状态: 🔬待验证
- 关联: `test_artifacts/stage3a_dma_udp.bit` MD5=3D5C0FB51FDAA48E458C6B3ABC719169

### TEST-STAGE3A-001 烧录记录 [2026-09-22]
- 身份校验: BIT MD5=`3D5C0FB51FDAA48E458C6B3ABC719169`；ELF MD5=`07FDE20DA224CBCC9348BBF728C51778`。
- 板端操作: XSDB 完整执行 `fpga -file`、PS初始化、`dow`、`con`；输出依次为`STAGE3A_BIT_PROGRAMMED`、`STAGE3A_ELF_DOWNLOADED`、`STAGE3A_CPU_RUNNING`。
- 验证边界: 尚未取得UART `STAGE3A_DMA_COMPLETE`或RK `827/827`证据，不能据此声明DMA或UDP通过。
- 状态: 🔬待验证

### FIX-011 [2026-09-22] AXI DMA 14位长度分块调度
- 问题: Stage3A UART显示请求全帧`0x00119746`后，DMA长度读回`0x00001746`，全帧命令被截断。
- 根因: 已核对AXI DMA生成IP：`C_SG_LENGTH_WIDTH=14`，单次simple-mode MM2S最大长度为16383B；`0x00119746 & 0x3fff = 0x1746`，与板上读回一致。
- 修复: `stage3a_pattern_main.c` 改为每次提交11个完整1394B payload（15334B），共76次；每个DMA命令严格在UDP包边界结束，并在下一命令前清除IOC。
- 验证: 🔬待重新完整烧录；首命令必须读回`len=00003be6`，最终UART必须出现`STAGE3A_DMA_COMPLETE chunks=76 packets=827`，RK必须出现`827/827`。
- 状态: 🔬待验证

### FIX-011 烧录记录 [2026-09-22]
- 身份校验: BIT MD5=`3D5C0FB51FDAA48E458C6B3ABC719169`；分块ELF MD5=`47A2F4EEF2C2BF5756BDF8956D347AFE`。
- 板端操作: 完整执行BIT下发、PS初始化、ELF下载和CPU启动，XSDB输出`STAGE3A_BIT_PROGRAMMED`、`STAGE3A_ELF_DOWNLOADED`、`STAGE3A_CPU_RUNNING`。
- 状态: 🔬待UART与RK验收

### TEST-STAGE3A-002 [2026-09-22] 分块DMA首块背压超时
- 板上证据: 首块参数正确：`packets_per_chunk=11`、`sa=12000000`、`len=00003BE6`；30秒后`STAGE3A_DMA_TIMEOUT chunk=0 sr=00000000`。
- 已排除: DMA长度截断（首块读回与15334B预期一致）；DMA错误状态位（`sr`错误位为0）。
- 当前边界: `sr=0`表示MM2S运行中且未完成，结合Stage2已证明的DDR/HP0/DMA+常ready sink，阻塞位于AXIS FIFO下游背压路径。
- 相关条件: Stage3A FIFO读侧、packetizer和UDP发送时钟均由`u_clk_phase/clk_out1`驱动，其输入为物理`rgmii_rxc`；需先确认RK/PHY链路已建立后再重测。
- 状态: 🔬待链路确认；未宣称根因。

### FIX-012 [2026-09-22] Stage 3A 全链路串口可观测性与 FIFO 输入复位补线
- 问题: 首块 DMA 超时仅输出 `SR=00000000`，只能证明 MM2S 正在等待，无法一次区分 FIFO 输入复位、FIFO 跨时钟、packetizer 填包或 UDP 发送完成路径。
- 根因: 已审计保存的 BD reset fanout，`axis_fifo_udp_0/s_axis_aresetn` 不在 `peripheral_aresetn` 网络中；同时既有 RTL 没有把 AXIS 各段握手和 packetizer 状态暴露给 PS。
- 修复: 新增透明 `axis_flow_monitor.v`，统计 DMA→FIFO 的接收 beat/TLAST/背压周期；packetizer 输出心跳、入站 beat、包启动、UDP 请求/完成和状态；`eth_stream.v` 将其映射至 AXI-Lite 0x18..0x38；ELF 在启动、前 1 秒每 100ms、后续每 500ms、超时处统一输出同一快照及位置分类。BD 脚本补接 FIFO `s_axis_aresetn`，并改用唯一 `eth_stream_stage3_diag` module_ref 规避 Vivado 旧端口缓存。
- 验证: `axis_flow_monitor.v`、`dma_udp_packetizer.v`、`eth_stream_stage3_diag.v` 已由 xvlog 解析；烧录前重新构建的诊断 ELF MD5=`F2E16A3151F7EF03E6D4C93C687A9FBA`。BD 更新实测日志含 `DMA_FLOW_MONITOR_CONNECTED`、三条 `PORT_dma_mon_*=OK`、`FIFO_PACKETIZER_CONNECTED`、`VALIDATE_RC=0`、`BD_SAVED`。仍须板测。
- 状态: 🔬待验证

### TEST-STAGE3A-003 [2026-09-22] 全链路诊断版完整烧录
- 工件: `stage3a_dma_udp.bit` MD5=`241D247179F9E710B526556EA7EFDB81`；`stage3a_pattern.elf` MD5=`F2E16A3151F7EF03E6D4C93C687A9FBA`。
- 板端操作: XSDB 完整返回 `STAGE3A_BIT_PROGRAMMED`、`STAGE3A_ELF_DOWNLOADED`、`STAGE3A_CPU_RUNNING`。
- 验收: 等待本次 UART 的 `STAGE3A_FLOW`/`STAGE3A_LOC` 快照与 RK 接收结果；不得以烧录成功推定数据链路成功。
- 状态: 🔬待验证

### FIX-013 [2026-09-22] 消除 Stage 3A 分帧到达、AXIS 字节反序与 RK 局部帧叠加
- 问题: RK 每个2秒接收窗口仅收到112/152/144/155/153/89个包，随后归零；画面按六层自上而下累积并带有8字节周期彩色锯齿。
- 根因: UART 已证明 DMA 76 个分块全部完成，packetizer 已完成至少826个 UDP 包，故非链路中断。软件每个分块固定等待100ms，76块使一帧至少被拉长7.6秒，跨越多个RK的2秒窗口；RK每窗重置索引位图但未清空帧缓存，导致局部轮次叠图。packetizer 的 AXIS lane 0 错取为 `TDATA[63:56]`，违反 `TKEEP[0]` 对应 `TDATA[7:0]` 的 AXI-Stream 定义。
- 修复: DMA 启动前显式等待5秒链路/时钟稳定；轮询间隔100ms改为1ms；修正8条AXIS byte lane映射；RK 每轮清空暂存帧，且仅在827包完整时更新可视帧。
- 验证: RTL与ELF待重新构建、完整烧录；验收为UART `STAGE3A_DMA_COMPLETE chunks=76 packets=827`且最后UDP完成计数827，RK单个窗口`got=827/827 miss=0`，画面不再分层或出现8字节锯齿。
- 状态: 🔬待验证

### FIX-014 [2026-09-22] 805/827 固定缺失的端到端归因仪表
- 问题: 两次RK分窗口接收包数之和均为805而非827，固定差22；现有FPGA日志最后一次采样位于第827包完成前，RK只报告最终`got`，无法区分物理未到达与协议过滤。
- 根因: 已由两次独立实测证明存在可重复的22包差，但根因位置尚未获得足够证据，不能归咎于网络或packetizer。
- 修复: ELF在DMA结束后最多等待3秒，只有`in_last=76`、`pkt_start=827`、`udp_done=827`才报告`FINAL_DRAIN_COMPLETE`，否则输出全链路最终快照。RK对raw、FPGA源MAC、IPv4/UDP、短包、错误总包数、帧号冲突、非法序号、重复序号和接受包逐项计数，并输出每轮缺失序号。
- 验证: packetizer RTL 已由 xvlog 解析；含终态 drain 计数的 ELF 已成功编译，当前 MD5=`9F20B66A4243622EDCEC6306BC2A0630`。仍待重新构建 bit、完整烧录和 RK 重新编译。单次结果将精确判定22包位于发送端未完成、线路/内核未到达，或RK解析拒绝。
- 状态: 🔬待验证

### TEST-STAGE3A-004 [2026-09-22] 最终诊断版实现构建与烧录
- 工件: `stage3a_dma_udp.bit` MD5=`BF067D893CA8CC48274A9A901DE3193F`；实际下载 ELF MD5=`E80FEBDA6861E886FD7BB8BB226AE675`。
- 板端操作: XSDB 返回 `STAGE3A_BIT_PROGRAMMED`、`STAGE3A_ELF_DOWNLOADED`、`STAGE3A_CPU_RUNNING`。
- 验收: 待 RK 接收程序重新编译和单次端到端运行。
- 状态: 🔬待验证

### FIX-015 [2026-09-22] 修复非对齐 DMA 分块的 AXIS TKEEP 丢 lane 与错误短包边界
- 问题: 完整发送后 FPGA 终态稳定为 `in_last=76`、`pkt_start=826`、`udp_done=826`，并出现 `STAGE3A_FINAL_DRAIN_TIMEOUT`；RK 因只能显示827/827完整帧而全程黑屏。
- 根因: 每次11包DMA命令的源地址依次偏移15334B，不保持8字节对齐。AXI DMA 因此在分块边界产生带稀疏TKEEP的首/尾beat；packetizer遇到第一个无效lane就清空整个beat，错误丢弃其后的有效lane。同时代码将每个DMA命令的TLAST当作可结束不满1394B的UDP包，破坏了固定包协议。
- 修复: packetizer改为逐lane跳过无效TKEEP位并保留同一beat的后续有效lane；仅累计满1394个有效payload字节才启动UDP包，DMA分块TLAST不再作为UDP包边界。
- 验证: 待RTL静态检查、实现构建、完整烧录。验收UART必须为`pkt_start=827`、`udp_done=827`、`STAGE3A_FINAL_DRAIN_COMPLETE`，之后RK才允许显示测试图样。
- 状态: 🔬待验证

### TEST-STAGE3A-005 [2026-09-22] packetizer 修复版构建
- 工件: `stage3a_dma_udp.bit` MD5=`39E6170084E14894F45DE84F5AC11735`；构建日志返回 `STAGE3A_BUILD_COMPLETE`。
- 验收: 待完整 BIT+ELF 烧录；目标为 `pkt_start=827`、`udp_done=827`、`STAGE3A_FINAL_DRAIN_COMPLETE`。
- 状态: 🔬待验证

### FIX-016 [2026-09-22] 去除分块 DMA 测试的 UART 人为节流
- 问题: 千兆全双工已由 RK `ethtool` 确认，但827包测试从首块到末块约4秒，RK的2秒接收窗口被切成多个统计帧。
- 根因: AXI DMA 14位长度要求76条simple-mode命令；旧ELF在每条命令开始、轮询和完成处同步输出UART文本。115200波特率的数百行日志占用秒级时间，PS无法及时下发下一条DMA命令，PL在命令间出现空闲间隙。
- 修复: 增加性能模式；发送期间仅保留首块启动、错误、超时和最终全链路快照，轮询周期从1ms降为10us，成功分块不再输出UART文本。
- 验证: 待重新编译ELF并完整烧录。验收为RK单个2秒窗口收完本次发送的全部FPGA实际生成包；`pkt_start/udp_done`仍作为827包正确性的独立验收项。
- 状态: 🔬待验证

### TEST-STAGE3A-006 [2026-09-22] 性能版 ELF 完整烧录
- 工件: 复用 packetizer 修复BIT MD5=`39E6170084E14894F45DE84F5AC11735`；烧录前实际重建ELF MD5=`58DBF807B0D62A662CF24933A96A292A`。
- 板端操作: XSDB 返回 `STAGE3A_BIT_PROGRAMMED`、`STAGE3A_ELF_DOWNLOADED`、`STAGE3A_CPU_RUNNING`。
- 验收: 观察RK单个2秒窗口内收到的包总数，以及UART最终`pkt_start/udp_done`。性能改善不替代827包完整性验收。
- 状态: 🔬待验证

### TRY-008 [进行中] 双bank乒乓 — 8B洞之谜
- 问题: 线上偏移恒 +2字, R5/R6/R8 三种写端实现均不变
- 嫌疑: AXI have_addr/have_data 捕获链吞掉 RAM_WA 后的前2次 wr_fire
- 探针: 最小单字探针 ELF 已写入源码, 待编译烧录
- 状态: 🔬待验证

### FIX-005 [2026-09-20] 恢复 eth_stream CDC 时序约束
- 问题: 真构建后 GIMME 不响应; BIN3 STATUS=0; R0 最小接收链 CAFE 回包正常
- 根因证据: post-route timing.rpt 出现 async_default TNS=-744.655ns, 125MHz eth 域与100MHz PS域 CDC 未豁免; 2FF 同步器被按同步路径优化/布局
- 修复: eth_pins.xdc 增加 clk_fpga_0 <-> clk_out1_zynq_u_clk_phase_0_1 false_path, 双时钟BRAM跨域约束
- 验证状态: 🔬待构建验证; 目标是 async_default/CDC 违例归零并恢复 GIMME
- 关联: GIMME_DEBUG_LOG.md, BUILD_LESSONS.md

### FIX-006 [2026-09-20] 消除 eth_stream 多驱动寄存器
- 问题: 真综合出现 Synth 8-6859/8-6858; have_addr、have_data、frame_req_ps、tx_start_ps 同时被寄存器逻辑和常量/GND驱动
- 根因证据: 构建日志明确报告 multi-driven net，并注明 constant driver preserved / other driver ignored
- 修复: AXI 捕获与清零合并为一个 always；frame_req_ps 和 tx_start_ps 的所有权分别收归各自 CDC always
- 验证状态: 🔬待重新综合; 必须确认 multi-driven critical warning=0，再继续烧录
- 关联: GIMME_DEBUG_LOG.md

### FIX-007 [2026-09-20] 消除残留 tx_start_ps 双驱动
- 问题: FIX-006 构建已通过综合，但 opt_design DRC 失败: MDRV-1，tx_start_ps_reg/Q 与 tx_start_ps_reg__0/Q 双驱动
- 根因证据: 构建日志明确指出 eth_stream.v 写译码块与 TX-start CDC 块同时赋值 tx_start_ps
- 修复: 删除写译码块对 tx_start_ps 的赋值，TX-start CDC always 独占该寄存器；同时前移 wr_fire 声明消除前向引用警告
- 验证状态: 🔬待重新构建，目标是 MDRV-1=0

### FIX-007 验证结果 [2026-09-20 16:16]
- 构建结果: ✅ 完成，synthesis 0 errors / 0 critical warnings；opt/place/route/bitstream 全部完成；BIT=4,045,767 bytes，MD5=380E46933977AE8C452DDF42CBF8245A
- 多驱动: ✅ 日志中不再出现 MDRV-1；最终综合 critical warnings=0
- 时序: timing.rpt 的 async_default 汇总为 WNS=4.045ns、TNS=0、0 failing endpoints
- 注意: eth_pins.xdc 中仍有 clock override / no clocks matched 警告；CDC约束的实际覆盖范围尚未完全证明，不能据此宣称时序问题彻底解决
- 板上状态: 🔬尚未烧录验证

### FIX-008 [2026-09-20] 恢复真综合下的纯v5视频协议基线
- 前提证据: FIX-007后 RK 已抓到连续 1404B 回包，LED 1010/1011 表明 GIMME→PS→TX 链路恢复
- 问题: 当前 ELF 仍为 DIAG=1 且按双bank地址写；当前 RTL 是纯v5单bank，因此线上协议头为零、出现重复诊断包，不能显示图像
- 修复: DIAG=0；BRAM固定地址0；恢复 fill_pb 正常 fid/total/idx；每包等待 tx_busy 置位再等待清零，避免覆写单bank
- 验证状态: 🔬待构建、冷启动完整烧录及 RK 827/827 画面测试

### FIX-009 [2026-09-20] 修复 DMA 帧缓存读取与 HDMI 中断
- 问题: RK画面混有HDMI LED残帧并严重撕裂；HDMI中断；截图仪表盘显示S2MM错误块
- 证据: 通信版与HDMI正常版的BD/VDMA/display/camera源码及FB_Base一致；通信版独有直接memcpy(FB_Base)且没有DCache失效；错误自救会停止S2MM和MM2S
- 根因: CPU从DMA写入DDR读取时使用陈旧DCache，且固定槽0与S2MM环写竞争；错误自救主动停止HDMI MM2S
- 修复: 删除dashboard/错误自救/VDMA停止与重配；按PARKPTR[28:24]取S2MM当前写槽，复制(write_slot+2)%3的安全完成帧；复制前失效源帧DCache
- 验证状态: 🔬待编译、冷启动完整烧录，先验收HDMI连续输出和RK无旧残影/帧内撕裂

### FIX-009 板上结果 [2026-09-20]
- 结果: ❌ 不能验收；完整烧录后、RK 尚未启动前 HDMI 已出现大面积白屏/错位。
- 排除: 因 RK/GIMME 后的快照代码尚未执行，DCache invalidate、安全帧槽选择、PS 发送循环均不是该 HDMI 启动即异常的触发因素。
- 新证据: 当前通信 BIT post-route 的最差时序路径仍全部落在 ov5640_to_lcd 的 ov5640_pclk→AXI 观测寄存器跨域路径；已知 HDMI LED BIT D256149A 在相同板卡上恢复正常，证明硬件链路正常。
- 当前结论: 问题位于通信 BIT 的实现/约束/时钟或 OOC 组合，而非运行期 DDR snapshot；停止在该 BIT 上继续修改运行期内存代码。
- 后续: 必须比较/恢复已知 HDMI LED BIT 的实现约束与通信 BIT 的实现约束，再重新生成通信设计；不在当前异常 BIT 上盲调。

### TEST-010 [2026-09-20] 通信 BIT × HDMI 正常 ELF 交叉判别
- 目的: 一次完整烧录分离通信 BIT 实现问题与通信 ELF 启动/VDMA/显示问题
- 固定: 通信 BIT=380E46933977AE8C452DDF42CBF8245A；不运行RK/GIMME/快照逻辑
- 替换: ELF=17558663EA5A2838E4B8ED4199D7C70F（HDMI LED 已实测正常）
- 判定: HDMI正常→通信BIT无罪、通信ELF有罪；HDMI异常→通信BIT/实现/约束有罪
- 状态: 🔬脚本已创建，待断电重启后执行

### TEST-011 [2026-09-20] 通信BD/RGMII保留、eth_stream静默空壳二分
- 前提: TEST-010 证明通信BIT + HDMI正常ELF仍花屏，根因在通信BIT而非通信ELF/RK/快照
- 固定: 通信BD、u_clk_phase、RGMII引脚及 eth_pins.xdc 保持不变；使用 HDMI正常ELF
- 变量: eth_stream替换为端口兼容静默空壳，移除UDP、BRAM、CDC、RGMII逻辑及AXI业务逻辑
- 判定: HDMI恢复→eth_stream RTL有罪；HDMI仍异常→RGMII时钟/引脚/约束集成有罪
- 状态: 🔬待构建

### TEST-011 结果 [2026-09-20]
- 板上结果: ✅ HDMI 恢复正常（通信BD/RGMII引脚/u_clk_phase/eth_pins.xdc + HDMI正常ELF + eth_stream静默空壳）
- 结论: 通信ELF、RK/快照、通信BD外部引脚、u_clk_phase单独存在及 eth_pins.xdc 单独存在均排除；根因收敛到 eth_stream 业务 RTL 实际综合/切换行为。
- 下一判别: 保留静默AXI/UDP移除，仅恢复 gmii_to_rgmii 原语链，用固定静默GMII数据；以此区分RGMII原语/时钟逻辑与UDP/BRAM/CDC/AXI逻辑。

### TEST-012 [2026-09-20] 仅RGMII IDDR/ODDR原语链二分
- 固定: TEST-011的通信BD/RGMII引脚/u_clk_phase/XDC/HDMI正常ELF
- 变量: 从静默空壳恢复 gmii_to_rgmii；TX恒0，不接UDP；无BRAM/CDC/AXI业务
- 判定: HDMI异常→RGMII原语时钟链有罪；HDMI正常→根因在UDP/BRAM/CDC/AXI业务侧
- 状态: 🔬待构建

### TEST-013 [2026-09-20] 单BIT RGMII三模式自动诊断
- 目的: 单次45秒观察同时区分 RX-IDDR、TXC=125MHz、TX-ODDR 三种根因
- 模式: 0-15秒 RX-IDDR only/TX静态；15-30秒 RX+TXC only；30-45秒 RX+TXC+ODDR；循环
- 固定: 通信BD/RGMII引脚/XDC、HDMI正常ELF；无UDP/BRAM/CDC/通信软件
- 判定: mode0异常=RX-IDDR；仅mode1/2异常=TXC；仅mode2异常=ODDR
- 状态: 🔬待构建

### TEST-012 重做 [2026-09-20]
- 原TEST-012作废：资源/MD5身份链不充分，禁止据其板上结果定论
- 重做保障：从 eth_stream.test012_rgmiionly.v 恢复（其通过gmii_to_rgmii子模块引入IDDR/ODDR）；专属脚本 build_test012.tcl；输出固定为 test_artifacts/test012_rgmiionly.bit 且复制post_synth.dcp
- 烧录前必须验证：专属DCP存在 5×IDDR 与 5×ODDR，专属BIT MD5已记录
- 状态: 🔬待构建

### TEST-012 REDO-2 [2026-09-20] 合法ODDR直连版本
- 前一重做失败：ODDR后存在模式LUT，DRC REQP-1884拒绝实现，作废
- 本版: 无mode计数器/无mux；5×IDDR和5×ODDR；每个ODDR Q直接驱动顶层RGMII输出；TX数据恒0
- 专属工件: test012_redo_rgmiionly.bit / post_synth.dcp
- 烧录前验收: post_synth内 5 IDDR、5 ODDR，且无 ODDR_has_invalid_load；专属MD5记录
- 状态: 🔬待elaboration

### TEST-012 REDO-2 构建验证 [2026-09-20]
- 专属BIT: test012_redo_rgmiionly.bit，MD5=DB1CD787B6F816528B6AEAFD746F2272
- 专属post_synth DCP: MD5=D7CCF4A842B26E478FBE2D9A6558695C
- DCP核验: eth_stream内恰好5×IDDR（RX_CTL+4 data）和5×ODDR（TX_CTL+4 data）；另有HDMI自身4×ODDR，不计入测试
- 实现: 完成，无 ODDR_has_invalid_load；允许烧录

### TEST-014 [2026-09-20] PHY释放后的真实RGMII时钟单变量测试
- 基线: TEST-012 REDO-2（5×IDDR+5×ODDR）HDMI正常，但PHY被持续复位，RGMII时钟不一定活动
- 唯一变量: eth_rst_n由100MHz计数器在约670ms后释放；UDP/BRAM/CDC/业务AXI仍全部移除
- 判定: HDMI异常→真实PHY/RGMII活动时钟链根因；HDMI正常→继续查UDP/BRAM/CDC/AXI业务
- 专属工件: test014_phyactive_rgmiionly.bit
- 状态: 🔬待elaboration

### TEST-014 构建验证 [2026-09-20]
- 专属BIT: test014_phyactive_rgmiionly.bit MD5=D3CB09CE8BE31F762E62B36237951148
- 专属DCP: MD5=6B68B2041F2BF163B90E87B28E46CEB3
- DCP: 5×IDDR、eth_stream内5×ODDR（总ODDR=9含HDMI自身4个）、PHY计数器FF=34
- 实现完成，无ODDR非法负载；允许烧录

### TEST-014 板上结果 [2026-09-20]
- 结果: ✅ HDMI 正常（PHY 已在约670ms后释放）
- 结论: PHY启动、真实RGMII RXC活动、5×RX IDDR、5×TX ODDR、TXC连续时钟及TX静态输出均排除为HDMI异常根因
- 下一步: 单变量引入 UDP 协议状态机，不引入AXI业务/BRAM/跨域逻辑

### TEST-015 [2026-09-20] UDP状态机单变量测试
- 基线: TEST-014真实PHY/RGMII活动时 HDMI正常
- 唯一新增: 完整udp RX/TX状态机，真实RGMII接收接入
- 固定禁止: tx_start_en=0，故不产生UDP发送；无BRAM/AXI业务/PS↔ETH CDC
- 判定: HDMI异常→UDP状态机根因；HDMI正常→继续引入BRAM或AXI/CDC
- 专属工件: test015_udp_rxonly.bit
- 状态: 🔬待elaboration

### TEST-016 [2026-09-20] 双时钟BRAM单变量测试
- 基线: TEST-015 UDP状态机 + RGMII/PHY HDMI正常
- 唯一新增: eth_stream 1K×32 RAMB真双端口，100MHz端持续写递增字，真实RGMII时钟端持续读递增地址
- 排除: 无AXI业务寄存器、无PS↔ETH握手CDC、无UDP tx_start/发送
- 判定: HDMI异常→双时钟BRAM实现/时钟域根因；HDMI正常→继续引入AXI业务/CDC
- 专属工件: test016_dualclock_bram.bit
- 状态: 🔬待elaboration

### TEST-016 REDO [2026-09-20] 保留双时钟RAMB测试
- 原TEST-016作废：后综合DCP未找到可识别test_bram，测试逻辑可能被优化
- 修复: RAM及地址/数据/校验寄存器均KEEP+DONT_TOUCH；ETH读数据滚动XOR校验；校验值接至AXI只读输出以形成不可消除观察路径
- 验收: 专属DCP须查询到eth_stream下RAMB36E1及test_rd_checksum寄存器
- 状态: 🔬待elaboration

### TEST-016 FINAL 板上结果 [2026-09-20]
- 工件: BIT=16188EE7E8100FB3617E0130DEE30C2E；DCP已验证 U_TEST_RAM=RAMB18E1
- 板上: HDMI 非完全正常，偶尔发生画面撕裂/跳帧
- 有效结论: 在TEST-015正常基线中，仅增加“100MHz写 / 真实RGMII时钟读”的活动真双端口RAMB18E1，即足以诱发HDMI不稳定；双时钟RAMB活动是当前首个可复现的触发条件
- 注意: 此结果尚不能区分“异时钟端口”与“同地址异步读写碰撞”或“RGMII时钟作为BRAM时钟的布线/约束”三个机制；不得直接把所有BRAM或内存本身定罪
- 下一诊断: TEST-017保持同一RAMB与同等读写活动，但Port B改用s_axi_aclk（单时钟），唯一去除异时钟因素

### TEST-017 [2026-09-20] 单时钟 RAMB18E1 对照
- 基线: TEST-016 FINAL 双时钟RAMB18E1诱发偶发HDMI撕裂/跳帧
- 唯一变量: 保持同一显式RAMB、相同连续写读/同地址模式，但Port B时钟由真实RGMII改为100MHz s_axi_aclk
- 判定: HDMI正常→异时钟/真实RGMII BRAM时钟是触发项；HDMI异常→地址碰撞或BRAM端口活动项
- 专属工件: test017_singleclock_ramb18.bit
- 状态: 🔬待elaboration

### TEST-017 板上结果 [2026-09-20]
- 工件: BIT=6D59632AA44050BEDF9BA614B0FFE6C5；DCP验证 U_TEST_RAM=RAMB18E1
- 首次烧录后HDMI灭屏；使用相同BIT/ELF完整重烧后HDMI恢复正常。首次现象作为烧录/启动异常记录，不用于RAM因果判断。
- 稳态观察: HDMI 正常。
- 对比: TEST-016 FINAL（跨时钟、读写地址同递增）存在偶发撕裂/跳帧；TEST-017（单时钟、相同地址活动）稳定正常。
- 当前有效结论: 同地址读写碰撞/BRAM端口活动本身不是充分触发条件；“跨时钟Port-B”是剩余触发项，但仍需用跨时钟且读写地址物理隔离的TEST-018区分真实异时钟与异步碰撞。

### TEST-018 [2026-09-20] 跨时钟 RAMB18E1 地址物理隔离
- 基线: TEST-016跨时钟同递增地址偶发撕裂；TEST-017单时钟同递增地址正常
- 唯一变化相对TEST-016: Port A仅写地址0–511；Port B仅读地址512–1023；Port B恢复真实RGMII时钟
- 目的: 区分“异时钟本身”与“异时钟+地址碰撞”
- 判定: HDMI异常→纯异时钟RAMB触发；HDMI正常→仅异时钟地址碰撞触发
- 专属工件: test018_async_ramb18_disjoint.bit
- 状态: 🔬待elaboration

### TEST-018 板上结果 [2026-09-20]
- 工件: BIT=65E06B9FC2173CB03F4BDA4B8C38C411；DCP=5E8F9334B238B71EF9B6FE76FA71E75C；U_TEST_RAM=RAMB18E1；A/B地址物理隔离
- 板上: 仍有偶发画面撕裂、跳帧、闪烁，现象与TEST-016跨时钟同地址版本相同
- 有效结论: 物理地址碰撞不是必要条件；活动的“100MHz写端 + RGMII时钟读端”异时钟双端口RAMB18E1组合本身足以触发HDMI不稳定
- 当前剩余分辨: 是Port-B真实RGMII时钟的BRAM端口活动，还是两个端口同时进行存储器访问的组合。下一最小测试应保持CLKBWRCLK=RGMII时钟，但令Port-B ENBWREN=0，Port-A继续100MHz写。

### TEST-019 [2026-09-20] 异时钟RAMB Port-B读禁用判别
- 基线: TEST-018已证明异时钟RAMB地址隔离后仍触发HDMI偶发不稳
- 唯一变化: 保留 U_TEST_RAM Port-B 的 CLKBWRCLK=真实RGMII时钟和地址递增，但 ENBWREN=0，不发生Port-B读取
- 判定: HDMI正常→Port-B读活动是触发项；HDMI异常→仅RGMII时钟接入RAM端口即触发
- 专属工件: test019_async_ramb_portb_disabled.bit
- 状态: 🔬待elaboration

### TEST-019 板上结果 [2026-09-20]
- 工件: BIT=40D6F98E3E5F3949B842F82F45DF7B06；Port-B ENBWREN=0
- 板上: 仍有卡帧/撕裂
- 有效结论: Port-B读使能关闭后不稳仍存在，因此读使能本身不是唯一触发项
- 限制: TEST-019仍有rgmii_rxc驱动的test_rd_addr和test_rd_checksum寄存器，不能把结果归因于RAM时钟连接本身

### TEST-020 [2026-09-20] RGMII时钟仅连接禁用RAMB Port-B
- 唯一变化相对TEST-019: 删除全部rgmii_rxc时钟的fabric寄存器/校验逻辑；Port-B仍CLKBWRCLK=RGMII、ENBWREN=0、静态地址
- 判定: HDMI正常→TEST-019问题来自RGMII域fabric逻辑；HDMI异常→RGMII时钟接RAMB Port-B本身触发
- 专属工件: test020_rgmii_clock_ramb_only.bit
- 状态: 🔬待elaboration

### TEST-020 板上结果 [2026-09-20]
- 工件: BIT=1AC8E164CC62783DB22824450F2303A5；DCP=77E47DD829E04CEFDC21AFDAC312A316；U_TEST_RAM=RAMB18E1；RGMII_FABRIC_FFS=0
- 板上: HDMI 正常（持续观察）
- 有效结论: 真实RGMII时钟仅连接到禁用RAMB Port-B本身不触发HDMI不稳。
- 结合TEST-019: 触发条件是由rgmii_rxc驱动的fabric寄存器/LUT活动（TEST-019中为test_rd_addr+test_rd_checksum），而不是RAM Port-B时钟连接/读使能本身。
- 下一判别: TEST-021去掉RAMB和UDP，只保留一个真实rgmii_rxc驱动的简单计数器；判断任意RGMII时钟域fabric活动是否足以触发，还是必须与RAMB/PS写组合。

### TEST-021 [2026-09-20] RGMII时钟域fabric计数器单变量
- 基线: TEST-020中RGMII时钟仅接RAMB且HDMI正常；TEST-019中RGMII驱动fabric寄存器且HDMI不稳
- 唯一活动逻辑: rgmii_rxc驱动32位自增计数器，DONT_TOUCH/KEEP，计数值连AXI只读输出
- 移除: RAMB、UDP、IDDR/ODDR、业务AXI、所有其它RGMII fabric
- 判定: HDMI异常→任意RGMII域fabric活动足以触发；HDMI正常→必须是RGMII fabric与RAMB/组合的触发
- 专属工件: test021_rgmii_counter_only.bit
- 状态: 🔬待elaboration

## 诊断预算与停止规则（用户批准，2026-09-20）

从当前 TEST-021 起，禁止无限二分。诊断分支预算如下：

1. **仅允许完成当前已启动的 TEST-021**；不新增其它诊断测试。
2. TEST-021 的两个结果都直接进入同一根治方向，不再继续测试：
   - HDMI 异常：RGMII RXC 驱动 fabric 逻辑本身已足够触发问题。
   - HDMI 正常：触发条件是 RGMII RXC 域 fabric 与双时钟 RAMB 的组合。
3. 两种结果的根治共同原则：RGMII RXC 域仅保留 I/O 采样；经可靠 CDC/异步 FIFO 转入独立系统时钟域；禁止 RGMII RXC 直接驱动 BRAM 或复杂 fabric 状态机。HDMI/VDMA 链保持不动。
4. 根治实现后，只允许 **一次** 专属验证构建/冷启动板测；验证工件必须满足源码→DCP→专属BIT→MD5→烧录脚本的完整身份链。
5. 若这一次根治验证失败，自动诊断停止：不再新增试验，提交完整失败证据、保持 HDMI 正常基线，并等待用户明确决定后续方向。
6. 任何“根因已锁定”声明必须同时具备：单变量、DCP特征验证、专属BIT、对照测试、板测与台账记录；否则只能称为待验证假设。

### TEST-021 板上结果 [2026-09-20]
- 工件: BIT=CA82B7BC0953AA4A49D459B5E8ADC0D0；DCP=365945ECD3C958B82E4F663CFE81E711
- DCP变量核验: RGMII计数器32FF；U_TEST_RAM=0；UDP=0
- 板上: HDMI 持续正常
- 结论: 真实RGMII RXC驱动少量独立fabric计数器本身不触发HDMI不稳。
- 综合TEST-016/017/018/019/020/021: 触发边界是“RGMII RXC域fabric活动 + 同时访问双时钟RAMB”的组合；RGMII时钟、独立fabric、RAMB时钟连接、同地址碰撞均非单独充分条件。
- 根治设计规则: 禁止RGMII RXC域逻辑直接读写/驱动双时钟RAMB；RGMII域仅完成IO采样/最小协议入口，采用异步FIFO或可靠CDC把数据/事件转入独立系统时钟域；BRAM与UDP帧缓冲状态机在该系统域运行。根据诊断预算，不再新增根因二分，下一步只做一次根治集成验证。

### ROOTFIX-001 [2026-09-20] FIFO wire hole protocol adaptation
- 根治实现检查发现: 原v5 BRAM的地址+1隐式产生4B wire hole；XPM FIFO无地址偏移，继续旧写序会使RK SKIP=4错位
- 修复: main.c FIFO写入改为显式先写4B 0，再写350个pb字；总351字=1404B，保持RK SKIP=4、协议不变
- 状态: 🔬随唯一根治集成构建验证

### ROOTFIX-002 [2026-09-21] XPM async FIFO 根治集成构建验证
- BIT: rootfix_xpm_async_fifo.bit MD5=1E13D08671D1A73B06FCD8599E6DEAA1
- ELF: build/eth_stream.elf MD5=DB187660810BEB73E5BEFAC6A39A1FA7
- DCP: xpm_fifo_async / xpm_cdc_gray / FIFO灰码同步存在；eth_stream RAW_MEM=0；UDP TX FSM存在
- 协议: PS显式写4B零洞后写350个pb字，保持RK SKIP=4
- 状态: 🔬已准备完整冷启动烧录，板测验收：HDMI稳定 + RK 827/827 + 无旧残影

### ROOTFIX-002 板上验证结果 [2026-09-21]
- 完整烧录: ROOTFIX BIT=1E13D08671D1A73B06FCD8599E6DEAA1；ELF=DB187660810BEB73E5BEFAC6A39A1FA7；脚本第二次已完整完成 BIT+ELF+RUNNING
- HDMI: ✅ 持续正常。根治设计成功消除了此前异时钟裸RAMB组合造成的HDMI撕裂/跳帧。
- RK: ❌ frame_recv连续 GIMME 后 got=0/827、miss=827、约0.5fps；说明根治架构下 UDP 端到端功能未恢复。
- 结论: 根治架构的“HDMI安全性”验证通过；“UDP功能”验证失败。根据诊断预算规则，停止新增二分/测试，不进行继续自动修补。保留所有工件，等待用户明确授权下一阶段功能集成或审查。
- 当前板上: ROOTFIX 通信BIT + ROOTFIX ELF；可用HDMI显示，RK无包。

### DMA-UDP 架构审查 [2026-09-21]
- 目标重新确认: UDP 已跑通；当前最高目标是以帧级PS命令取代PS逐字AXI-Lite搬运，实现 DDR→PL DMA→UDP 高帧率路径；HDMI不是最终产品输出，仅为集成完整性哨兵。
- 独立审查结论: HP0已启用且64-bit，现有VDMA已通过HP0访问DDR；HP0不是DMA。明日标准路径必须使用AXI DMA MM2S→AXIS异步FIFO→UDP packetizer，不能优先集成手写AXI burst reader。
- 帧所有权警告: 1,152,000B原始帧在100Mbps约需92ms，三帧30fps捕获环约66ms可能复写；DMA首证必须用不可变DDR pattern，直播帧必须先解决更多帧槽/DDR staging/第二DDR/压缩。
- 文档: ddr_pl_dma_udp/ARCHITECTURE.md 与 TOMORROW_PLAN.md。

### DMA-UDP 明日交付完成 [2026-09-21]
- 已完成: 独立项目 ddr_pl_dma_udp 的架构、HP0可行性审计、AXI DMA MM2S标准路线、BD接线清单、AXIS适配器骨架、PS帧级控制模板、静态审查和明日分阶段测试计划
- 架构更正: 不使用手写frame_dma_reader_axi作为明日主路线；使用AXI DMA MM2S→AXIS async FIFO→UDP packetizer
- 已识别阻塞条件: 3-store live capture ring在100Mbps raw帧发送下不具帧所有权安全性；第一DMA证明必须使用不可变DDR pattern
- 明日需要执行: Phase A BD加入AXI DMA MM2S及HP0路径；此阶段尚未修改BD/生成BIT

### DMA Phase A BD integration [2026-09-21]
- 实现: 新增 axi_dma_udp_0 (MM2S-only, 64-bit) 和 axis_fifo_udp_0 (async, 64-bit)
- 现有已验证 VDMA HP0路径复用: DMA M_AXI_MM2S→axi_smc/S02→M00→PS HP0
- 控制: PS GP0→periph M07→DMA S_AXI_LITE；Vivado自动分配DMA控制地址0x40400000/64KB
- 验证: 初始validation发现M07_ACLK无时钟，补M07_ACLK=FCLK和M07_ARESETN=peripheral reset后 validate_bd_design通过并保存BD
- 边界: FIFO输出尚未接UDP，Phase A仅建立PS控制/PL直读DDR基础，未声称UDP已完成

### DMA Phase A target generation result [2026-09-21]
- User-provided result: >>> PHASE_A_TARGETS_GENERATED <<<; Vivado exited normally at 10:26:40.
- Warning: IP_Flow 19-11770 says clock interface s_axi_aclk has no FREQ_HZ parameter; non-blocking generation warning, must be corrected or accepted before final build review.
- Scope achieved: BD target generation only. No Phase A implementation BIT/DCP and no UDP packetizer connection yet.
- Next authorized work: inspect generated project, correct clock metadata if required, then run the visible Phase A implementation build only after user-started/observed workflow; future builds wait for user result.

### DMA Phase A implementation build [2026-09-21]
- BD已实际保存AXI DMA MM2S→axi_smc/S02→HP0、GP0 M07→DMA Lite、DMA AXIS→异步FIFO，并通过validate_bd_design
- 当前开始专属实现构建，输出phasea_dma_hp0_axisfifo.bit/post_synth/post_route
- FIFO输出尚未接UDP；本阶段只验证PS帧级控制基础和PL直读DDR基础

### Phase A build fix: new IP synth netlists as RTL [2026-09-21]
- 现象: Synth 8-439 module zynq_axi_dma_udp_0_0 not found；新IP只有VHD/V无DCP无stub，顶层黑盒无来源
- 根因: 整包locked IP使generate_target失败，新IP从未产生OOC DCP；旧流程靠.gen既有DCP+stub通过
- 修复: build_nonproj.tcl 直接 read_verilog/read_vhdl 新IP的generated synth netlist（axis_fifo为.v，axi_dma为.vhd），与zynq_eth_stream_0_0.v同构做法

### Phase A 构建修复链 [2026-09-21]
- 问题1: Synth 8-439 module zynq_axi_dma_udp_0_0 not found — 新IP无DCP无stub
- 问题2: SMC stub 缺 S02 端口 — 旧2口DCP的stub被使用（NUM_SI=3改后未重新生成）
- 问题3: generate_target up-to-date假象 — 上午的部分生成留下残缺产物骗过状态检查，删除三个IP的gen目录后重生成成功
- 问题4: eth_stream_0 module_ref 解析失败 — 生成脚本漏了read_verilog注册RTL（build_nonproj.tcl的正确顺序）
- 最终方案: build_nonproj.tcl 将三个IP的synth包装+ipshared核心源码全部注册为RTL（与eth_stream_0_0.v同构），不再依赖不存在的DCP
- 新增read_verilog: smc synth+bd_7cab, fifo synth, axis_data_fifo core, axis_infrastructure
- 新增read_vhdl: dma synth, axi_dma core, axi_datamover, blk_mem_gen
- 所有10个源文件路径已验证存在

### Phase A 板上结果 [2026-09-21]
- 工件: BIT=phasea_dma_hp0_axisfifo.bit MD5=BAC49ADDA85E8F54F2E9EEBA1113E1D4
- DCP验证: 17 IP 全部实例化、零黑盒；axi_dma/axis_fifo/axi_smc(3口) DCP 均生成
- 板上: HDMI 画质异常，严重失真 + 间歇性闪烁
- 分析: Phase A 同时引入了多个新变量（SMC 3口扩展、AXI DMA、AXIS FIFO、M07 外设互连扩展），违反单变量原则，无法定位具体是哪个组件导致
- 与 TEST-016~021 对照: RGMII 域 fabric 活动仍为零（DMA/FIFO 全在 FCLK 域），但 HP0 互连结构和地址映射改变可能影响 VDMA 对 DDR 的访问时序
- 决定: 不继续猜测，需要单变量拆解或回退

### Phase A 时序分析结论 [2026-09-21]
- 时序报告发现两类违例:
  1. ov5640_pclk→clk_fpga_0 WNS=-6.903 TNS=-218 (32端点): ov5640_to_lcd观测寄存器CDC路径，所有历史构建均存在且HDMI正常，排除
  2. I clock (HDMI 500MHz serializer) WNS=-0.954 (7端点): hdmi_transmitter par_to_ser data_rise_s_reg→ODDR D1 路径违反 setup —— 这是直接TMDS输出数据路径
- 结论: Phase A 新增 DMA/FIFO/SMC 逻辑改变了布局和拥塞，导致 HDMI 串行器 500MHz 数据路径失守，造成严重失真
- ov5640 72MHz 时钟域 WNS=+7.709 健康；clk_fpga_0 100MHz WNS=+1.548 健康
- 修复方向: (a)对hdmi_transmitter添加pblock或布局约束保护串行器区域 (b)降低新增逻辑对布局的扰动 (c)检查axi_dynclk MMCM的BUFIO布局

### 目标重定位 [2026-09-21]
- 用户明确: HDMI 不是最终目标，可以放弃；UDP 高速畅通是唯一硬指标
- Phase A 的 HDMI 失真（I clock 串行器 -0.954ns）不再作为阻塞问题修复
- 新策略: 从 BD 中移除 HDMI 发送链（hdmi_transmitter、v_axi4s_vid_out、v_tc、axi_dynclk、VDMA MM2S读通道），保留 OV5640→VDMA S2MM→DDR 捕获链 + AXI DMA MM2S→FIFO→UDP
- 好处: (1)释放 LUT/FF/布线资源给 DMA/UDP (2)消除 500MHz 串行器时序压力 (3)消除 HDMI/网络对 HP0 带宽的部分争用 (4)简化时钟域
- VDMA 仍需保留 S2MM（写入捕获帧），仅关闭 MM2S 显示读出

### Phase B BD 修改完成 [2026-09-21]
- REMOVED: hdmi_transmitter_0, v_axi4s_vid_out_0, v_tc_0, axi_dynclk_0, tmds_*端口
- VDMA MM2S 已关闭(S2MM保留)
- VALIDATE_RC=0 BD_SAVED PROJECT_SAVED_AS_PHASE_B
- 注意: ov5640_to_lcd_0/sys_rst_n 被tie-off到0(CRITICAL WARNING)——原来自rst模块，删除链后无源，需确认S2MM链是否仍工作
- dangling nets警告(vdma M_AXIS_MM2S等)是删除后的残留，无害
- 下一步: build_phase_b_project.tcl 构建 phaseb_udp_only.bit

### Phase B 构建失败与修复 [2026-09-21]
- 失败: Opt 31-67 ov5640_to_lcd 的 sys_rst_n LUT输入悬空
- 根因: 原设计中 sys_rst_n 由 axi_dynclk_0/LOCKED_O 驱动；删除 HDMI 链(含 dynclk)后失去驱动源
- 修复: phase_b_fix_rst.tcl 将 ov5640_to_lcd_0/sys_rst_n 连接到 rst_ps7_0_100M/peripheral_aresetn
- 修复后需重跑 build_phase_b_project.tcl

### Phase B 构建成功 [2026-09-21]
- BIT: phaseb_udp_only.bit MD5=2112328097C18555AA4F39E39B086173
- 资源对比 Phase A: LUT 8841→5547(-37%) FF 13964→7760(-44%) RAMB 10.5→5.5
- HDMI 链已移除: 无 hdmi_transmitter/vid_out/v_tc/dynclk 实例
- 保留 13 IP: vdma(S2MM only) + dma_udp + fifo_udp + smc + eth_stream + 捕获链 + PS + led
- 500MHz 串行器不复存在；RGMII IDDR/ODDR 5+5 保留
- Black Boxes: 空
- sys_rst_n 已接 peripheral_aresetn

### Phase B 总线挂起隔离诊断 [2026-09-21]
- 隔离测试: PS内部(UART 0xE0000000)读取正常 → DAP健康
- eth_stream(0x40000000)读取挂起 → 所有GP0 PL外设全部挂起
- 互连已缩到5口(M00-M04在synth确认)，地址未变(VDMA 0x43000000/DMA 0x40400000)
- 头号嫌疑: ps7_0_axi_periph 内部 auto_pc (AXI3→AXI4L协议转换器)
- 证据: 打开工程时 'Could not find XCI: zynq_ps7_0_axi_periph_imp_auto_pc_0' + 'axi_protocol_converter not registered in generated file cache'
- 该组件在Phase A加入M07时或Phase B删IP时损坏/缓存陈旧
- 下一步: 在用户cmd中重置并重新生成 ps7_0_axi_periph 及其嵌套IP

### DAP误诊定论 [2026-09-21]
- 对照实验: 已知HDMI正常的led_dbg BIT上，XSDB DAP读VDMA同样挂起
- 结论: DAP→GP0寄存器读取在本板卡/工具链上从来不工作；与任何BD设计无关
- 推翻: auto_pc损坏、xbar悬空死锁、Phase B总线挂死——全部为误诊
- Phase B BIT(2112328097C18555AA4F39E39B086173)可能本来完好，当时唯一失败证据是无效的DAP方法
- 主线状态: Phase B架构(捕获+DMA+FIFO，HDMI已移除)构建成功且17 IP零黑盒，等待真正有效的验证

### Phase B 证据链收集结果 [2026-09-21]
- EVIDENCE_A: 相机I2C完全正常(0x5640, 复位后稳定)
- EVIDENCE_B: VDMA配置前无DDR写入者
- EVIDENCE_C: VDMA S2MM正常启动(run=1,无错误,等待AXIS输入), PARKPTR恒0
- EVIDENCE_D: 相机完整初始化后数据流仍死(magic未被覆盖)
- peripheral_aresetn确认高电平(VDMA AXI可访问)
- ov5640_to_lcd RTL确认: 无AXI寄存器控制, 纯硬件捕获, 相机电源信号固定
- 断点: 像素数据路径 ov5640并口→ov5640_to_lcd→v_vid_in→VDMA
- 待验证: BIT网表中sys_rst_n实际连接(check_sysrst_netlist.tcl)

### 相机硬件确认存活 + STREAM_DEAD全部解释 [2026-09-21]
- TEST-021 + led_node16.elf (09/20原组合) → HDMI有图像(色调分离但数据流活)
- 相机并口、捕获链、VDMA S2MM 全部正常
- STREAM_DEAD根因: 测试ELF缺少DisplayInitialize(dynclk)
  → TEST-021 BD: sys_rst_n←dynclk LOCKED, 不初始化则捕获复位
- 色调分离是显示质量问题,不影响数据流判断,后续排查
- Phase B待重测: sys_rst_n←peripheral_aresetn(已证明高),
  理论上无需dynclk即应捕获——立即重跑证据ELF验证

### Phase B 捕获链确认存活 [2026-09-21 v5诊断]
- 根因(来自板上实测+驱动源码): 我此前VDMA S2MM寄存器地址全错
  正确: VSIZE=0xA0 HSIZE=0xA4 STRD=0xA8 START=0xAC+ (StartAddrBase=0xA0)
  错误: 我写VSIZE到0x40, HSIZE到0x38 (属于MM2S区域/无效)
- v5(正确地址)板上结果:
  HSIZE/VSIZE读写一致 ✓
  PARKPTR=0x01000000 (S2MM推进到帧存储1!) ✓
  DDR有图像数据(08002408/30181030模式) ✓
- 结论: Phase B BIT功能完好, 捕获链正常, 之前所有"死链"都是我的寄存器地址错误
- 待观察: STAT err_internal=1, PARKPTR停在store1不循环 — 
  循环模式/错误标志需后续排查,但不影响"数据已到达DDR"的事实
- 下一阶段: DMA读DDR测试(Stage2) + 循环问题排查

### 进展总结 [2026-09-21 深夜]
今日实际达成（有板测证据的）:
1. ✅ 相机硬件确认存活（TEST-021+led ELF → HDMI有图像）
2. ✅ Phase B BIT 确认功能完好（v5正确寄存器地址 → PARKPTR推进+DDR图像数据）
3. ✅ DAP误诊链终结（已知好BIT同样挂 → DAP→GP0路径从来不通，是工具问题）
4. ✅ VDMA S2MM 正确寄存器映射确立（0xA0/0xA4/0xA8/0xAC，来自驱动源码+板测验证）
5. ✅ 我的测试ELF两大bug修复：缺SCCB_Init、寄存器地址错

今日浪费（误诊链）:
- auto_pc损坏/xbar悬空/总线挂死 → 全是DAP误诊
- STREAM_DEAD系列 → 缺dynclk init(TEST-021 BD) + 寄存器地址错(所有BD)

下一步必须带来进展的定义:
Stage 2: AXI DMA读DDR → FIFO有数据 → 这是新的从未验证过的环节
Stage 3: packetizer连入 → RK收到包 → 端到端

### Stage 2 DMA读DDR通过 [2026-09-21]
- 条件: Phase B BIT + AXIS常ready sink + RK开机/PHY链路建立
- UART证据: DMA SR从0x00000000变为0x00001002并保持
- 按DMA寄存器定义: bit1=Idle=1、bit12=IOC=1；错误位(bit4/5/6)=0
- SA=0x11000000、LEN=0x1000均读回正确
- 结论: AXI DMA MM2S已完成4096B DDR读取，Stage 2“PL从DDR读数据”通过
- 严格边界: 本次同时存在两个相对上次的变化（FIFO sink已接入、RK/PHY已开机），因此不能单独把恢复归因于某一个；但DMA/HP0/SMC/S02/时钟复位/AXIS背压组合已被实板证明可完成传输
- 下一步: Stage 3接入packetizer，替换sink；保持DMA/HP0/FIFO已验证结构不变

### Stage 3B SG continuous DMA migration [2026-09-22]
- Requested outcome: replace the 76-command AXI DMA simple-mode loop with one PS-started, PL-owned continuous transfer, following the HDMI VDMA operating model.
- Implementation: added `ddr_pl_dma_udp/stage3b_enable_sg.tcl`, which enables AXI DMA scatter-gather mode, expands length width to 23 bits, and connects `M_AXI_SG` to the previously unused `axi_smc/S00_AXI` path to PS HP0. Existing VDMA S2MM (`S01_AXI`) and DMA payload MM2S (`S02_AXI`) wiring is retained.
- Software: `sw/stage3a_pattern_main.c` now builds a 207-entry, 64-byte-aligned descriptor ring. Each descriptor transfers four 1394-byte UDP payloads (5576 bytes, source-address aligned); the final descriptor transfers three payloads. PS writes CURDESC, RUNSTOP, and TAILDESC once per frame. Packet boundaries remain solely the packetizer's 1394-byte counter; descriptor TLAST is not a UDP boundary.
- Deliverables: separate Stage 3B bit/ELF names and one-shot build/flash scripts were added so Stage 3A artifacts cannot be accidentally programmed as Stage 3B.
- Safety interlock: the legacy Stage 3A ELF build now stops with `STAGE3A_RETIRED`; it cannot pair the SG source with the old simple-mode bitstream.
- Static verification: `build_stage3b_sg_elf.ps1` completed; ELF MD5 `45EDE1487E02130299C40B01142672AC`. Existing BSP emits unrelated duplicate address-macro warnings.
- Hardware boundary: no new BIT, BD validation, or board result yet. Local Vivado batch startup failed before Tcl execution with `Common 17-356 Failed to install all user apps`; therefore SG connectivity and timing have not been claimed as verified.

### Stage 3B Vivado startup and BD validation [2026-09-22]
- Root cause isolation: the global Vivado Tcl application cache is unusable in batch mode (`Common 17-356`). There were no running Vivado/Java processes. One stale TclStore lock was moved to a reversible `.codex-stale-20260922-1245` backup, but the error persisted.
- Resolution: Stage 3B uses `XILINX_LOCAL_USER_DATA=D:\SDU\IC\HarnessProject\guide-dog\.vivado-stage3b-userdata`, isolating this build from the damaged global cache without deleting it.
- Evidence: `stage3b_enable_sg.tcl` completed and saved the BD. Vivado assigned `/axi_dma_udp_0/Data_SG` to PS HP0 DDR (`0x00000000`, 1G), reserved SmartConnect S00/S01/S02 routes, and the script wrote `VALIDATE_RC=0` and `BD_SAVED` to `ddr_pl_dma_udp/stage3b_sg_result.txt`.

### Stage 3B first implementation review [2026-09-22]
- Build evidence: Stage3B generated `stage3b_sg_udp.bit` (MD5 `244B6BF741C428079B9F1975335E9391`) and its synth DCP. The generated DMA stub confirms `C_INCLUDE_SG=1`, `C_SG_LENGTH_WIDTH=23`, and a 32-bit `M_AXI_SG`; post-route netlist includes `GEN_SCATTER_GATHER_MODE`.
- SG timing evidence: `clk_fpga_0` (DMA/HP0/SG) setup slack is +1.459ns and hold +0.050ns. The 125MHz packetizer/RGMII MMCM clock setup slack is +0.404ns and hold +0.080ns.
- Not accepted yet: total WNS=-7.909ns is entirely on `ov5640_pclk <-> clk_fpga_0` paths, which are physically asynchronous camera-to-PS CDC crossings but lacked a clock-group declaration. The implementation also has seven stale TMDS constraints after HDMI removal and a duplicate RGMII clock definition. These must be corrected and rebuilt before Stage3B is accepted.

### Stage 3B second implementation review [2026-09-22]
- The camera CDC constraint removed all `ov5640_pclk <-> clk_fpga_0` violations, but the first placement of that constraint was evaluated too early during synthesis and created two non-functional critical warnings.
- New evidence identified the remaining timing failure as `clk_fpga_0 <-> clk_out1_zynq_u_clk_phase_0`: the legacy XDC referenced a stale `_1` suffix, so its false paths did not match the generated 125MHz clock. These domains are connected only through the existing async FIFO and synchronized debug/control crossings.
- Correction prepared: `stage3b_cdc_timing.xdc` declares the camera/FCLK and FCLK/eth-MMCM clocks as asynchronous clock groups. `build_stage3b_sg.tcl` adds it with `USED_IN_SYNTHESIS=false`, `USED_IN_IMPLEMENTATION=true`, and `PROCESSING_ORDER=LATE`; invalid legacy false-path lines were removed. Final implementation rebuild remains required.

### Stage 3B final implementation and artifact acceptance [2026-09-22 13:41-13:43]
- Final implementation completed through `write_bitstream`: 178 infos, 11 warnings, **0 critical warnings**, and **0 errors**. The routed DRC has 0 errors; its 23 non-fatal findings are the pre-existing camera-PCLK non-dedicated BUFG route and async-reset RAM warnings in the existing FIFO/IP logic.
- Formal routed timing signoff (`zynq_wrapper_timing_summary_routed.rpt`) reports: WNS `+0.519ns`, TNS `0.000ns`, WHS `+0.009ns`, THS `0.000ns`, zero setup/hold failing endpoints, and `All user specified timing constraints are met.` The two formerly failing asynchronous domain pairs no longer appear as failing clock interactions.
- Accepted FPGA artifact: `test_artifacts/stage3b_sg_udp.bit`, 4,045,767 bytes, MD5 `762ADA260F6890C96B55EC79B95C6A88`.
- The generated AXI DMA stub confirms the actual built hardware has `C_INCLUDE_SG=1`, `C_SG_LENGTH_WIDTH=23`, `C_M_AXI_SG_ADDR_WIDTH=32`, and `C_M_AXI_SG_DATA_WIDTH=32`.
- Matching bare-metal ELF was rebuilt successfully after the bitstream: `test_artifacts/stage3b_sg_udp.elf`, 217,632 bytes, MD5 `2E78D159246B581C742BBDC515C01AA5`. The build has only existing BSP address-macro redefinition warnings; all buffers used by Stage3B remain within the shared valid DDR range.
- Static/build acceptance is complete. Board acceptance remains intentionally open until the user programs the pair and captures the expected UART completion markers plus RK receiving one complete 827-packet frame. No claim of on-board throughput or image correctness is made before that evidence exists.

### Stage 3B programming attempt and board-observation boundary [2026-09-22 13:44]
- The accepted Stage3B pair was actually programmed through XSDB: `STAGE3B_BIT_PROGRAMMED`, `STAGE3B_ELF_DOWNLOADED`, and `STAGE3B_CPU_RUNNING` were all returned by the hardware tool.
- Post-program observation could not be collected from this workstation: Windows exposes no serial port while the JTAG connection is present, and SSH to `cat@172.31.200.2:22` using the project-authorized key times out. This is a physical/debug-connectivity boundary, not an FPGA build or programming failure.
- Therefore on-board behavior (UART completion, RK `827/827`, image validity, and throughput) remains unverified. Do not represent Stage3B as end-to-end passed until either the FPGA UART is connected or RK SSH/network reachability is restored and the receive result is captured.

### Stage 3B RK observation [2026-09-22]
- With the RK receiver running locally on HDMI before a second Stage3B reprogramming, the user reports the receiver remains at `0/827`.
- This establishes that Stage3B is not accepted end-to-end. It does not by itself locate the fault: `frame_recv` separately reports `raw`, `fpga`, `ipv4_udp`, and protocol-rejection counters, but those diagnostic counts have not yet been captured. The next required evidence is the complete RK `[diag]` line from the same receive round; it distinguishes wire/PHY absence from parser rejection without changing hardware or source.

### Stage 3B SG first-board failure root cause and alignment fix [2026-09-22]
- RK SSH evidence after two Stage3B sends: Ethernet link is `1000Mb/s`, full duplex, and carrier up; RK transmitted 46 GIMME frames but its Ethernet RX counters remained exactly `0 packets / 0 bytes`. The failure is upstream of the RK parser.
- A read-only JTAG DDR snapshot of the descriptor ring (`sg_ring=0x00108240`) located the failure without accessing blocked PL AXI registers: BD0 status is `0x90000000` (`COMPLETE | INTERNAL_ERROR`), while BDs 103 and 206 have zero status. DMA stopped after the first descriptor and no complete UDP packet can reach the PHY.
- Root cause: BDs 0..205 have 5576-byte transfers (four 1394-byte payloads, 8-byte aligned), but the final 3-packet BD was 4182 bytes. AXI DMA documentation requires every descriptor in a multi-BD SG chain to be word aligned; the final unaligned length produces the observed internal error.
- Fix: Stage3B ELF now rounds the DMA transfer span from 1,152,838 to 1,152,840 bytes and makes only the final descriptor 4184 bytes, supplying two explicit zero pad bytes. The packetizer emits exactly 827 packets before consuming those two pad bytes, so no 828th packet is generated. The DCache flush range covers the padded span.
- Rebuilt matching ELF: `stage3b_sg_udp.elf`, MD5 `D02BA6B653273D82B322DE02D9383E39`. FPGA bitstream is unchanged. Pending board validation: fresh download of this ELF with receiver already running must yield completed descriptors and nonzero RK RX.

### Stage 3B end-to-end SG + RK UDP receiver acceptance [2026-09-22]
- Final ELF (`test_artifacts/stage3b_sg_udp.elf`) was rebuilt after both descriptor fixes; MD5 `E7EC917F30183097F8C02387DD154A62`. The signed-off Stage3B bitstream is unchanged: MD5 `762ADA260F6890C96B55EC79B95C6A88`.
- The former RK receiver used an `AF_PACKET` raw socket both to emit the required GIMME L2 control frame and to parse image traffic. This was the wrong receive interface for this application: the FPGA image traffic is valid ordinary IPv4 UDP (destination port 1234; UDP checksum zero is legal for IPv4), as independently confirmed by tcpdump.
- Root fix in `rk_frame_recv.cpp` v5: retain the bound `AF_PACKET` socket exclusively for GIMME transmission; bind a separate `AF_INET/SOCK_DGRAM` socket to `0.0.0.0:1234` and parse its UDP payload directly as `[4B hole][fid][total][idx][data]`. No FPGA RTL, bitstream, DMA configuration, packet header, or protocol workaround was added.
- RK build validation: v5 compiled on the board with `g++ -x c++ -O2 -Wall -Wextra` and was atomically switched only after that successful compilation. Previous AF_PACKET source and binary remain as `frame_recv.cpp.v4_af_packet` and `frame_recv.v4_af_packet` on RK.
- Runtime evidence: v5 is running and owns UDP `0.0.0.0:1234`. After ELF-only download, the receiver recorded `[f=62] got=827/827 miss=0 (1170 ms, 0.9 fps, gimme=3)`. Thus the application received every unique packet index and assembled one whole 800x480 RGB frame.
- The receiver subsequently reports `0/827` on later rounds because the bare-metal Stage3B ELF deliberately sends exactly one frame then remains in its final wait loop. This is expected idle behavior; the viewer retains the last complete image and never replaces it with a timed-out partial frame.
- Independent DMA evidence from the same run: BD0 status `0x800015C8`, BD103 `0x800015C8`, and BD206 `0x80001058`. Each has the COMPLETE bit and no DMA error bits. These values prove all 207 scatter-gather descriptors completed.
- RK network evidence: link remains 1000 Mb/s/full duplex; RX counter reached 4,129 packets with zero interface drops. `net.core.rmem_max=212992`, but kernel UDP statistics show zero receive-buffer errors; the complete 827-packet application frame is the decisive result.
- Acceptance boundary: the requested PS-one-start / PL-continuous-SG-DMA / UDP-to-RK full-frame transfer is now board-proven. The current payload is the intentional RGB color-bar test pattern, so camera-frame content and continuous multi-frame scheduling remain separate future work; they are not claimed by this test.

### Stage 4 OV5640 camera-to-RK preparation [2026-09-22]
- Objective: replace the validated Stage3B pattern source with one safe OV5640 frame from the existing VDMA S2MM ring, without changing the signed-off FPGA bitstream.
- Source: added `ddr_pl_dma_udp/sw/stage4_camera_main.c`; it initializes SCCB/OV5640, starts the proven VDMA S2MM configuration at `0x11000000`, samples PARKPTR at 10ms cadence, and selects the frame one slot behind the observed writer.
- Descriptor boundary: 206 BDs carry 824 complete UDP payloads, BD206 carries the final `3344B` of the `1152000B` image, and BD207 reads a separate aligned `840B` zero buffer. This prevents the DMA from reading into the adjacent VDMA slot while preserving the fixed 827-packet wire format.
- Static build: `build_stage4_camera_elf.ps1` completed with ELF MD5 `9428672BF07AD5B15ACDB7E1DE8B17D2`. Only existing BSP macro redefinition and legacy SCCB indentation warnings remain.
- First cold-boot board run proved all 208 SG BDs complete but produced no new RK RX packets. The missing condition was the proven Stage3B 5-second Ethernet/clock settle before DMA launch; Stage4 now waits 5 seconds after VDMA start and then reselects the safe frame slot.
- Flash gate prepared: `run_stage4_camera_sg_udp.ps1` verifies bit MD5 `762ADA260F6890C96B55EC79B95C6A88` and the new ELF MD5 before invoking the exact full-flash Tcl script. No camera/VDMA board claim is made until the next cold-power restart and resulting UART plus RK `827/827` evidence are captured.
- Status: 🔬待冷重启完整烧录与板测。

### Stage 4 OV5640 to RK board acceptance [2026-09-22]
- After the second cold restart, the MD5-gated full flash completed: `STAGE4_BIT_PROGRAMMED`, `STAGE4_ELF_DOWNLOADED`, `STAGE4_CPU_RUNNING`.
- RK evidence: `[f=1185] got=827/827 miss=0`; same round diagnostic was `udp=827 accepted=827 short=0 bad_total=0 bad_fid=0 bad_idx=0 dup=0`. The later `0/827` rounds are the expected idle rounds after this ELF's single-frame transmission.
- RK Ethernet evidence: RX increased from `4129` to `4957` packets with zero interface errors/drops; UDP statistics showed zero receive errors and zero receive-buffer errors.
- SG evidence: BD0=`0x800015C8`, BD206=`0x80000D10`, BD207 padding=`0x80000348`; all have COMPLETE set and no DMA error bits. BD0 source address=`0x11119400`, inside the VDMA OV5640 three-frame ring (`0x11000000`, `0x11119400`, `0x11232800`), proving this was not the prior test-pattern source.
- Root issue fixed during this test: full FPGA configuration requires the same 5-second Ethernet/clock settle used by the proven Stage3B path; starting camera SG DMA earlier completed descriptors but emitted no RK-visible packets. Stage4 now waits 5 seconds, then selects a safe completed VDMA slot.
- Status: ✅ OV5640 frame transfer accepted end-to-end for one frame. Current ELF intentionally sends one frame; continuous frame scheduling is the next separate implementation step.

### Stage 5 continuous OV5640 frame scheduling preparation [2026-09-22]
- Implementation: the PS now waits for VDMA PARKPTR to advance, selects the completed slot behind the writer, rebuilds the same 208-entry SG ring for that slot, and starts one PL-owned transfer. It validates each frame using counter deltas (`+208 TLAST`, `+827 packet starts`, `+827 UDP completions`) rather than absolute counters.
- The packetizer naturally returns to `ST_FILL` after `frame_done`; no FPGA RTL or bitstream change is required for this scheduling step.
- The previously accepted single-frame ELF was preserved as `test_artifacts/stage4_camera_sg_udp_single.elf` (MD5 `9428672BF07AD5B15ACDB7E1DE8B17D2`).
- New continuous ELF: `test_artifacts/stage5_camera_continuous_sg_udp.elf`, MD5 `6F374BE02B1972395F1730CCDB537BD7`.
- Status: 🔬待冷重启完整烧录与多帧 RK 验证。

### Stage 5 VDMA circular-mode correction [2026-09-22]
- Failure evidence: the first Stage5 ELF sent one accepted frame (`827/827`) and then blocked in `wait_next_safe_slot()`; RK had no interface errors/drops, so the stop was before the second SG launch.
- Root cause targeted: Stage5 had configured VDMA S2MM with bare register writes (`CTRL=0x3`), bypassing the project's validated `XAxiVdma` setup. The replacement calls `run_vdma_frame_buffer(... ONLY_WRITE)`, which configures circular mode, all three frame-store addresses, and starts S2MM in driver order.
- Build evidence: `build_stage5_camera_continuous_elf.ps1` now compiles and links `vdma_api.c` plus `xaxivdma.c`, `xaxivdma_channel.c`, `xaxivdma_sinit.c`, and `xaxivdma_g.c`. Build completed successfully; new ELF MD5 `AD5756D29F7BDF3545394DAE8C6262BC`.
- No RTL/BD change: the signed Stage3B bitstream remains the required bitstream; only the PS ELF changed.
- Status: 🔬待冷重启、完整烧录，并以至少连续 5 帧 `827/827` 验收。

### Stage 5 gen-lock correction [2026-09-22]
- Board evidence: after the driver-based VDMA change, RK RX increased by exactly `1656` packets (`2 x 828`) and then remained unchanged for 4 seconds, with zero interface errors/drops. This proves one VDMA rotation occurred, then S2MM stopped.
- Correction: disabled `EnableSync` for the VDMA setup because the OV5640 stream has no gen-lock source; circular S2MM remains enabled and all three frame stores are unchanged.
- Build evidence: new ELF MD5 `92ED04BF7C6AD224F0E911E0CAC9805C`; the flash wrapper MD5 gate was updated. No RTL/BD rebuild is needed.
- Status: 🔬待冷重启、完整烧录，并验证至少 5 个连续 `827/827` 帧。

### Stage 5 VDMA line-width correction [2026-09-22]
- Static root cause: `run_vdma_frame_buffer()` multiplies its hsize argument by the VDMA's configured `64-bit` width. Passing `800` therefore programmed `6400B` per S2MM line instead of the OV5640 RGB888 requirement of `2400B`; this overruns the `1152000B` frame-slot layout.
- Correction: Stage5 passes `300` (`2400B / 8B`) to the legacy helper, yielding `2400B` HSIZE/stride and the correct `1152000B` address increment for every one of the three slots.
- Build evidence: successful ELF-only build, MD5 `CE763A2DF1AC9BD527245F8DB6448BA2`; the flash wrapper MD5 gate was updated. No RTL/BD rebuild is needed.
- Status: 🔬待完整烧录，验收要求仍为至少连续 5 个 `827/827` 帧。

### Stage 5 fixed-DDR diagnostic [2026-09-22]
- Remaining evidence after the line-width correction: RK received exactly one `828`-packet frame and then no additional packets during a 10-second sample, with zero RX errors/drops.
- Added a read-only diagnostic snapshot at DDR `0x00300000`: magic, phase, frame number, PARKPTR, S2MM status, MM2S status, all three packetizer counters, source address, and poll count. It is cache-flushed by PS and read by `read_stage5_diag.tcl`; no blocked PL AXI reads are used.
- Build evidence: successful ELF-only build, MD5 `BE66C514EEB7D7D49FEC2648BC3CF36B`; the flash wrapper MD5 gate was updated.
- Status: 🔬待烧录后读取快照，以一次运行定位停止在 VDMA、SG DMA 或 UDP drain 的哪一层。

### Stage 5 diagnostic conclusion [2026-09-22]
- Snapshot at `0x00300000`: `phase=6`, `frame=0`, `park=0`, `s2mm_stat=0x0001D000`, `mm2s_stat=0x0001100A`, counters `in_last=208`, `pkt_start=828`, `udp_done=828`, source `0x11232800`. This proves the first frame and all 208 SG descriptors completed; no low-bit S2MM error is set, and the stop occurs before the next safe-slot transition.
- Corrective decision: restore `EnableSync=1` for both VDMA channels, matching the configured IP gen-lock modes and the previously observed behavior that `EnableSync=0` stops after one frame. Keep the corrected `2400B` HSIZE/stride (`hsize=300` to the legacy helper).
- Build evidence: successful diagnostic ELF build, MD5 `3BA74FFF247FA5AFB3510EBDA42C157C`; flash wrapper gate updated.

### Stage 5 one-shot node probe [2026-09-22]
- Added pre/post markers for SCCB, VDMA driver setup, initial and next PARKPTR reads, SG ring, DMA reset/setup/start/status, and packetizer completion. Each marker is flushed to DDR `0x00300000` before the potentially blocking operation, so the final `node` identifies the exact stalled boundary.
- Diagnostic ELF build passed; MD5 `9DC9ECFF5F4E50F011C1C41CF39E48F4`; flash wrapper gate updated.
- Status: 🔬待单次完整烧录并读取节点快照。

### Stage 5 root cause: unhandled AXI DMA interrupt [2026-09-22]
- One-shot node evidence: final marker `node=0x2E` (46), with `in_last=208`, `pkt_start=828`, `udp_done=828`, `s2mm_stat=0x0001D000`, `mm2s_stat=0x0001100A`. The next function's first marker (`node=0x46`, decimal 70) was never written.
- Root cause: `0x7000` was written into AXI DMA MM2S DMACR. Those are IOC/delay/error interrupt-enable bits, not a mask. No GIC interrupt handler is installed, so the first completed SG transfer raised an unhandled interrupt and trapped the CPU before the next frame scheduling call.
- Fix: keep `0x7000` only as a W1C write to DMASR, and start DMACR with `RUNSTOP` alone. Continuous completion remains polled synchronously.
- Build evidence: final ELF-only build passed, MD5 `2DC2DC226CC8DCB0C3896BA5C219A529`; flash wrapper gate updated.

### Stage 5 final interrupt-source evidence [2026-09-22]
- The AXI DMA IRQ-disable build still ended at node `0x2E`; therefore AXI DMA IRQ was not the remaining source.
- Same snapshot had VDMA status `0x0001D000`, including interrupt/error-enable status bit `0x4000`. `run_vdma_frame_buffer()` calls `XAxiVdma_IntrEnable(... XAXIVDMA_IXR_ERROR_MASK, XAXIVDMA_WRITE)` and no VDMA GIC handler exists.
- Final correction: explicitly disable `XAXIVDMA_IXR_ALL_MASK` on both VDMA channels immediately after helper setup, preserving polling-only operation.
- Build evidence: ELF-only build passed, MD5 `141B16B477F58A4E258B63CFBF93816D`; flash wrapper gate updated.

### Stage 5 final software race [2026-09-22]
- Final node snapshot after both IRQ sources were disabled: `node=0x2E`, `aux=0x00000BB8` (`polls=3000`), but counters already read `in_last=208`, `pkt_start=828`, `udp_done=828`. This proves the program entered its own `UDP_DRAIN` timeout despite the frame being complete.
- Root cause: three independent MMIO counters were compared with exact equality in separate reads; the final increment could occur between reads, producing a false timeout. The timeout path then intentionally parked the CPU forever.
- Fix: use `>=` during polling, take one final coherent sample after the loop, and only fail if that final sample is still below the required deltas.
- Build evidence: final ELF-only build passed, MD5 `1298AC765B73EF0988258157FCE5B6F8`; flash wrapper gate updated.

### Stage 5 VDMA error-code conclusion [2026-09-22]
- Final node snapshot reached `node=0x4F` (wait timeout), `frame=2`, `aux=2000`, with S2MM status `0x0001D810`.
- The low error field is `0x810 = XAXIVDMA_SR_ERR_INTERNAL_MASK (0x10) | XAXIVDMA_SR_ERR_FSZ_MORE_MASK (0x800)`. This is direct VDMA evidence: enabling gen-lock produces a frame-size-more/internal error and stops writer rotation.
- The earlier `EnableSync=0` snapshot had S2MM `0x0001D000` with low error field zero. Final validation therefore uses `EnableSync=0`, while retaining the corrected 2400B line width, IRQ disables, and counter-race fix.
- Build evidence: final validation ELF built successfully, MD5 `469EA2E42CA73E272779ED46A840FEBD`; flash wrapper gate updated.

### Stage 5 VTC backpressure release [2026-09-22]
- Final `EnableSync=0` snapshot had no VDMA low-bit errors (`0x1D000`) but writer never advanced, proving the input stream itself stopped after one frame.
- HDMI reference source shows `DisplayStart()` enables the VTC generator and explicitly releases VDMA backpressure. The network ELF had never initialized VTC/dynamic clock.
- Added `DisplayInitialize`/`DisplayStart` only for VTC/clock release; no display MM2S transfer is started by this code. Build passed, ELF MD5 `16CF09FEC58C3CA8AEAD500B3FE8DF0B`; flash gate updated.

### Stage 5 probe retained as permanent diagnostic entry [2026-09-22]
- Preserved the complete node-probe source, ELF build/flash/read scripts, fixed DDR snapshot format, node numbering, and maintenance rules in `STAGE5_PROBE.md`.
- Future diagnostics must extend this probe in place; existing node IDs and snapshot words remain stable.

### HDMI versus UDP boundary discipline [2026-09-22]
- HDMI-only blocks are not assumed in the UDP path. The current UDP BD intentionally removes VTC, dynamic clock, HDMI transmitter, and VDMA MM2S; only OV5640 -> `v_vid_in_axi4s` -> VDMA S2MM is relevant to capture.
- The observer-only probe reads the instantiated `ov5640_to_lcd` frame counters instead of attempting HDMI output initialization.

### Observer-only board result [2026-09-22]
- After a full flash of the observer ELF, snapshot node `0x4F` still showed no next VDMA writer and S2MM `0x0001D000` (no low-bit error).
- `ov5640_to_lcd` observation words 11..14 were all zero (`href=0`, `de=0`, `ce=0`, `lines=0`). This is direct evidence that the current UDP bitstream is not producing a latched complete camera frame; the single UDP frame cannot be treated as a continuously captured image.
- HDMI output modules are therefore excluded from the UDP data path. The next root-cause comparison must focus on camera reset/clock/VSYNC and `v_vid_in_axi4s` input protocol, using these counters as the acceptance gate.

### Stage 5 camera/DDR proof probe [2026-09-22]
- The previous observer read `ov5640_to_lcd` counters immediately after VDMA start, before the RTL `PIC_WAIT=10` frame qualification interval; its all-zero result was therefore insufficient to prove a dead camera path.
- Added delayed nodes `0x27/0x28` after the existing 5-second settle. They read `href/de/ce/lines` and the first word of all three S2MM frame slots.
- Each slot is seeded with `0xA5A5A5A5` before VDMA start. A changed slot head is direct proof that PL wrote DDR; unchanged sentinels mean no writer reached that slot. The result is independent of UDP counters and PS cache state.
- No HDMI/VTC/dynamic-clock or UDP logic was changed. This build is diagnostic only and must be board-tested before choosing a functional correction.

### Stage 5 camera/DDR proof probe board result [2026-09-22]
- Full flash succeeded with bit MD5 `762ADA260F6890C96B55EC79B95C6A88` and probe ELF MD5 `CA19B5476808271840CD0D2C2FA6EC6A`.
- Snapshot: final node `0x4F` (next-slot wait timeout), frame `2`, source `0x11232800`, PARKPTR `0x00000000`, S2MM `0x0001D000` (no low-bit error), packetizer counters `in_last=208`, `pkt_start=828`, `udp_done=828`.
- Delayed camera observation after 5 seconds: `href=828`, `tft_de=3076`, `tft_ce=40`, `lines=14`. The counters are not an 800x480 complete-frame signature, so they are evidence of a truncated/incorrect observation window or upstream frame qualification, not proof that the camera is dead.
- All three seeded frame heads changed from `0xA5A5A5A5`: slot0=`0x00080800`, slot1=`0xF8F8FCF8`, slot2=`0x08080408`. Multiple DDR offsets in all three slots also contain non-sentinel data. Therefore PL S2MM writes reached every frame-store slot; the camera/VDMA-to-DDR path is active.
- Cross-check against the earlier Stage4 acceptance in this ledger: the same OV5640 source and Stage3B bitstream produced RK `827/827`, all SG descriptors complete, and a non-test-pattern source address. The present failure is consequently not “camera never wrote DDR”; it remains continuous writer rotation/frame ownership, with the counter signature requiring a separate input-timing investigation if full-frame validity is still questioned.

### Stage 5 VTC/dynamic-clock hypothesis rejected [2026-09-22]
- The HDMI reference does call `DisplayInitialize`/`DisplayStart`, but the actual `stage3b_sg_udp.bit` used by the Stage5 flash script is built from `phase_b_project`, whose BD has `c_include_mm2s=0` and has removed `axi_dynclk_0`, `v_tc_0`, and `v_axi4s_vid_out_0`.
- Clean board evidence: after a full power cycle, adding those calls stopped at `node=0x18`, inside `ClkStart()` waiting for a nonexistent dynamic-clock status bit. This is a direct proof that HDMI initialization is invalid for the capture-only bit.
- Correction: removed the display/dynclk calls and their driver objects. The capture-only path remains unchanged; snapshot words 18..24 and the entry freshness guard remain.
- Status: 🔬继续定位 capture-only `v_vid_in_axi4s`/VDMA stream behavior.

### Stage 5 capture-only rollback build [2026-09-22]
- Removed the invalid HDMI/dynclk initialization from the capture-only ELF; preserved the snapshot extension and fresh-run marker.
- Build evidence: ELF-only build passed, MD5 `E31EB007B585327DE2B73B498034C4B2`.
- Status: 🔬待重新下载后读取 capture-only 节点和 VDMA 配置。

### Stage 5 probe freshness guard [2026-09-22]
- Added an entry marker: program start clears all 25 snapshot words and writes `node=0x01` before camera initialization. This prevents DDR contents surviving a processor-only reset from being mistaken for the current run.
- Build evidence: ELF-only build passed, MD5 `17FF5648C3EEF74CAEAD81D200492D6D`.
- Status: 🔬待用户断电重启后重新烧录；重启前的 `node=0x0C` 读数不作为板测证据。

### Stage 5 RGMII-layer probe extension [2026-09-22]
- RK evidence remains `tcpdump: 0 UDP packets`, while the existing PL counters reach `pkt_start=828` and `udp_done=828`; this proves only the internal UDP engine path, not the physical TX pins.
- Added `ETH_DBG_ETH` at `ETH_BASE+0x3C`. Its snapshot packs `eth_rst_n`, the GMII/RGMII clock-domain heartbeat, and GMII TX-active cycle count. This separates packetizer completion from actual GMII activity in one run.
- Extended the permanent Stage5 snapshot from 25 to 26 words (`eth_status` word 25); existing word IDs remain unchanged.
- ELF build passed, MD5 `87E0C680FA7402C315C533AF9B398C3D`.
- RTL rebuild is pending: Vivado currently exits during startup with `Common 17-356 Failed to install all user apps` before synthesis; no HDL result has been claimed from that failed invocation.
- Independent `xvlog` syntax check now passes for `eth_stream.v` and `dma_udp_packetizer.v` after moving CDC register declarations before the AXI read process; this removes the concrete `VRFC 10-3380 used before declaration` error.
- Vivado user-config ACL was inspected and the sandbox account was granted inherited Modify access on `%APPDATA%\Xilinx\Vivado`; the launcher still fails at `Common 17-356`, so the remaining startup blocker is not the project source and the bitstream has not been regenerated.
- User completed the requested Vivado build: `IMPL_PROGRESS=100%`, `PHASEB_COMPLETE`. The resulting `stage3b_sg_udp.bit` MD5 is `EA6EDECC892B14C5E6D9D3861FA55267`; the Stage5 flash wrapper hash gate was updated to this bit and ELF `87E0C680FA7402C315C533AF9B398C3D`.
- The attempted module-refresh run was captured: it stopped at `stage3a_connect_packetizer.tcl:26` because `axis_flow_monitor_0/aclk` was already connected. The script was corrected to skip already-connected nets (including RGMII clock, ports, and monitor outputs), making repeated refreshes idempotent. No new bit is valid until this corrected script reaches `BD_SAVED`.

### Stage 5 complete TX-chain probe [2026-09-23]
- Extended the permanent DDR snapshot to retain post-send `ETH_DBG_HEART`, `ETH_DBG_PKT_BEATS`, `ETH_DBG_UDP_REQ`, `ETH_DBG_STATE`, and `ETH_DBG_ETH`; the earlier version sampled these fields only before the send and was not usable for TX diagnosis.
- Final snapshot after the continuous run: `pkt_start=827`, `udp_done=827`, `udp_req=0x46DE5=290277=827*351`, `pkt_state=0`, `eth_rst_n=1`, GMII heartbeat active, GMII TX-active count `0x6606` (the expected modulo-65536 count for 827 frames of 1458 active bytes/cycles).
- RK comparison with both the continuous Stage5 ELF and the previously accepted single-frame Stage4 ELF: `eth0 rx_packets` did not change during the run and receiver remained `got=0/827`. This rules out the packetizer, UDP request handshake, and GMII TX state machine as the present root cause; the remaining boundary is the physical RGMII TXC/TX_CTL/TXD pins, PHY reset/link, or board/cable path.
- No RTL workaround was applied after this probe because the available evidence shows the internal TX chain is operating; changing packet format or packetizer would be unsupported by the measurements.
- Raw-L2 confirmation: privileged RK `tcpdump -ni eth0 -e -xx -c 10 'udp port 1234'` captured only RK-originated GIMME frames (`10.212.211.2:40000 -> 10.212.211.3:1234`, destination FPGA MAC `12:34:56:78:9a:bc`) and zero FPGA-originated frames during the same 12-second window. This proves the green LED activity is RK GIMME traffic and the failure is upstream of RK UDP delivery/socket parsing.

### One-shot UDP loop probe result [2026-09-23]
- Programmed `test_artifacts/udp_loop_probe.bit`, MD5 `33EAED5B8DE3DA6C140471E17150B14B`.
- Board LED held `0101`, which is the probe's terminal state after observing `gmii_tx_en` and `udp_tx_done` for exactly one frame.
- RK `tcpdump` captured `12:34:56:78:9a:bc -> ff:ff:ff:ff:ff:ff`, `10.212.211.3:1234 -> 10.212.211.2:1234`, UDP payload length 32.
- This directly proves the baseline RGMII TX/PHY/cable/RK receive path and fixed UDP TX implementation. The unresolved failure is therefore in the business path that supplies/starts the DMA packetizer, not in the RK receiver or basic Ethernet path.

### Main business bit aligned to probe PHY reset [2026-09-23]
- Changed only `eth_stream.v` PHY output behavior: `eth_rst_n` is now continuously `1'b1`, matching the board-proven one-shot probe; DMA, packetizer, UDP payload format, RGMII pins, and phase-clock BD connections were unchanged.
- Build completed: `STAGE3B_BUILD_COMPLETE`, DRC 0 errors, route status 0 failed nets, estimated WNS `+0.297 ns`, WHS `+0.014 ns`.
- New bit MD5: `D87EE06655D55FE18778C364C393ADAD`. Stage5 flash wrapper hash gate was updated to this exact bit and the existing ELF MD5 remains `9368F046F0368A4EAC509558F7350317`.
- Board result: the new main-engine run produced FPGA-originated packets on RK: `12:34:56:78:9a:bc -> ff:ff:ff:ff:ff:ff`, `10.212.211.3:1234 -> 10.212.211.2:1234`, UDP payload length `1404`. This is the first direct evidence that the business packetizer path now reaches the proven physical link; frame completeness still requires the receiver/diagnostic counters to be read after the run.

### RK receiver/trigger boundary retest [2026-09-23]
- Restarted `frame_recv` on RK while capturing `eth0` with tcpdump. The receiver emitted four valid GIMME frames (`a2:d8:bf:a8:6d:b5 -> 12:34:56:78:9a:bc`, `10.212.211.2:40000 -> 10.212.211.3:1234`, UDP length 1).
- During the same 8-second window, tcpdump captured zero FPGA-originated packets and the receiver reported `udp=0`; this is not a socket-format failure.
- Source evidence: current `eth_stream.v` hardwires `stage3_dma_mode = 1'b1`, so GIMME is not the TX start mechanism in this build. The packetizer requires the Zynq PS/ELF DMA stream start. Therefore the next valid test is to start `frame_recv` first, then program the bit and download/run the Stage5 ELF, so the one PS-triggered frame is captured from packet 0.
- The RK `/proc/net/snmp` check showed `InCsumErrors=0`; earlier `RcvbufErrors=1311` were stale queue-overflow counters, not checksum rejection.

### Stage5 JTAG run and board-level probe comparison [2026-09-23]
- With RK `frame_recv` already running, Stage5 JTAG programming completed with the expected hashes: bit `D87EE06655D55FE18778C364C393ADAD`, ELF `9368F046F0368A4EAC509558F7350317`.
- Synchronized RK capture during that run recorded zero FPGA-originated UDP packets.
- Read-only PS snapshot after the run: `pkt_start=827`, `udp_done=827`, `eth_status=0xCB7F6606`; the internal packetizer/GMII counters therefore show one complete 827-packet transmission attempt.
- The independent `udp_loop_probe.bit` (MD5 `33EAED5B8DE3DA6C140471E17150B14B`) was then programmed under the same RK capture. It also produced zero packets, while RK still reported `1000Mb/s`, full duplex, and link detected.
- Conclusion for this board state: the failure is below the business packetizer and below the RK UDP socket, at the physical RGMII/PHY output or its board-level reset/power state. Main Stage5 bit/ELF was restored afterward. No application or packet-format change was made.

### Clean power-cycle retest [2026-09-23]
- After a full board power-off/on, Stage5 was programmed again successfully; RK synchronized capture still saw `0` FPGA-originated UDP packets.
- Fresh PS snapshot again reported `pkt_start=827`, `udp_done=827`, and `eth_status=0x9BC36606` (TX-active low word `0x6606`). RK `eth0` remained `1000Mb/s`, full duplex, no RX errors/drops.
- This confirms the failure is repeatable across power cycles: the PS/PL internal send completes, but no Ethernet frame reaches the RK port. No further software or packetizer change is justified until the RGMII/PHY pin/reset/board path is repaired or measured directly.

### RGMII constraint and clock-path audit [2026-09-23]
- Implemented Stage5 I/O report confirms the pin map is applied exactly as intended: TXC `K18`, TX_CTL `F16`, TXD `E18/E19/G17/G18`, PHY reset `J15`; all are Bank 35 `LVCMOS33`, all TX ports are outputs, and route status has zero routing errors.
- The BD confirms raw RXC is not used directly by the main TX logic: `rgmii_rxc -> u_clk_phase/clk_in1 -> clk_out1 -> eth_stream_0/rgmii_rxc`. `clk_out1` is 125 MHz at 210 degrees, matching the phase-clock structure used by the UDP probe.
- The active XDC does not set `SLEW` or output-delay constraints for any RGMII TX port. The implemented report consequently shows `SLEW=SLOW` on TXC/TX_CTL/TXD. This is a real constraint omission, but not yet proof that it alone causes the zero-packet result.
- RTL audit adds a separate concern: `rgmii_txc` is directly assigned from `gmii_tx_clk`, while TXD/TX_CTL ODDR primitives are clocked by that same `gmii_tx_clk`. Therefore the design has no explicit TXC-to-data skew mechanism; an XDC timing declaration cannot create physical RGMII clock skew. A correction requires a dedicated phase relationship in the TX clock/data generation, followed by a board capture.

### Stage 5 AXIS read-side consumer sweep [2026-09-23]
- Clean power-on JTAG run used bit MD5 `56FED175795EA123245CB79D6EAB62BA` and ELF MD5 `DD745F61CCA7324E4C9176CCC025F27A`. The final probe node was `90`, so all three legs wrote fresh data.
- `always-ready`: DMA status `0x0001100A`, 512 64-bit AXIS beats and one TLAST. This proves the async FIFO read clock/reset and basic FIFO output path work.
- `1-in-9 ready`: the same `0x0001100A`, 512 beats and one TLAST. This proves the read-side handles sustained intentional backpressure, not merely an always-ready sink.
- Original packetizer: the same DMA status, 512 packetizer AXIS beats and 4096 byte-consumption steps. A packetizer blocked after its first 1394-byte payload would not reach 4096 steps; this also exercises its `udp_tx_done` return-to-fill path.
- Conclusion: the observed production-frame stall is not a general async FIFO read-side, `TREADY`, or packetizer single-descriptor consumption failure. The next test must use the production multi-BD geometry and completion contract; RK and RGMII are out of scope until that internal frame test reaches `pkt_start=827` and `udp_done=827`.

### Stage 5 real-camera production-frame result [2026-09-23]
- Clean power-on run used the unchanged bit MD5 `56FED175795EA123245CB79D6EAB62BA` and ELF MD5 `3BD4DD35B8B66C48231DE5A9743A18F8`. Final node `92` proves the program completed both the retained read-side sweep and one real-camera production frame.
- Input TLAST counter was `211 = 3` sweep BDs plus the production ring's `208` BDs. Packetizer counters were `pkt_start=udp_done=829 = 2` sweep packets plus `827` real image packets. UDP request count was `290979 = 829 * 351`, and byte steps were `1156936 = 4096` sweep bytes plus `1152840` real wire bytes (`827 * 1394`).
- The prior production failure was a PS completion-contract bug: SG DMA raised `IOC` while downstream backpressure prevented immediate `Idle`; treating only `Idle` as completion made a completed ring falsely time out. The production code now resets to Halted, waits reset self-clear, accepts IOC, then independently verifies TLAST, packet-start, and UDP-done deltas.
- This establishes the full real-data PS DMA -> async FIFO -> packetizer -> UDP engine path. RK background receiver output was zero but was not time-correlated to this one-shot transmission; a synchronized raw RK capture remains required before asserting a physical-link conclusion.

### Stage 5 synchronized real-frame RK capture [2026-09-23]
- Before a clean-board Stage5 launch, RK ran privileged `tcpdump -ni eth0 -e -nn -vv 'udp port 1234'` for the complete 45-second window. It captured 85 packets, all RK-originated GIMME (`a2:d8:bf:a8:6d:b5 -> 12:34:56:78:9a:bc`, payload length 1), and zero FPGA-originated packets.
- The same launch's frozen PS snapshot reached node `92` with the exact internal production totals: TLAST `211`, `pkt_start=udp_done=829`, `udp_req=290979`, and byte steps `1156936`. There were no RK kernel capture drops.
- This is synchronized end-to-end evidence: the real camera frame completes through the FPGA UDP engine, but no corresponding Ethernet frame reaches RK's NIC. The remaining fault domain is strictly the RGMII TXC/TXD/TX_CTL to PHY physical output path or PHY configuration; RK receive software and every upstream data-path stage are excluded.

### Stage 5 real-frame RGMII TXC phase sweep [2026-09-23]
- Built and programmed physical-sweep bit MD5 `699CFED77C5048B55C3C3FEF70B6CA4D` and matching Stage5 ELF MD5 `51BF30170AB025DCE5286D9DF7E9E3B1`. Implementation signoff: WNS `+0.426 ns`, WHS `+0.013 ns`, zero timing failures, zero routing errors, and bitstream DRC zero errors.
- The TX data/control ODDRs and all upstream production logic were unchanged. Only TXC was selected at `0`, `90`, `180`, then `270` degrees relative to the 125 MHz data launch clock, with the selector accepted only during GMII idle. Stage5 rereads lock and active phase before each real-camera DMA send.
- Final permanent snapshot reached node `94`. Each of the four records at words `50..69` reports lock asserted and its requested active phase, followed by exactly `208` DMA TLASTs, `827` packet starts, and `827` UDP completions. Thus each candidate sent a complete real production frame through the same DMA/packetizer/UDP engine.
- RK started privileged raw `tcpdump` before programming. Capture result: 190 RK GIMME packets, zero FPGA-source UDP packets, zero kernel drops. No candidate phase reached RK.
- Conclusion: a missing static TXC-to-data phase is rejected for the tested `0/90/180/270` degree candidates. The remaining fault domain is now PHY TX electrical/register configuration or the FPGA-to-PHY board path; camera, DDR, PS DMA, async FIFO, packetizer, UDP fields, RK socket, and these four TXC phase choices are excluded by this run.

### Stage 5 clean real-camera eight-frame acceptance [2026-09-23]
- After a clean board power-on, direct-TXC bit MD5 `D03FE682203CD5A4D27DDE949BBDA8A7` and corrected one-shot ELF MD5 `6F16E5063B66BA11D06C847ADEA48CBC` sent eight real DDR frames. The ELF disables the preliminary AXIS sweep and uses exactly 838 padding bytes, not 840, so packetizer carryover does not shift subsequent frames.
- PS final node `94` reported `in_last=1664=8*208`, `pkt_start=udp_done=6616=8*827`; the GMII TX-active low-16 count was `0x3030`, exactly `(6616*1458) mod 65536`. An ILA trigger at packet-start count 826 captured GMII activity at the first frame's tail.
- Synchronized raw RK pcap `test_artifacts/stage5_clean_20260923.pcap` has 6609 FPGA-originated packets, with zero tcpdump kernel drops. `analyze_stage5_pcap.py` reports seven complete `827/827` frames and one `820/827` frame missing indices `790..796` only. RK receiver logged complete frames and now handles repeated constant `fid=1` by treating a repeated index zero as a new frame.
- Reconstructed `test_artifacts/stage5_clean_frame7.png` is a recognizable, non-test OV5640 scene. The first captured frame had a visible horizontal tear; later frames show the scene cleanly. Frame hashes differ across later frames, proving live camera updates to the DDR source.
- This is an end-to-end functional link, but **not yet stable**. The seven missing packets are after GMII and before RK raw capture; the exact physical/drop mechanism is not proven. Do not claim 100% delivery.
- ELF-only reload on the running board hung at VDMA initialization node `0x14`; a later full bit reprogram without board power-cycle stalled after three SG BDs/12 UDP packets at node `0x2C`. Neither invalid run is evidence about PHY packet-loss rate. A clean power-on is required for the next meaningful board comparison.

### Stage 5 autonomous high-frame-rate candidate [2026-09-23]
- User priority changed to high-rate PL-autonomous transport before physical-layer fine tuning. `stage5_camera_cyclic_sg_udp.elf` (MD5 `FB99AC13F28023A8E0C64F4A8663C43A`) is compiled but **not yet board-tested**. It sets AXI DMA MM2S `DMACR.CYCLIC=1`, links the last of 208 real SG descriptors to the first, and points `TAILDESC` to a separate unreachable 64-byte-aligned sentinel BD, following Xilinx's cyclic-SG driver example. PS starts the engine once, then only monitors counters/FPS. RK pcap plus an A9-halt test must prove PL continues transmitting autonomously.
- Existing `stage5_direct_txc_slow.bit` preserves the successful clean-run bit exactly (MD5 `D03FE682203CD5A4D27DDE949BBDA8A7`); `load_stage5_cyclic.tcl` selects this bit and the cyclic ELF. No PL rebuild is needed for this transport test.
- A proposed FAST-slew-only implementation was rejected at its post-route gate: actual `rgmii_txc` remained `SLEW=SLOW`. No FAST-slew bit was produced or programmed, and the XDC experiment was reverted. No physical-layer improvement is claimed.

### Stage 5 cyclic-SG high-rate board result [2026-09-23]
- After a confirmed full power cycle, programmed the unchanged successful bit MD5 `D03FE682203CD5A4D27DDE949BBDA8A7` and cyclic ELF MD5 `FB99AC13F28023A8E0C64F4A8663C43A`. DMA live CR `0x00010013` confirms Run/Stop and Cyclic are set; SR `0x00011008` shows running without error.
- RK raw capture `test_artifacts/stage5_cyclic_20260923.pcap` contains 200,000 FPGA-originated packets. The parser measured 242 frame starts at 49.58 fps; 239 frames complete, two startup frames missed packet ranges, and the terminal frame was truncated by tcpdump's packet-count limit. tcpdump reported 444 kernel drops in this 200k-packet capture, so those missing packets cannot be attributed solely to the wire. Complete-frame image hashes changed over time, confirming live camera data rather than a fixed test pattern.
- The PS monitor stopped at diagnostic node 107 / frame 112 because it required exactly `16*208` DMA TLASTs between non-atomic report samples. At the failure snapshot `pkt_start=udp_done=92705`, already beyond 112 full frames, and the subsequent live hardware count exceeded a million: this was a false monitor predicate, not a stopped PL engine. The source now checks DONE <= START and forward TLAST progress instead. The corrected cyclic ELF rebuilt successfully (MD5 `78CB9745983E4959DAE90E05EAEEF0BD`) but has **not** yet been board-tested; the active board still runs the prior ELF.
- Explicit autonomy test stopped A9 without touching PL. `UDP_DONE` advanced from `0x0075EB7A` to `0x00777FE9` in 2.5 s, a delta of 103,535 packets (~125 frames). Simultaneous RK pcap `test_artifacts/stage5_a9_halted_20260923.pcap` captured 80,000 FPGA packets; 96 complete frames plus one count-limited terminal partial at 49.78 fps, with four tcpdump kernel drops. Thus the real-camera DMA/packetizer/UDP/RGMII path keeps transmitting without per-frame PS control.
- The RK viewer process remains active, but its own log reports roughly 20–36 displayed fps and skipped/restarted same-fid frames under the ~50 fps stream. Wire transport rate and UI presentation rate are separate; receiver optimization and residual packet loss remain follow-up work.
- Attempted the corrected-ELF clean-run check after the next user power cycle. `fpga -file` completed, but XSDB then listed only `xc7z020` and `Legacy Debug Hub`; A9 was absent and DAP reported `APB AP transaction error, DAP status 0x30000021`. A fresh `hw_server` produced the same target list. Consequently the corrected ELF was **not downloaded**, and RK's synchronized follow-up capture had zero FPGA packets. This is a JTAG/PS access blocker for that follow-up, not a regression test of the cyclic transport. Do not label the corrected ELF board-verified or claim the present board is streaming.
- Hardened `load_stage5_cyclic.tcl` to return nonzero on a missing A9 or download error; XSDB had previously printed the target-selection failure but returned process exit code zero, which could misleadingly look like a successful flash.
- FPGA-only/local-viewer trial: programmed the validated bit only, then downloaded and ran corrected cyclic ELF MD5 `78CB9745983E4959DAE90E05EAEEF0BD` without launching `frame_recv`. DMA live CR was `0x00010013` and `UDP_DONE` advanced from `0x001087BB` to `0x001A3199` in about 2 seconds, proving the pixel stream is active before the user starts the RK viewer locally. The prior RK `frame_recv` process was stopped with exact-name `pkill`; no new RK receiver was started by this trial.

### RK receive-buffer self-configuration [2026-09-23]
- Evidence before the change: RK `net.core.rmem_max=212992`; while `frame_recv` was active, `/proc/net/snmp` `RcvbufErrors` increased by `18,760` in two seconds. The viewer's single receive/reassemble/display loop therefore lost datagrams before it could form frames.
- Updated `rk_frame_recv.cpp` to request a 16 MiB per-socket receive queue with `SO_RCVBUFFORCE` (falling back to `SO_RCVBUF`) and print the actual kernel value. This does not modify RK-wide sysctls. A root test binary reported `udp receive buffer requested=16777216 actual=33554432 (forced)` and received complete frames without startup errors.
- Deployed atomically on RK after successful `g++ -x c++ -O2 -Wall -Wextra` build. Current binary MD5 `41349539A744A1AF908F37D1103FB0EC`; source MD5 `60511C6A774509CD69FB4A79A63C2BE6`. Previous binary is preserved as `/home/cat/eth_recv/frame_recv.pre_rcvforce`.
- The new binary is installed but not running; the user must start it locally on HDMI. This addresses the measured kernel receive overflow; if display remains below wire rate, the next separate bottleneck is the single-threaded receive-plus-`imshow` loop.
- RK viewer receive/display decoupling [2026-09-23]: refactored `rk_frame_recv.cpp` into a UDP receive/reassembly thread plus a GUI thread. The receiver publishes only the newest complete frame under a mutex; the GUI copies and displays the newest sequence, dropping stale frames deliberately. The receiver reports once per second instead of printing two lines per frame. A bounded RK test of the new binary measured `rx_fps=49.0`, then `50.0`, with `dropped=0`; no FPGA change was made. New binary deployed as `/home/cat/eth_recv/frame_recv` (MD5 `4CD7027601FD4BA198339AED27F38AD8`), previous receive-buffer-only binary preserved as `frame_recv.pre_threaded`. The new binary is installed but stopped for user HDMI testing.
- Content-refresh audit after the user observed smooth `49.6 fps` counters but single-digit perceptual motion: `analyze_stage5_pcap.py` on the existing 200k-packet clean cyclic capture found 239 complete network frames but only 41 distinct consecutive SHA-256 image runs in ~4.86 s; most images repeated for 7–9 network frames. This distinguishes network/display-loop fps from new camera-content fps. Source inspection confirms VDMA S2MM cycles through three frame-store addresses (`WriteCfg.EnableCircularBuf=1`, `FixedFrameStoreAddr=0`), whereas `build_sg_ring(frame_base)` fixes all cyclic MM2S descriptors to the one slot selected at startup. Thus the sender revisits one camera buffer instead of selecting the latest completed buffer each frame. Sensor-native fps and exact VDMA slot cadence are not measured yet. A read-only JTAG PARKPTR sampler was prepared but could not run because this session exposed no JTAG targets (likely cable not connected); it made no hardware changes.

### Cyclic sender three-slot content refresh fix [2026-09-23]
- Changed only the cyclic Stage5 ELF's SG-ring construction. In `STAGE5_CYCLIC_DMA`, the ring now contains `SG_BD_COUNT * FRAME_COUNT` descriptors and cycles through all three VDMA frame-store addresses in order; the PS still configures the ring once and the PL/DMA runs autonomously afterward. Non-cyclic builds retain the original single-frame ring geometry.
- Updated the cyclic monitor's TLAST progress threshold to the expanded ring size. ELF-only build passed with MD5 `27CD81A55050084642E92EA27C8657A9`. The known-good bit remains unchanged (`D03FE682203CD5A4D27DDE949BBDA8A7`).
- This removes the confirmed fixed-slot replay mechanism, but a board run is still required to check whether a slot can be read while VDMA is writing it. That possible tear is intentionally measured next; no claim of stable content yet.

### Three-slot cyclic content refresh board result [2026-09-23]
- After the user's cold reboot, programmed the unchanged bit `D03FE682203CD5A4D27DDE949BBDA8A7` and cyclic ELF `27CD81A55050084642E92EA27C8657A9`. A synchronized RK raw capture (no `frame_recv` process) recorded 23 complete image frames at `49.76 fps`; tcpdump reported 162 kernel drops during the 20,000-packet capture, so the final partial frame is capture-boundary loss.
- Consecutive content analysis found `MAX_RUN=1`: no two adjacent complete frames had the same image SHA-256. This removes the previous 7–9-frame fixed-slot replay pattern. The first complete frame reconstructed as a recognizable real OV5640 scene (`test_artifacts/stage5_slots_live_frame.png`). Several non-adjacent hashes recur, consistent with the three-slot writer cadence rather than a permanently frozen buffer.
- This test confirms the three-slot ring refreshes camera content at the wire rate. It does not yet prove every frame is tear-free when the reader catches a VDMA write; the sample image was visually coherent, but a longer capture with a dedicated tear detector is still required before claiming stable delivery.

### PL-owner node diagnostic and MM2S circular-read correction [2026-10-01]
- Build `20261001T001416Z_axis_nodes_v4` with matching SHA-256 bit `B1241EEDBE880F573ABF1D319AA9E32103C64827932EEFE44FEDA04240370A95` and detailed UART ELF first isolated the startup fault: with a 2 s wait before S2MM, status was `0x15810` (`internal=1`, `FSZ_MORE=1`). Removing that wait changed status to `0x11000` with all error bits clear. This proves the first AXIS SOF was being lost while S2MM was stopped.
- The owner diagnostic build `20261001T001416Z_owner_diag_v5` uses bit SHA-256 `56DD6BFE2020430C35716A8B31D190D02F29B0DBFF50B31624748061C2A66691`. Matching ELF `stage5_latest_frame_owner_diag_v5.elf` is SHA-256 `94960503BB18065B8285ADCDFED357F7708B88375D7A2CC1DC114EE07F9822C9`.
- Its one-run node counters were `write=33`, `commit=32`, `fsync=32`, `stream_done=32`, all fault bits clear. The actual MM2S AR monitor remained at `read_slot=0` while `latest_slot=1`; therefore dynamic-slave FSYNC restarted the same VDMA read slot and the gate correctly rejected newer committed slots. This is the precise second root cause.
- The ELF-only correction runs MM2S with `CR=0x00010003` (plain circular, sync disabled), allowing the VDMA hardware frame-store pointer to rotate through all three slots; the gate still rejects a slot unless it is the newest committed generation. Matching ELF `stage5_latest_frame_owner_diag_v5_cyclic_mm2s.elf` is SHA-256 `947D2D1602B3D40DCCAB376D69BFBB765FFD8014B5434E1B75A59491424493A5`.
- Same-bit board test after the correction showed continuous packetizer growth (`pkt_start` increased by about `64,506` packets per 5 s) and `S2MM=0x11000` with no errors. A synchronized RK capture recorded 76,092 packets, zero kernel drops, 92 frame starts, 91 complete `827/827` frames, sequential FIDs `2094..2127`, no duplicate packets, and `start_to_start_fps=15.56`. The terminal frame was truncated by capture timeout (missing indices `824..826`), not an in-flight loss.
- RK receiver log during the same run reports approximately `15.6 fps`, `accepted=13232`, `dropped=0` per one-second window. Evidence is stored under `test_artifacts/20261001T001416Z_owner_diag_v5/rk_owner_v5_live_analysis.txt` and `rk_owner_v5_receiver_tail.log`.
- End-to-end OV5640 -> AXIS -> S2MM -> three DDR slots -> PL owner/gate -> MM2S -> packetizer/RGMII -> RK is now board-verified. The measured rate is limited by the current camera timing (`HTS=0x0A0A`, `VTS=0x0708`, about 15.6 fps); 40--50 fps requires a separate sensor-timing change and acceptance run.
# v11 VSYNC stretch build provenance [2026-10-01]
- Refreshed `ov5640_to_lcd` IP revision from 10 to 11 so the generated OOC checkpoint contains the HREF-gated VSYNC stretch fix; the v11 synthesis log resolves `zynq_ov5640_to_lcd_0_0_synth_1` from the refreshed revision.
- Build `20261001T040500Z_vsync_stretch_v11` completed with synthesis and implementation at 100%, DRC errors 0, unrouted nets 0, setup slack `+0.411 ns`, hold slack `+0.023 ns`.
- Artifacts: `stage5_latest_frame_owner_v11_vsync_stretch.bit` SHA-256 `C89F8FE4CB35FF313B6CED24E0B7F4AC0E1C358505B126C63A6B93F12BF81FB6`; matching LTX SHA-256 `4304D7CD503C8759C7D6A2CDEB022FB868CCD40FE53F17E1231B9715191E4507`; matching ELF SHA-256 `977D95D67A90BBEE162CAD8248753B0DB36CFC5840D8E59C8C390F73FCE5AE9F`.
- Board acceptance is pending cold-start JTAG recovery. Read-only preflight before programming saw `xc7z020` but DAP `0x30000021` and no A9 target; no board result is claimed from that state.
- v11 programming attempt at 2026-10-01 04:25 local successfully downloaded the bit (`V11_BIT_PROGRAMMED`), but XSDB still exposed only `xc7z020` and DAP `0x30000021`; the required A9 target was absent, so the ELF was deliberately not downloaded and no UART/RK result was accepted.
- Recovery audit: restarted `hw_server`, reduced JTAG frequency from 15 MHz to 1 MHz, and issued DAP/ POR/ SRST reset attempts. DAP reset briefly exposed an APU target, but both Cortex-A9 targets remained `0xF0000021`; SRST returned to DAP `0x30000021`. This rules out the host server and JTAG speed as the immediate cause; a physical board power cycle is required before ELF download.
- Further PS initialization probe: raw JTAG chain is healthy (`arm_dap` IDCODE `4ba00477`, FPGA IDCODE `23727093`), but `ps7_init` fails at `0xF8007080` with `AHB AP transaction error, DAP status 0xF0000021`; A9 remains inaccessible. This is board PS power/reset state, not an RTL or artifact issue.

### Camera-baseline isolation before PL-owner repair [2026-10-01]
- The v11 candidate was invalid for triple-buffer attribution because it changed OV5640 PLL/HTS/VTS and added a sensor standby/restart sequence. Its board log showed `href=0`, `de=0`, `lines=0`, and all three DDR slots remained `A5A5A5A5`; this is a camera-input failure before the three-slot scheduler and was not treated as a PL-owner result.
- Restored `stage5_latest_frame_main.c` to the known-good `OV5640_Init()` timing (`HTS=0x0A0A`, `VTS=0x0708`) and removed the extra timing writes/standby restart. No PL owner RTL was changed.
- Fixed `preflight_latest_frame.tcl` to validate the actual embedded `ila_rgmii_tx` IP and require exactly five probes; the previous check referenced a deleted standalone `ila_latest_frame` cell.
- BD preflight passed with top `zynq_wrapper`, actual `eth_stream_stage3_axis_diag` module reference, and `LATEST_PREFLIGHT_ILA_PROBES=5`. Slot ownership simulation passed with zero collisions for safe read times.
- ELF-only artifact `stage5_latest_frame_pl_owner_camera_baseline_v1.elf` SHA-256 `0C00FBAAF83E2B7EDA5EC487874084C13F0D97E485A2CF8EA23A4DA1005F7B13`; manifest `test_artifacts/20261001T062420Z_owner_camera_baseline_v1.manifest.json`. No bitstream or board acceptance is claimed yet.

### Owner-camera baseline end-to-end acceptance [2026-10-01]
- The exact manifest pair was used: build `20261001T062420Z_owner_camera_baseline_v1`, bit SHA-256 `3B702CA5F73DB5E4F86820448A95B654FE4C2813E4148DC170105DCD885664F8`, ELF SHA-256 `0C00FBAAF83E2B7EDA5EC487874084C13F0D97E485A2CF8EA23A4DA1005F7B13`.
- After reloading that ELF through XSDB (`OWNER_CAMERA_BASELINE_ELF_DOWNLOADED`, CPU running), a synchronized 15 s privileged RK capture stored at `test_artifacts/owner_accept_20261001_retry3.pcap` contained 192,672 FPGA-source UDP packets, zero kernel drops, and 232 complete `827/827` frames. FIDs were continuous from `1675` through `1906`; no duplicate packet indices were observed. The terminal capture frame was truncated at the timeout boundary (`808/827`), not by an in-flight loss.
- `analyze_stage5_pcap.py` measured `start_to_start_fps=15.56`; every complete frame had a distinct SHA-256 in the capture. RK `frame_recv` log simultaneously reported `rx_fps=15.5--15.6`, `accepted=13232`, `dropped=0` per reporting window.
- Post-capture JTAG snapshot: CPU state remained running, MM2S status `0x00011000` (no error), packetizer `pkt_start=udp_done=0x0039B1B4`, and GMII TX activity/heartbeat continued. S2MM status retained `0x00015090` (internal + FSZ_LESS sticky status from startup), but it did not prevent the accepted complete-frame stream in this run.
- This is an end-to-end functional PASS for `OV5640 -> AXIS -> S2MM -> DDR slots -> PL owner -> MM2S -> packetizer/RGMII -> RK` at the restored camera timing (~15.56 fps). It is not a 40--50 fps result; that requires a separate sensor timing change and a new acceptance run. The S2MM sticky startup status remains a diagnostic warning and must not be silently reclassified as clean.

### Permanent commit-stop root cause and scoped repair [2026-10-01]
- The earlier camera-baseline functional PASS was a short capture, not a long-run reliability claim. Later, write-start advanced while commit and UDP counters froze. A five-probe observational ILA ECO captured the first fault at slot 2 base `0x11232800`: the preceding frame had only 299*2400 bytes, and the old observer rejected a legal slot-base restart unless the preceding frame was exactly complete. Its sticky fault suppressed every subsequent commit. S2MM FSZ_LESS was present, but the upstream short-frame cause was not identified.
- Only the frame-commit observer was functionally corrected: legal in-range base restart, first-AW marker queued with each transaction, accumulator reset in B-response order, short captures discarded, and commits only after a full successful new frame. The `vdma_frame_commit_axi_restart_v1` module reference forced fresh OOC synthesis; camera settings, video input, VDMA configuration, packetizer, RGMII and RK code were unchanged.
- Old RTL fails the short-frame regression; fixed RTL passes, including outstanding old responses and the actual 299-line geometry. All five existing path regressions pass.
- New build `20261001T084500Z_commit_restart_v1`: bit SHA-256 `C16B5261200629DD30B6BEF998B7D77CBC8D3DD824DB3A86317B6787F56A9EA2`, unchanged camera-baseline ELF SHA-256 `0C00FBAAF83E2B7EDA5EC487874084C13F0D97E485A2CF8EA23A4DA1005F7B13`. 60 source hashes match; route/DRC errors=0, setup +0.410 ns, hold +0.019 ns, all bus-skew constraints met.
- A host Tcl source-scope error and then inaccessible A9/DAP prevented two pre-download attempts; neither is valid repair-board evidence. Global-scope PS initialization and explicit success-marker checks were added to the download script. A user-confirmed additional cold start restored A9 access.
- Valid evidence `test_artifacts/20261001T084500Z_commit_restart_v1/20261001T090222Z_board`: 610-second RK capture, 7,814,148 packets, 9447 complete frames with 9447 distinct image-only hashes, no duplicate indices/FID gaps, 15.564121 fps. One interior frame missed 18 packets (FID 5381, indices 662..679); the terminal frame was capture-truncated. Kernel drops=0. All 120 JTAG samples retained S2MM `0x11000`, fault bits=0 and forward commit/TX progress. No permanent stop recurred, but no short-frame event occurred in this run, so short-frame recovery is simulation-verified, not directly board-trigger-verified. Neither loss-free delivery nor 40--50 fps is claimed.
- Per user request, ended diagnostic capture/monitoring and stopped the old RK viewer. FPGA autonomous streaming remains active for local viewing. Detailed report: `test_artifacts/20261001_commit_fault_root_cause.md`.

