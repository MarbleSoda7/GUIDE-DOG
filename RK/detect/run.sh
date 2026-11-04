#!/bin/sh
# Bring up the C pipeline on the RK3568:
#
#   rxfast   -- root, AF_PACKET: eats the 12.7k pkt/s stream and republishes
#               whole frames through /dev/shm/rxfast
#   guide_rk -- mmaps the newest frame, runs RKNN, sends "GRD1" back to the PL
#
# Must run as root (AF_PACKET + the neighbour entry).  Ctrl-C stops both.
#
#   sudo ./run.sh
#   MODEL=/path/to/other.rknn IFACE=eth1 sudo ./run.sh
cd "$(dirname "$0")" || exit 1

IFACE=${IFACE:-eth0}
FPGA_IP=${FPGA_IP:-10.212.211.3}
FPGA_MAC=${FPGA_MAC:-12:34:56:78:9a:bc}
MODEL=${MODEL:-/home/cat/guide_rknn_test/models/yolov5n_int8.rknn}
ANCHORS=${ANCHORS:-/home/cat/guide_rknn_test/anchors_yolov5.txt}

if [ "$(id -u)" != "0" ]; then
    echo "run.sh: must be root (AF_PACKET): sudo ./run.sh"
    exit 1
fi
for f in rxfast guide_rk; do
    if [ ! -x "./$f" ]; then
        echo "run.sh: ./$f missing -- run ./build.sh first"
        exit 1
    fi
done
if [ ! -f "$MODEL" ]; then
    echo "run.sh: model not found: $MODEL"
    exit 1
fi

# The PL's udp_rx accepts frames but never answers ARP.  Without this pinned
# entry every reply sits in the kernel neighbour queue and never hits the wire
# -- sendto() still returns success, which is exactly what made it look like
# the FPGA was dropping packets.  This one line is the whole fix.
ip neigh replace "$FPGA_IP" lladdr "$FPGA_MAC" dev "$IFACE" nud permanent
echo "neigh:"; ip neigh show "$FPGA_IP"

# Only one receiver may answer, or the PL gets two replies per frame.
# -x matches the executable name exactly; the earlier pattern used $(pwd)/rxfast
# but the process is started as ./rxfast, so that never matched anything.
pkill -f 'rk_detect\.py' 2>/dev/null
pkill -x rxfast 2>/dev/null
pkill -x guide_rk 2>/dev/null
sleep 0.3

./rxfast "$IFACE" &
RX=$!
sleep 0.5

if ! kill -0 "$RX" 2>/dev/null; then
    echo "run.sh: rxfast died on start-up (wrong iface?)"
    exit 1
fi

# rxfast is killed when this shell exits, including Ctrl-C on guide_rk.
trap 'kill $RX 2>/dev/null' EXIT INT TERM

./guide_rk --model "$MODEL" --anchors "$ANCHORS"
