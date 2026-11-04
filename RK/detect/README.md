# rk_detect — RK3568 检测端代码包

导盲犬避障项目里跑在 RK3568 上的一段：收 FPGA 通过 PL 以太网发来的 800×480 BGR 帧，
用 RKNN NPU 跑 YOLOv5n int8，把检测框以 `GRD1` UDP 回包发回 FPGA（10.212.211.3:1235）。

本包只含**检测端**。FPGA 侧（VDMA 采集、remap、视差、UDP 收发）在 `../../delivery/`
的镜像里，不在此包内。

```
rk_detect 检测端          上行 827 包/帧 → rxfast 拼帧 → /dev/shm/rxfast
                                     ↓
                          guide_rk 取最新帧 → letterbox 640×640 → NPU
                                     ↓
                          GRD1 回包 → PL → PS 在框内算视差距离 → 串口打印
```

## 文件

| 文件 | 说明 |
|---|---|
| `guide_rk.c` | **生产实现**，C99 + librknnrt，实测 5.0 fps，loop 55–75 ms |
| `rxfast.c` | AF_PACKET 收包 + 拼帧，把整帧发布到 `/dev/shm/rxfast` |
| `rk_detect.py` | Python 参考实现 / 回退，纯 numpy + PIL，约 0.65 fps |
| `rknn_api.h` | RKNN 头文件，结构体布局必须匹配板上 `librknnrt.so`（本项目为 2.3.2） |
| `build.sh` | 编译；`./build.sh test` 只跑数学自检 |
| `run.sh` | 起 rxfast + guide_rk，自动钉 ARP 永久表项 |
| `run_py.sh` | Python 回退的启动器（补 `PYTHONPATH`，因为 sudo 会把 HOME 改成 /root） |
| `test_det.py` | 单帧离线测试（不碰相机和网络） |
| —（anchors 见 `../model/anchors_yolov5.txt`） | 18 个 anchor 浮点，`[head][anchor][w,h]` |

## 前置条件

- RK3568 上的 `librknnrt.so`（`/usr/lib/librknnrt.so`，或 rknn-toolkit-lite2 装在
  site-packages 里的那份，`build.sh` 会自动找）
- 板载 gcc（本项目实测 9.4）
- 模型：`yolov5n_int8.rknn`（**不在本包内**，见下）
- 必须是 root：AF_PACKET 原始套接字 + 改邻居表

## 模型与 anchors

```
/home/cat/guide_rknn_test/models/yolov5n_int8.rknn
/home/cat/guide_rknn_test/anchors_yolov5.txt
```

模型是外部转换好的 int8 RKNN，本仓库没有训练/导出代码。三个约束：

1. 输入 640×640×**RGB**，输出 3 个 head，每格 85 通道（4 框 + 1 obj + 80 类）。
   不满足会打印 `UNRECOGNISED (skipped)`，表现为 `det=0` 但 `infer` 正常。
2. anchors 必须与训练时一致，否则框大小整体偏。
3. 回包分数是 `score*100` 存 1 字节，**精度只有 1%**；要精细分数用 `test_det.py`（float）。

`../model/anchors_yolov5.txt` **就是板上 `/home/cat/guide_rknn_test/anchors_yolov5.txt` 的原件**
（96 B，md5 `c0bd396da01c74d27365685ebd196bd0`），不是猜的默认值。换模型才需要换它。
`deploy.sh` 会把它放到 `/home/cat/guide_rknn_test/anchors_yolov5.txt`，与 `run.sh` 的默认值对齐。

模型侧板上实际有两个：

```
yolov5n_int8.rknn    3,046,136 B   <- run.sh 默认用这个
yolov5s_relu_int8.rknn 7,934,072 B
```

## 编译

```sh
cd /home/cat/rk_detect
./build.sh          # rxfast + guide_rk
./build.sh test     # 只做 letterbox/解码/NMS/回包 的数学自检，不需要 NPU、不需要 root
```

自检输出形如 `letterbox r=0.8000 dw=0 dh=128` → `post n=2` → `reply len=24` → `SELFTEST OK`，
出现 `FAIL ...` 说明后处理坏了，与模型无关。

## 运行

```sh
sudo ./run.sh
# 换模型/网口：
MODEL=/path/to/other.rknn IFACE=eth1 sudo ./run.sh
```

