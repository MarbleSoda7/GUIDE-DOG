#!/bin/bash
# board_service.sh - 板卡端常驻推理服务 (断线自动重连)
# 用法: ./board_service.sh start|stop|status|log
HOST=${GD_HOST:-10.212.211.1}
PORT=${GD_PORT:-9600}
MODEL=${GD_MODEL:-models/yolov5n_int8.rknn}
UNIT=gd-infer

cd /home/cat/guide-dog || exit 1

case "$1" in
  start)
    sudo systemctl stop $UNIT 2>/dev/null
    sudo systemd-run --unit=$UNIT --collect \
      --working-directory=/home/cat/guide-dog \
      /usr/bin/python3 /home/cat/guide-dog/board_client.py "$HOST" "$PORT" "$MODEL"
    sleep 2
    sudo systemctl is-active $UNIT && echo "[$UNIT] 已启动 (自动重连, 目标 $HOST:$PORT)"
    ;;
  stop)
    sudo systemctl stop $UNIT 2>/dev/null && echo "[$UNIT] 已停止"
    ;;
  status)
    sudo systemctl status $UNIT --no-pager | head -12
    ;;
  log)
    sudo journalctl -u $UNIT -n 40 --no-pager
    ;;
  *)
    echo "用法: $0 start|stop|status|log"
    ;;
esac
