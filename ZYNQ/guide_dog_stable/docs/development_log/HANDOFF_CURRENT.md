# Project Handoff: OV5640 ZYNQ HDMI Ethernet RK

Updated 2026-09-20. This is a standalone continuation guide.

## User rules
- Chinese. Evidence first. Do not guess or apply symptomatic fixes.
- Every fix/test/failure must be appended to FIX_LEDGER.md.
- After a Vivado build starts, never poll, inspect the process, or read build output. Wait for the user to send its result.
- Only full flash after user explicitly confirms cold power restart. Do not use ELF-only flashing for official camera/VDMA tests.
- Verify MD5 before flash. Builds must be in visible foreground cmd window.
- Never delete working artifacts or test_artifacts.

## Hardware and pipeline
- ZYNQ-7020 / Vivado 2026.1 / bare-metal A9.
- Camera 800x480 RGB888.
- Video chain: OV5640 -> ov5640_to_lcd -> v_vid_in_axi4s -> VDMA S2MM -> PS DDR -> VDMA MM2S -> v_axi4s_vid_out -> HDMI transmitter.
- FPGA MAC 12:34:56:78:9a:bc, FPGA IP 10.212.211.3. RK IP 10.212.211.2.
- Board has two DDR3 devices, both PS controllable. Current design only uses PS DDR mapped framebuffer.
- Current VDMA framebuffer region: FB_Base=0x11000000, one frame=800*480*3=0x119400, three-frame end=0x1134BC00.

## Known HDMI-good reference
- BIT: ov5640_hdmi/led_dbg_bit/led_dbg_bitstream.bit
- BIT MD5: D256149A1D80B0A7043C9C9063F9CB35
- ELF: ov5640_hdmi_led/build/led_node16.elf
- ELF MD5: 17558663EA5A2838E4B8ED4199D7C70F
- This exact pair has been board-tested HDMI good.

## Communication wire protocol
UDP payload is [4-byte hole][fid big endian 2][total big endian 2][idx big endian 2][1394 data]. TOTAL_PKTS=827, PKT_WIRE=1404, RK SKIP=4.
RK login cat@172.31.200.2 using key C:\Users\29113\.ssh\lubancat_codex_ed25519.
RK viewer command: cd /home/cat/eth_recv ; sudo -E env DISPLAY=172.31.200.1:0.0 XAUTHORITY=/home/cat/.Xauthority ./frame_recv

## High-confidence conclusions
1. HDMI-good BIT and HDMI-good ELF work on the same board. Base camera, HDMI, VDMA and display hardware are good.
2. Communication BIT plus HDMI-good ELF still produced HDMI corruption. Therefore RK, GIMME, snapshot, DCache and communication ELF runtime are not the trigger for HDMI-at-boot corruption.
3. TEST-011 communication BD plus RGMII pins/u_clk_phase/XDC but eth_stream silent shell produced normal HDMI. Communication BD shell and static RGMII integration are not sufficient triggers.
4. TEST-012 REDO-2 (verified 5 RX IDDR plus 5 TX ODDR, PHY held reset) produced normal HDMI.
5. TEST-014 (same RGMII primitives, PHY released after 670ms, real RGMII RXC active) produced normal HDMI.
6. TEST-015 (TEST-014 plus UDP RX/TX state machines, tx_start_en fixed zero, no BRAM/AXI business/PS-ETH CDC) produced normal HDMI. UDP state machines alone are not trigger.
7. TEST-016 FINAL explicit RAMB18E1: Port A writes at 100MHz, Port B reads on true RGMII clock and accesses potentially same addresses. HDMI occasionally tore/jumped. Valid physical RAMB was verified.
8. TEST-017 same RAMB activity but both ports use 100MHz was stable normal after a repeat flash. The first flash blanked but same BIT/ELF reflash recovered; this is flash/start anomaly, not RAM causality.
9. Current hypothesis requiring final discrimination: asynchronous dual-clock RAMB plus address collision. Do not yet state that dual-clock RAMB itself is conclusively guilty.

## Invalid tests: do not cite
- Original TEST-012 had no verified primitive identity.
- Initial TEST-013 had no reliable user-visible mode markers and artifact ambiguity.
- TEST-016 inference/KEEP versions did not yield eth_stream RAMB and are invalid.
- First TEST-012 REDO with ODDR after a mux failed DRC REQP-1884; invalid.

## Current active task: TEST-018
Purpose: distinguish pure asynchronous dual-clock RAMB from async address collision.
Current eth_rtl/eth_stream.v is TEST-018.
- Explicit RAMB18E1 U_TEST_RAM.
- Port A: s_axi_aclk 100MHz, writes physical addresses 0 through 511.
- Port B: real rgmii_rxc, reads physical addresses 512 through 1023.
- Thus physical A/B addresses are disjoint.
- UDP/RGMII/PHY retained; business AXI registers, PS-ETH CDC and actual UDP transmission absent.
Build script: build_test018.tcl. It was started before this handoff. Per user rule do not monitor it. Wait for user build result.
After user says build complete:
1. Check test_artifacts/test018_async_ramb18_disjoint.bit and corresponding post_synth DCP.
2. Verify DCP has U_TEST_RAM with REF_NAME RAMB18E1.
3. Record MD5 in FIX_LEDGER.md.
4. Wait for user cold reboot, then create/use dedicated flash script pointing exactly to test018 bit plus HDMI-good ELF 17558663.
5. Observe only HDMI. Do not start RK.
Interpretation: HDMI bad means pure async dual-clock RAMB is trigger. HDMI normal means only async collision combination is trigger.

## Dedicated artifact identities
TEST012 REDO-2 BIT DB1CD787B6F816528B6AEAFD746F2272.
TEST014 BIT D3CB09CE8BE31F762E62B36237951148.
TEST015 BIT D38838719B37DDF4CB722CF7B5E5B9CB.
TEST016 FINAL BIT 16188EE7E8100FB3617E0130DEE30C2E.
TEST017 BIT 6D59632AA44050BEDF9BA614B0FFE6C5.
All are under test_artifacts and must not be deleted.

## Important files
- eth_rtl/eth_stream.v: current TEST-018 RTL.
- eth_rtl/zynq_eth_stream_0_0.v: module_ref wrapper required by build.
- build_nonproj.tcl: common non-project build.
- test_artifacts: dedicated test BIT/DCP artifacts.
- FIX_LEDGER.md: authoritative running test/fix record.
- GIMME_DEBUG_LOG.md, STEP1_DEBUG_LOG.md, BUILD_LESSONS.md: historical logs.

## Build notes
The BD is locked/OOC and emits BD 41-1942 errors but existing non-project flow can still finish. Success only means BIT OK and COMPLETE from user-supplied log. Every test must use dedicated build_testXXX.tcl and dedicated flash_testXXX script.
Do not rely on ordinary eth_dbg_bitstream.bit identity.

## Future architecture
After hardware isolation is complete, desired architecture uses hardware video HDMI on existing DDR and PL DMA/master Ethernet transfer, ideally leveraging second DDR3 for network frame source. PS should only configure and request frames, not move pixels.

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
