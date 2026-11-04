# PL 双目硬件畸变矫正：实现与交接说明

## 1. 当前交付边界

仅修改独立副本 D:/latest_project_pl_rectify；源目录 D:/latest_project 不作为写入目标。实现的是面向 HLS 综合的真实 PL remap 源码数据通路，不是 PS 上调用 OpenCV 替代硬件，也不是 AXIS bypass。
**已完成的构建：HLS 综合导出（pl_remap_accel:1.0）→ Vivado BD 集成 → 全设计综合/实现/write_bitstream → 同轮 bit/HWH/XSA → 产物封存 → image.ub 与 BOOT.BIN 重打包 → 部署到 sd_card_latest。** 实测 routed WNS +0.150ns、0 failing endpoint、routing errors 0、DRC 0 Error；资源 LUT 19,144(35.98%)、FF 31,352(29.47%)、BRAM Tile 31.5(22.50%)、DSP 50(22.73%)；功耗 2.067W。未重建 PetaLinux rootfs（工具链缺失），改为对既有 initramfs 原位替换。
尚未验收：上板图像质量、真实标定精度、≥10 pair/s 吞吐、曝光同步。默认 --rectify off 保留原始图回退。

## 2. 数据路径与职责

```text
OV5640 左/右 → 两路 VDMA 三槽 DDR
                     ↓ 停止两路写入并等待HALTED；复制已完成槽；恢复采集
                  raw1 / raw2 不变快照
                     ↓ 同一个 PL 核先左后右
         Q10.6网格插值 → 源图cache → 双线性RGB888 → corrected1 / corrected2
                     ↓ 两眼处理均成功后才开始发送
                cam1全帧UDP完成 → cam2全帧UDP完成 → RK双目显示
```

PL 从 DDR 读取源图与 LUT，写回校正帧。PS 负责摄像头/VDMA控制、快照复制、LUT上传、寄存器启动及UDP调度；只有显式 --verify-remap-crc 会额外读输出做CPU CRC校验，不执行PS像素矫正。
两摄像头仍自由运行。pair_id 是软件配对序号，不是共同曝光时间戳。停止VDMA是保守的快照稳定策略，不是硬件曝光同步；当前只能按静态/慢动场景验证，并实测停启对帧率的影响。HALTED只按当前VDMA操作完成解释，不把停机中断帧当作整帧；每次恢复后还等待每路至少3次writer slot变化、完整轮转三槽，超时丢弃整对。此保守策略会显著限制吞吐，最低10 pair/s仍需板级验证，可能需要后续真正的frame ownership优化。

## 3. 核实现与数值契约

- 固定输入/输出：800×480、紧凑RGB888，每眼1,152,000字节。
- 单个64位 AXI memory bundle，共享一个核顺序处理左右眼；src/dst/LUT首地址均8字节对齐。
- 运行时选择 step=16 或8；Q10.6无符号坐标，0xFFFF为无效节点。
- 网格最后节点在x=799、y=479，不在800/480；最后网格跨度分别为15或7。
- 网格坐标采用先横向floor、再纵向floor；四个signed横向分子在每个cell行初始化，随后逐像素加法递增；跨度8/16/7/15使用常量除法分支，不累计已舍入的delta。RGB双线性结果采用 (weighted_sum+2048)>>12。任何角点无效时对应单元填黑。源图最后行/列合法，邻点钳制到边缘。
- 源图使用8KiB、64×128字节直接映射cache；miss按16×64位连续读取。LUT预装入BRAM，输出按行连续64位写回。
- CRC为IEEE CRC32，按输出RGB字节光栅顺序；统计项包含invalid pixels、128B cache misses、pixel count、CRC。
- HLS层性能与资源仍需综合报告和板级计时验证；主机C++测试不等于RTL时序/AXI仿真。

实现文件：[pl_remap_accel.cpp](<D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/pl_remap_accel.cpp>)；逐像素参考：[remap_reference.py](<D:/latest_project_pl_rectify/tools/remap_reference.py>)。

## 4. 摄像头参数怎么改

参数入口：[camera_params.json](<D:/latest_project_pl_rectify/tools/camera_params.json>)。左右眼各自包含K（3×3内参）、D（4项fisheye畸变）、R（3×3整流旋转）、rectified_K（3×3输出投影）。
已有矩阵时，实际映射以矩阵为准；只改hfov_deg不会覆盖已有K。170度镜头和约40mm基线不能代替实测双目标定。基线主要服务后续深度换算，本次没有实现视差/测距。
默认配置 calibration_valid=false，属于170度→100度输出视场的合成烟测参数。不能只把该标记改true就称为已标定。实测参数必须由棋盘格标定或可信外部标定导入，并另做留出样本极线误差检验。

### 4.1 实测标定（之后取得图像后）

