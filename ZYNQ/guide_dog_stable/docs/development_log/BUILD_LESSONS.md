# 构建经验与流程规则

## 用户明确要求

- 构建开始后，助手不得自行监控、轮询或读取构建过程输出。
- 构建期间不主动检查 Vivado 进程、不判断是否完成、不重复启动构建。
- 必须等待用户主动发送构建结果；收到结果后，才能进行产物校验、烧录或下一步分析。
- “前台窗口已启动”不代表构建成功；成功状态只以用户主动发送的完整结果为准。

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

## 硬性规则（2026-09-21，用户强制：不许再犯低级错误）

### 关键路径脚本纪律
1. 关键路径脚本（改BD/构建/烧录）只允许包含【已在本会话验证过语法】的命令。
2. 辅助功能（地址dump/报告打印）一律不得加入关键路径；确需加入，先在独立小脚本验证语法。
3. report_property 只接受单个对象。多对象用 foreach 逐个调用。
4. 每次脚本改动后、交给用户运行前，必须逐行自查语法与对象数量。

### 本会话已验证的命令用法
- get_bd_addr_segs -of_objects [get_bd_cells X] → 可多对象，但 get_property 需逐个
- get_property OFFSET $seg → 单对象，OK
- connect_bd_net 已连接会报错 → 必须 catch 包裹，catch 后脚本继续
- delete_bd_objs 删除 net 后 cell 仍存在
- set_property CONFIG.NUM_MI N [get_bd_cells X] → 端口自动增删，已有连接保留
- read_bd 之后必须 open_bd_design 才能操作 BD 对象
- 非工程模式 generate_target 不产生 DCP；OOC DCP 需工程模式 launch_runs
- launch_runs 前若 run 已完成/失败需 reset_run
- save_project_as 产生独立 .srcs 副本，与主工程 BD 会分叉

### 失败案例存档
- 案例1: report_property 传 2 个对象 → 17-56 报错，脚本死在 save 前，BD 改动丢失
- 案例2: read_bd 后没 open_bd_design → get_bd_cells 报 "must be open"
- 案例3: update_ip_catalog 在沙箱环境触发 tclapp::load_apps 'Could not open C' → 我的沙箱不能跑 Vivado 批处理，只有用户 cmd 可以
- 案例4: launch_runs 不 reset_run → "needs to be reset before launching"
- 案例5: 删除 IP 后不缩互连 → 悬空 xbar 主口 → AXI 总线死锁（Phase B 总线挂起根因）

## 最高优先级教训 [2026-09-21 晚间，用户严厉批评]

### 犯规行为记录
在用户明确多次要求"不要猜、建立完整证据链"之后，我仍然：
1. 提出"genlock耦合"假设时直接说"ROOT CAUSE FOUND"——但genlock解释仅基于
   xparameters的GENLOCK_MODE参数推断，从未在板上验证
2. 正确做法应当是：写诊断ELF → 板上跑 → 看数据 → 再下结论

### 硬性规则（永久生效）
1. 禁止在证据不足时使用"ROOT CAUSE FOUND"、"找到了"等定论性表述
2. 任何假设必须标注为【假设】，且必须有对应的验证实验
3. 诊断ELF必须在烧录并看到UART输出后，才能讨论结论
4. 结论只能来自板上实测数据，不能来自文档推断
5. 我说"可能/应该/理论上"的时候，就是还没验证的时候——闭嘴，去验证

### 今晚genlock假设的正确验证方式（已准备但未执行）
- 诊断v4 ELF已构建（MD5 06F7BD8714316F4E8C99F527DACDCEA7）
- 它打印：PARKPTR/STAT全位解码/HSIZE/VSIZE/STRIDE/START寄存器
- 每2秒采样10次 + DDR多点采样
- 尝试genlock-free配置 + tail-kick兜底
- 必须烧录跑完看UART输出后，才能说任何结论
