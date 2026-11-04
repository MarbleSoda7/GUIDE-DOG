#!/bin/sh
# 把本目录推（或装）到 RK3568 上应有的位置。
#
#   ./deploy.sh cat@172.31.200.2    # 从 PC 推送（usb0 的地址，密码 temppwd）
#   ./deploy.sh local               # 已经在板上，直接安装
#
# 目标布局与 run.sh / guide_rk 的默认路径严格对齐：
#   detect/*        -> /home/cat/rk_detect/
#   model/*.rknn    -> /home/cat/guide_rknn_test/models/   （仓库不含模型，缺失时跳过）
#   model/*.txt     -> /home/cat/guide_rknn_test/
#   model/*.yaml    -> /home/cat/guide_rknn_test/
#   tools/*         -> /home/cat/rk_tools/
#
# 只覆盖源码和小文件；不删目标目录里的其他东西（比如已编译的 guide_rk）。
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DET=/home/cat/rk_detect
GKY=/home/cat/guide_rknn_test
TOOLS=/home/cat/rk_tools

if [ "$1" = "local" ]; then
    mkdir -p "$DET" "$GKY/models" "$TOOLS"
    cp "$HERE"/detect/* "$DET"/
    cp "$HERE"/model/*.txt "$HERE"/model/*.yaml "$GKY"/ 2>/dev/null || true
    cp "$HERE"/tools/* "$TOOLS"/
    if ls "$HERE"/model/*.rknn >/dev/null 2>&1; then
        cp "$HERE"/model/*.rknn "$GKY/models"/
    else
        echo "WARN: 仓库不含 model/*.rknn，请把模型放到 $GKY/models/"
    fi
    chmod +x "$DET"/*.sh "$TOOLS"/*.py 2>/dev/null || true
    echo "installed: $DET / $GKY / $TOOLS"
    echo "next: ssh in, cd $DET, ./build.sh, sudo ./run.sh"
    exit 0
fi

if [ -z "$1" ]; then
    echo "usage: $0 cat@172.31.200.2 | local"
    exit 1
fi
HOST=$1
ssh "$HOST" "mkdir -p $DET $GKY/models $TOOLS"
scp "$HERE"/detect/* "$HOST:$DET/"
scp "$HERE"/model/*.txt "$HERE"/model/*.yaml "$HOST:$GKY/"
scp "$HERE"/tools/* "$HOST:$TOOLS/"
if ls "$HERE"/model/*.rknn >/dev/null 2>&1; then
    scp "$HERE"/model/*.rknn "$HOST:$GKY/models/"
else
    echo "WARN: 仓库不含 model/*.rknn，请把模型放到 $HOST:$GKY/models/"
fi
ssh "$HOST" "chmod +x $DET/*.sh $TOOLS/*.py 2>/dev/null; echo installed: $DET $GKY $TOOLS"