准备至少15组800×480原始左右图，匹配文件名，棋盘格覆盖视场各区与不同姿态。必须输入实物方格边长mm；默认内角点9×6，可修改。主机安装NumPy和带fisheye模块的OpenCV。所有命令在副本根目录执行：

```sh
python3 tools/stereo_calibrate.py --left-dir calibration/left --right-dir calibration/right --square-mm 20 --cols 9 --rows 6 --out tools/camera_params_measured.json --grid-dir calibration/luts
```

20只是命令示例，替换为真实方格尺寸。输出包含K/D/R/T、R1/R2/P1/P2/Q、实测基线、样本来源和RMS；calibration_valid表示实测来源，不表示精度已通过验收。--grid-dir会生成step16与step8子目录，方便比较离散误差。

### 4.2 生成部署LUT

```sh
python3 tools/generate_remap_lut.py --config tools/camera_params_measured.json --step 16 --output-dir zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data
```

只做数据通路烟测时才使用：

```sh
python3 tools/generate_remap_lut.py --config tools/camera_params.json --allow-synthetic --output-dir zynq_project/petalinux_key/project-spec/meta-user/recipes-apps/camremap/files/data
```

同时部署left_remap.rmp、right_remap.rmp、remap_manifest.json，不能混用不同配置的左右眼或旧manifest。保持800×480与当前ABI时，修改K/D/R/rectified_K或切换step不需重综合PL，只需重新生成并部署两份LUT及manifest。改分辨率/像素格式/位宽则需要更改硬件和全链路。

## 5. RMP2格式与安全检查

| 项目 | step16 | step8 |
|---|---:|---:|
| 网格 | 51×31 | 101×61 |
| 节点数 | 1,581 | 6,161 |
| payload字节 | 6,324 | 24,644 |
| 文件字节（含96字节头） | 6,420 | 24,740 |
| DDR上传字节（补齐64位） | 6,328 | 24,648 |

头包含magic/version/header bytes、geometry/step/frac/eye/flags、节点数、payload长度和CRC。flags bit0表示实测标定来源；40..71存payload SHA256，72..95存配置SHA256前24字节。头CRC仅覆盖0..35，因此运行驱动还要求manifest内完整文件SHA256和完整配置hash进行交叉绑定。校验用于防错配/损坏，不是密码认证。
上传只取payload，不把96字节头交给PL；额外4字节补零。左右眼预留各0x8000，超界、重叠、步长不一致、缺眼、错眼、hash不符都拒绝启动。manifest中的source_locality是16×16区域包围盒的分析估计，不是实际8KiB直接映射cache的命中率或带宽实测。

## 6. DDR与寄存器接口

reserved-memory为0x30000000起16MiB、no-map；以下均为相对此基址的偏移。

| 用途 | 偏移 | 字节 |
|---|---|---:|
| cam1三槽 | 0 / 0x00119400 / 0x00232800 | 每槽1,152,000 |
| cam2三槽 | 0x00400000 / 0x00519400 / 0x00632800 | 每槽1,152,000 |
| raw1快照 | 0x00800000 | 1,152,000 |
| raw2快照 | 0x00920000 | 1,152,000 |
| left LUT | 0x00A40000 | 0x8000预留 |
| right LUT | 0x00A60000 | 0x8000预留 |
| corrected1 | 0x00C00000 | 1,152,000 |
| corrected2 | 0x00D20000 | 1,152,000 |

启动检查所有区间非重叠；驱动再次检查物理地址在reserved范围内且src/dst/LUT不重叠。O_SYNC/no-map是CPU映射条件，不独立证明PL写完成；必须先完成硬件停机/完成握手。

| HLS AXI-Lite相对偏移 | 字段 |
|---|---|
| 0x00 | AP_CTRL：start bit0 / done bit1 / idle bit2 |
| 0x10 / 0x14 | src低/高32位 |
| 0x1C / 0x20 | lut低/高32位 |
| 0x28 / 0x2C | dst低/高32位 |
| 0x34 | step（8或16） |
| 0x40 | status（0成功；1非法step） |
| 0x50 / 0x60 | invalid_count / cache_miss_count |
| 0x70 / 0x80 | pixel_count / CRC32 |

Guard是旁路响应监测器，不是AXI隔离器：监测R/B握手的非OKAY响应，不中断/终止在途事务。ID=0x524D5032@0x00，FLAGS@0x04，读/写错误计数@0x08/0x0C，首次response@0x10，W1C@0x14，ABI=1@0x1C。驱动在每次启动前检查ID/ABI、既存fault和idle，错配时拒绝写入启动参数。故障/超时后禁止继续复用核，须重置或重新配置PL。

## 7. Vivado集成及后续构建

