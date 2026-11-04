#!/bin/bash
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

# Build the receiver from the source shipped beside this script. Do not kill
# arbitrary processes: deployment only compiles and reports the output path.
if [ ! -f rk_frame_recv.cpp ]; then
    echo "missing $SCRIPT_DIR/rk_frame_recv.cpp" >&2
    exit 1
fi
g++ -O2 -Wall -Wextra -pthread -o frame_recv_stereo rk_frame_recv.cpp \
    -lopencv_core -lopencv_imgproc -lopencv_highgui -lopencv_imgcodecs
echo "receiver_build=ok output=$SCRIPT_DIR/frame_recv_stereo"

# A sender is optional and is built only when that source exists.
if [ -f frame_send.cpp ]; then
    g++ -O2 -Wall -Wextra -pthread -o frame_send frame_send.cpp \
        -lopencv_core -lopencv_imgproc -lopencv_imgcodecs
    echo "sender_build=ok output=$SCRIPT_DIR/frame_send"
else
    echo "sender_build=skipped (frame_send.cpp not present)"
fi

echo "--- verify stereo receiver markers ---"
grep -c "ZYNQ STEREO" rk_frame_recv.cpp
grep -c "PKT_MAGIC0" rk_frame_recv.cpp