`run.sh` 做的事：`ip neigh replace 10.212.211.3 lladdr 12:34:56:78:9a:bc nud permanent`
→ 杀掉旧进程 → 起 `rxfast` → 前台跑 `guide_rk`。Ctrl-C 一起收。

**那行 ARP 是整条链路的开关**：PL 的 `udp_rx` 不回 ARP，PS 侧 `eth0` 永远 NO-CARRIER，
邻居表是 `INCOMPLETE` 时 `sendto()` 照样返回成功但一个包都上不了线。

Python 回退：

```sh
sudo python3 -u rk_detect.py --iface eth0            # 自动用 rxfast 的共享内存
sudo python3 -u rk_detect.py --rx py                 # 纯 Python 收包
```

## 每帧打印怎么读

`guide_rk`：

```
fid=1234   det=3  prep=18.2 infer=25.1 getout=9.0 post=6.3 loop=61.2ms
    person 0.87 (120,80)-(300,400)  chair 0.41 (410,300)-(500,430)
```

| 字段 | 正常值 | 含义 |
|---|---|---|
| `infer` | ~25 ms | NPU 纯推理，换模型只看这个数 |
| `det` | 场景相关，走廊 0–3 | 20 = 撞 `MAX_BOXES` 上限 |
| `prep` / `getout` / `post` | 18 / 9 / 6 ms | letterbox、取输出、NMS+还原 |
| `loop` | 55–75 ms | 被等帧门控，**不是**吞吐上限 |

首次启动会把三个 head 的维度 dump 一次（`out[0] dims=1,3,85,80,80 ... gh=80 gw=80`），
换模型时先看这一行。

`rk_detect.py` 每 2 s 打一次心跳：

```
RX raw=... pkts=... frames=... best=n/827 rej[mac=0 ip=0 len=0 total=0] fid=... ack=... want=...
```

`rej` 任一非 0 就是收包过滤出问题；`pkts` 应约 2.18 万/s、`frames` 约 26/s。

## 已知限制

- 回包实际速率低于发送速率时，PS 侧 `pending` 会缓慢增长；`want` 追问的是旧 fid，
  而接收端只保留最近 8 帧，太老的永远命中不了。
- 5.0 fps 的瓶颈在 FPGA 发送侧（`tx_fid` 实测 5.3/s），不在 RK。
- 模型只认训练集里的那 80 类；路障锥、栏杆、台阶、坑洞、玻璃门不在其中，必然漏检。
  这不是阈值问题，需要换数据集微调。
- `rk_detect.py` 的收包路径在本包里叫 `Receiver`/`FastReceiver`，与 `guide_rk` 的
  共享内存布局（`struct shm_hdr`）必须一致，改一处要同步另一处。

## 来源与核对

2026-11-04 17:1x 从板上 `/home/cat/rk_detect/` 直接取回原件，与主仓库
`success_eight_hdmi/rk/` 逐字节对比，**四个源文件 md5 全部一致**：

| 文件 | md5 | 两处一致 |
|---|---|---|
| `guide_rk.c` | `d7c407c567ade89965316478c25bf667` | 是 |
| `rk_detect.py` | `011456ec05dc76a53e246cea973ed273` | 是 |
| `rxfast.c` | `2dc879f975e895f13677fe6b8b3bbd4c` | 是 |
| `build.sh` | `765b90823ece65a818f01abe4fe9113d` | 是 |
| `run.sh` | `50cd8767316fbe295cc9a14c87159ebc` | 是 |
| `run_py.sh` | `3e70173cc667aa76ba439144b54c3c7d` | 板上独有 |

板上的编译产物 `guide_rk`（587bd494）和 `rxfast`（dba8bdce）故意不带，用 `./build.sh`
在目标板上重编，避免架构/库版本对不上。

板上还有一份 `rk_detect_old.py`（2024 年旧脚本，md5 `a094eedb`），**未收录**：
它和现在的收包协议不一致，只作历史存档。

`test_det.py` 由 `_uart/_rk_test_det.py` 改成可带参数、可读任意尺寸图片（内部统一缩到
800×480，因为 `Detector` 用常量 W/H 夹取框）的版本。`SHA256SUMS` 是本包内文件的校验值。
