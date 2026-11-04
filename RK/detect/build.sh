#!/bin/sh
# Build the two C pieces on the RK3568 (or any Linux host, for the maths test).
#
#   ./build.sh          full build: rxfast + guide_rk
#   ./build.sh test     maths self-test only (no rknn runtime, no root needed)
#
# Everything is plain C99 + librknnrt. gcc on the board is enough.
set -e
CC=${CC:-gcc}
CFLAGS=${CFLAGS:--O2 -Wall -std=gnu99}

echo "== self-test: letterbox / decode / NMS / reply =="
$CC $CFLAGS -DSELFTEST guide_rk.c -o t_guide -lm
./t_guide
rm -f t_guide

if [ "$1" = "test" ]; then
    exit 0
fi

echo "== rxfast (packet reassembler) =="
$CC $CFLAGS -o rxfast rxfast.c

echo "== locating librknnrt.so =="
RKNN_LIB=""
RKNN_INC=""
for c in /usr/lib/librknnrt.so \
         /usr/lib/aarch64-linux-gnu/librknnrt.so \
         /usr/local/lib/librknnrt.so; do
    if [ -f "$c" ]; then RKNN_LIB=$c; break; fi
done
if [ -z "$RKNN_LIB" ]; then
    # the rknn-toolkit-lite2 wheel ships the runtime inside site-packages
    RKNN_LIB=$(find /usr /opt /home -name librknnrt.so 2>/dev/null | head -1)
fi
if [ -z "$RKNN_LIB" ]; then
    echo "ERROR: librknnrt.so not found."
    echo "       pip3 install rknn-toolkit-lite2   (or copy it into /usr/lib)"
    exit 1
fi
echo "   using $RKNN_LIB"

if [ ! -f rknn_api.h ]; then
    # The header's struct layout has to match /usr/lib/librknnrt.so, so prefer
    # whatever the board already builds against over a copy from elsewhere.
    for d in /home/cat/plate-detect-latest/includes/rknn \
             /home/cat/guide_rknn_test/include; do
        if [ -f "$d/rknn_api.h" ]; then
            RKNN_INC="-I$d"
            echo "   header: $d/rknn_api.h"
            break
        fi
    done
    if [ -z "$RKNN_INC" ]; then
        echo "ERROR: no rknn_api.h found next to the sources or on the board"
        exit 1
    fi
fi

echo "== guide_rk (RKNN detector) =="
$CC $CFLAGS $RKNN_INC -o guide_rk guide_rk.c "$RKNN_LIB" -lm

echo
echo "built: rxfast, guide_rk"
echo "next:  sudo ./run.sh"
