# model — 检测模型的参数与标签（不含模型文件）

这个目录放**参数**，不放 `.rknn`。模型是外部用 rknn-toolkit2 转出来的 int8 RKNN，
体积和授权都不适合进 git，`model/*.rknn` 已被 `.gitignore` 挡掉。

| 文件 | 内容 |
|---|---|
| `anchors_yolov5.txt` | 18 个 anchor 浮点，按 `[head][anchor][w,h]` 顺序，被 `guide_rk.c` / `rk_detect.py` 直接读 |
| `labels.txt` | 80 个类名，行号即类别 id |
| `model_params.yaml` | 输入形状、三个 head 的网格、解码公式、阈值——换模型时必须一起对上的东西 |
| `.gitignore` | `*.rknn` / `*.onnx` / `*.pt` |

## 模型文件放哪

仓库不带模型，部署时自己放（板上原有的那份就是）：

```
/home/cat/guide_rknn_test/models/yolov5n_int8.rknn     3,046,136 B
sha256  f4900e080cd304f30e1f30ec1c7726f097628ff1b6809f0dd3d9931614fba254
```

`deploy.sh` 检测到 `model/*.rknn` 不存在时会跳过并提示，不会中断部署。
放好之后 `run.sh` 的默认路径就能直接用；换模型用 `MODEL=/path/to/x.rknn sudo ./run.sh`。

## 换模型时的硬约束

1. **输入**：`1×640×640×3`，uint8，RGB，不做归一化（int8 量化模型直接吃 uint8）。
2. **输出**：3 个 head，每格 85 通道（4 框 + 1 obj + 80 类），网格 80/40/20。
   不满足时 `guide_rk` 首次启动会 dump 出 `UNRECOGNISED (skipped)`，表现为
   `det=0` 但 `infer` 正常。
3. **anchors**：必须与训练一致，否则框整体偏大/偏小。
4. **激活**：输出已过 sigmoid（0..1），解码用 RKNN 官方 yolov5 的
   `(2p − 0.5 + grid) × stride` 约定。如果换的模型输出是 logits，必须先改解码。
5. **类别顺序**：必须与训练时的类名顺序逐行一致，否则 `class_name()` 会张冠李戴。

## 这不是训练配置

本仓库没有训练脚本、没有 `.pt`/`.onnx`、没有量化校准集，模型是外部训练转换后拿进来的。
`model_params.yaml` 记录的是**推理侧**参数，用于换模型/排查时对齐，不是训练超参。