以下步骤已按顺序实际执行，可作为复现流程。统一入口为 [BUILD_PL_RECTIFY.ps1](<D:/latest_project_pl_rectify/BUILD_PL_RECTIFY.ps1>)：无参数只预检；在Xilinx工具环境显式运行 `./BUILD_PL_RECTIFY.ps1 -Build -Force` 才进行HLS/Vivado长构建，并校验同轮canonical bit/HWH/XSA与源码hash。此入口不自动完成PetaLinux或SD打包。离线验证证据与未验收项见 [验证记录](<D:/latest_project_pl_rectify/PL_RECTIFY_VERIFICATION.md>)。

1. 在Vitis HLS 2024.1环境设置PL_RECTIFY_BUILD=1，运行run_pl_remap_hls.tcl，综合并导出xilinx.com:hls:pl_remap_accel:1.0。门禁避免误触长构建。
2. 再以Vivado 2024.1 batch执行integrate_pl_remap.tcl。该脚本负责准备副本、注册新IP、连接和validate/save BD；不launch综合或实现。必须先有实际导出的HLS IP。
3. 集成使用FCLK0=100MHz：PS M07→HLS控制@0x40000000、M08→guard@0x40020000；HLS gmem→SmartConnect S03→原HP0，保留原M00..M06/S00..S02。检查地址冲突、原连接和外部源路径，失败须修正，不能强行继续。
4. 运行HLS和全设计综合/实现后检查资源、WNS、DRC及CDC；生成同一轮canonical bit/HWH/XSA，再导入PetaLinux更新硬件描述和镜像。
5. 更新应用data内HWH/bit和LUT/manifest，核对reserved DDR、启动BOOT.BIN中的实际bit和运行时HWH一致。重新打包BOOT.BIN/boot.scr/image.ub；不要从历史delivery或旧runs拼接产物。
6. 写SD前先备份原卡；本次已备份到 sd_card_original_backup，并把新包部署到 sd_card_latest（尚未写物理卡）。

脚本：[run_pl_remap_hls.tcl](<D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/run_pl_remap_hls.tcl>)、[integrate_pl_remap.tcl](<D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/integrate_pl_remap.tcl>)。

## 8. 新固件生成后的运行方式

先停止自动服务，避免多个进程访问同一DMA/VDMA；确认bit/HWH来自同一构建。

```sh
# Zynq Linux；仅新固件支持PL模式
/etc/init.d/camremap stop
python3 -u -m camremap --rectify off --fps 10

# 实测LUT模式
python3 -u -m camremap --rectify pl --fps 10 --verify-remap-crc

# 仅允许合成参数烟测
python3 -u -m camremap --rectify pl --allow-synthetic-lut --frames 20 --fps 5 --verify-remap-crc
```

实际运行只选其中一条python命令，不并行运行。--fps是上限节拍，不是性能保证。CPU CRC调试会增加DDR读取和PS开销，性能测量时可关闭但保持PL完成/guard检查。
PL超时或AXI fault可能仍有在途写入：不能只重启Python或只reset UDP DMA后重试。TX未完整排空也要停止，避免下一眼修改metadata把尾包重标。运行进程分别以2/3退出；自启动监督脚本对这两种错误写入/run/camremap-fatal并停止自动重启。必须先重新配置PL或重启板卡；若采用手工重新配置，确认完成后才执行/etc/init.d/camremap clear-fatal并重新启动服务，不能把清除标志当作硬件复位。

RK3568接收格式不变，仍为UDP1234、800×480 RGB888、12字节v1头、827包（826×1394+556）。接收端仅在完整帧发布时将pixels与pair_id一起更新，显示必须同pair_id。后续在RK本机编译并运行：

```sh
cd /home/cat/eth_recv
bash _deploy.sh
sudo -E ./frame_recv_stereo --no-infer
```

有桌面/X11时才显示窗口；SSH无显示可使用接收端headless方式。RK eth0验收地址10.212.211.2/24，FPGA目标10.212.211.3，勿误改用于SSH的其他网口。

## 9. 验收与明确未完成项

- 离线：参数合法性、RMP2 hash/CRC、step8/16/末行末列、非整数插值、C++全帧参考、MMIO错误注入及双眼失败不发送。
- HLS之后：检查导出register map与本表逐字一致，单m_axi gmem、资源和latency；不能凭C++通过推断综合一定成功。
- Vivado之后：检查两路摄像头/原UDP未回归，地址/时钟/复位正确，资源时序满足，guard能观测错误响应。
- 上板：先raw基线，再合成LUT烟测和identity/CRC，再实测标定LUT。观察invalid/cache miss/CRC/完整pair计数，核对没有串眼、错pair或陈旧画面。
- 帧率：最低10 pair/s是待验收目标，不能作为当前结果。停止/恢复VDMA、PS拷贝、cache冲突和DDR共享都可能限制吞吐，需计时后再优化。
- 图像质量：以真实棋盘格/直线/静态场景验收；当前没有真实标定图、留出样本极线误差或测距精度报告。
- 本工程不是硬件同步曝光系统，也未实现StereoBM/SGM、深度图或目标距离。

