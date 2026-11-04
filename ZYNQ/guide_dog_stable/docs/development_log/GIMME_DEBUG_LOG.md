# GIMME 死因排查日志 (真构建后)

> 2026-09-20 下午。真构建链打通后, LED 卡 1001 (GIMME 零响应)。
> 本文档记录完整排查证据链 + 方案B决策。

## 背景

真构建 (BB5921DE/C2F8F8AA): 删除陈旧 dcp + 手写 zynq_eth_stream_0_0 包装层
→ R1~R9 修改第一次真正上板 → 但 GIMME 立即死。

之前所有"正常"的 bit (0C0A700E..175D04A5) 全部复用 09-18 陈旧 dcp
→ 那些构建里跑的 eth_stream 从来不是我们的源码!

## 排查记录 (全部实证, 无猜测)

| # | 嫌疑 | 验证方法 | 结果 |
|---|---|---|---|
| 1 | 时序违例 | timing.rpt | ✗ 全过 (WNS +1.916ns, 0 fail) |
| 2 | 端口映射 | component.xml + zynq.v 逐端口比对 | ✗ 按名一致 (28端口) |
| 3 | RGMII RTL 差异 | 与 29_eth_udp_loop 原版 MD5 对比 | ✗ 47F3B8D2 完全一致 |
| 4 | UDP 参数链 | eth_stream→udp→udp_rx 逐级检查 | ✗ BOARD_MAC/IP 传递正确 |
| 5 | PHY 复位 | RTL 检查 | ✗ rst_cnt 670ms 在位 |
| 6 | frame_req CDC | RTL 检查 | ✗ rec_d1/2/3→sticky 完整 |
| 7 | AXI 译码死锁 | 结构对比 | ✗ 与 v5 相同(曾在dcp正常) |
| 8 | RGMII 时钟架构 | BD clk_wiz 链确认 | ✗ rgmii_rxc→u_clk_phase(210°)→eth_stream 等价 |

## 核心矛盾 (未解)

09-18 陈旧 dcp: GIMME 正常
我的重写源码:   GIMME 死 (真构建上板)
接收路径"没改" — 但 09-18 原版源码已丢失 (逐轮覆盖), 无法 diff!

## 附加发现 (排查路上)

- component.xml 只列 20 端口 (busInterface 视图) — rgmii 在 model ports, 提取方式问题, 非真缺失
- BD 完整 IP 清单确认: clk_wiz:6.0 (u_clk_phase) 在位
- zynq.v (synth 产物) 是 09-18 生成 — 但 BD 结构未变, 连接有效
- 原版工程顶层: rgmii_rxc → 内部 clk_wiz → 相移 → gmii_to_rgmii (与BD外置等价)

## 决策: 方案B — 移植原版接收链

29_eth_udp_loop 工程 (36MB 完好) 有【经过验证的】:
  - eth_udp_loop.v 顶层 (GIMME 接收正常工作的原始实现)
  - udp/*.v + gmii_to_rgmii/*.v (与我们 MD5 一致)

方案B: eth_stream = 原版顶层接收链(原样) + 我们的发送侧(双bank乒乓)
  接收: udp_rx + frame_req 逻辑 — 100% 原版代码
  发送: BRAM 双bank + one-hot + pending (Step1 目标)
  AXI: 保留我们的无死锁译码 (曾在dcp里验证过的结构)

## 文件版本

| 文件 | 状态 |
|---|---|
| eth_stream.step1_backup.v | Step1 全部修改 (双bank+onehot+pending+地址链) |
| eth_stream.v | v5 baseline (排查用, GIMME未验证) |
| 29_eth_udp_loop/ | 原版参考工程 (接收链来源) |

## 新证据: 真构建后的 CDC 违例

- BIN3 的 STATUS-on-LED 读数为 0, GIMME 不响应; R0 最小回发链正常。
- post-route timing.rpt 具体显示: async_default TNS=-744.655ns; clk_fpga_0→eth 时钟域有 16 条严重跨域路径。
- 这些路径来自新源码中的 CDC 信号/双时钟 BRAM, 不是 HDMI 的 obs 计数器或 HDMI 串化器。
- 已在 eth_pins.xdc 加双向 CDC false_path; 本轮必须用新约束重新综合、实现、检查 timing.rpt。
