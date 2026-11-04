#!/bin/bash
# gd_server_ctl.sh - 导盲推理服务管理 (systemd 单元 gd-server)
# 用法: sudo ./gd_server_ctl.sh start|stop|restart|status|log
set -u

DIR=/home/cat/guide-dog
MODEL="$DIR/models/yolov5n_int8.rknn"
PORT=9527
FOV=180.0
UNIT=gd-server

case "${1:-status}" in
  start)
    systemctl stop $UNIT 2>/dev/null
    systemd-run --unit=$UNIT --working-directory=$DIR \
      "$DIR/gd_server" "$MODEL" $PORT $FOV
    sleep 3
    systemctl is-active $UNIT && ss -tln | grep -q ":$PORT" && \
      echo "[+] 服务已启动, 监听 0.0.0.0:$PORT" || echo "[!] 启动异常, 查看: $0 log"
    ;;
  stop)
    systemctl stop $UNIT 2>/dev/null && echo "[+] 已停止" || echo "[!] 未在运行"
    ;;
  restart)
    systemctl stop $UNIT 2>/dev/null; sleep 1
    exec "$0" start
    ;;
  status)
    echo "[状态] $(systemctl is-active $UNIT 2>/dev/null)"
    echo "[端口] $(ss -tln 2>/dev/null | grep ":$PORT" || echo 未监听)"
    ps -o pid,rss,%cpu,etime,cmd -C gd_server 2>/dev/null | head -3
    ;;
  log)
    journalctl -u $UNIT --no-pager -n "${2:-30}"
    ;;
  *)
    echo "用法: sudo $0 start|stop|restart|status|log [行数]"; exit 1
    ;;
esac
