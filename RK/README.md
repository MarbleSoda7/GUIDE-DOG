# RK — RK3568 端（导盲犬避障）

FPGA（Zynq xc7z020）把 800×480 BGR 双目帧通过 PL 以太网推到 RK3568；这里跑
YOLOv5n int8（RKNN NPU）出检测框，再以 `GRD1` UDP 回包发回 FPGA，由 PS 在框内算
视差距离、串口打印。实测 5.0 fps。

```
FPGA ──827 包/帧──▶ rxfast ──▶ /dev/shm/rxfast ──▶ guide_rk ──NPU──▶
                                                              GRD1 回包 ──▶ FPGA
```

## 目录

| 路径 | 内容 |
|---|---|
| `detect/` | 当前生产链路：`guide_rk.c`（C，5 fps）、`rk_detect.py`（Python 回退）、`rxfast.c`（拼帧）、`build.sh` / `run.sh` / `run_py.sh`、`test_det.py`、`rknn_api.h`。**细节看 `detect/README.md`** |
| `model/` | 参数与标签：`anchors_yolov5.txt`、`labels.txt`、`model_params.yaml`、`README.md`。**模型 `.rknn` 不入库** |
| `tools/` | `rk_capture_raw.py`（被动抓双目帧存 PNG）、`stereo_send.py`（不出 FPGA 时的合成发送器） |
| `deploy.sh` | 按板上布局安装：`./deploy.sh cat@172.31.200.2` 或板上 `./deploy.sh local` |

## 快速开始

```sh
./deploy.sh cat@172.31.200.2
ssh cat@172.31.200.2
cd /home/cat/rk_detect
./build.sh            # rxfast + guide_rk；./build.sh test 只跑数学自检
sudo ./run.sh         # 起 rxfast + guide_rk，并钉住 ARP 永久表项
```

板上布局（`deploy.sh` 照此对应，`run.sh` 的默认路径也照此）：

```
/home/cat/rk_detect/                    <- detect/*
/home/cat/guide_rknn_test/models/*.rknn <- 自己放（仓库不含模型）
/home/cat/guide_rknn_test/*.txt *.yaml  <- model/*
/home/cat/rk_tools/                     <- tools/*
```

`run.sh` 里那行 `ip neigh replace 10.212.211.3 lladdr 12:34:56:78:9a:bc nud permanent`
是整条链路的开关：PL 的 `udp_rx` 不回 ARP，PS 的 eth0 永远 NO-CARRIER，邻居表是
`INCOMPLETE` 时 `sendto()` 返回成功但一个包都上不了线。

## 协议

上行每包 10 B 头 + 1394 B 像素，827 包一帧（800×480×3 = 1,152,000 B）：

```
[ack BE16][want BE16][fid BE16][total BE16][idx BE16][1394B 像素]
```

下行回包：

```
[4B "GRD1"][2B fid][1B n][1B rsv] + n × 16B (1B cls, 1B score*100, 4×2B 框)
```

目标端口 1235，源 IP 10.212.211.3。

## 测试与指标

三层，从干净到真实：`./build.sh test`（纯数学，不需要 NPU/root）→
`python3 test_det.py 图.ppm`（单帧离线，隔离链路）→ `sudo ./run.sh`（整链路）。

每帧打印 `fid= det= prep= infer= getout= post= loop=`，判读要点：

- **`infer` ~25 ms** 才是模型本体的速度，换模型只看这个；`loop` 55–75 ms 被等帧门控，不是吞吐。
- **`det`** 走廊场景 0–3 正常，跌到 0 而 `infer` 正常 → 先看首次启动 dump 的 head 维度，
  出现 `UNRECOGNISED` 说明模型不是 3 head / 85 通道。
- 回包分数只有 **1% 精度**（`score*100` 存 1 字节），要精细分数用 `test_det.py`。
- PS 侧 `pending` 单调增长 = 产出快过消费；`range n/a` 占多 = 视差/标定问题，不是 YOLO。

## 运行依赖

- `librknnrt.so`（板上 `/usr/lib/librknnrt.so`，7,726,232 B，2026-05-02）/ rknn-toolkit-lite2
- 板载 gcc 9.4（`build.sh` 用）
- Python 回退另需 numpy / PIL / rknnlite —— `run_py.sh` 会显式补
  `PYTHONPATH=/home/cat/.local/lib/python3.8/site-packages`（sudo 会把 HOME 改成 /root）
- 必须是 root：AF_PACKET 原始套接字 + 改邻居表

## tools/ 的说明（重要）

`rk_capture_raw.py` 和 `stereo_send.py` 是**v1 包头**（12 B：`D2 C2 ver cam pair total idx plen`）
时期的工具，当前 PL 发的是上面的 10 B v2 头，**直接跑收不到帧**。
留在库里是因为 827 包重组、`SO_RCVBUFFORCE` 拉大 socket buffer、PNG 落盘这些逻辑还能直接用，
改 10 行解析即可。

## 历史

- 2026-11-04：本目录被当前板上的内容**整体覆盖**。上一代是 `src/rk_frame_recv.cpp` +
  `scripts/gd_*.sh` + `gd_client` / `upper_gui` / 去畸变 / QR 那套（44 个文件），
  仍然可以从前一个 master 提交取回：

  ```sh
  git show 9528ff2:RK/src/gd_client.py > gd_client.py
  git ls-tree -r --name-only 9528ff2 -- RK
  ```

## 来源核对

2026-11-04 17:1x 从板 `/home/cat/` 直接取回，与主仓库 `success_eight_hdmi/rk/` 逐字节一致：

| 文件 | md5 |
|---|---|
| `detect/guide_rk.c` | `d7c407c567ade89965316478c25bf667` |
| `detect/rk_detect.py` | `011456ec05dc76a53e246cea973ed273` |
| `detect/rxfast.c` | `2dc879f975e895f13677fe6b8b3bbd4c` |
| `detect/build.sh` / `run.sh` | `765b9082…` / `50cd8767…` |
| `detect/run_py.sh` | `3e70173cc667aa76ba439144b54c3c7d`（板上独有） |
| `model/anchors_yolov5.txt` | `c0bd396da01c74d27365685ebd196bd0` |

`detect/` 已在板上用 `./build.sh test` 验证：`SELFTEST OK`。
