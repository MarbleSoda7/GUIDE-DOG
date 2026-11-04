/*
 * guide_rk -- YOLOv5n detector for the guide-dog loop, in C.
 *
 * Reads the newest completed 800x480 BGR frame that rxfast published into
 * /dev/shm/rxfast, letterboxes it to 640x640 RGB, runs the int8 RKNN model on
 * the NPU, decodes the three yolov5 heads, does per-class NMS and sends the
 * boxes back to the FPGA as "GRD1" UDP datagrams.
 *
 * This is the same pipeline as rk_detect.py, with the same thresholds and the
 * same reply layout; the Python version stays as a fallback.  No OpenCV, no
 * numpy: the letterbox is ~30 lines and the post-process is the reference
 * yolov5 decode written out longhand, because the per-pixel work is trivial
 * next to the 70 ms the NPU needs anyway.
 *
 * Build (on the RK, needs librknnrt.so and rknn_api.h):
 *     gcc -O2 -o guide_rk guide_rk.c -lrknnrt -lm
 *
 * Run (root, after ./rxfast eth0 is up):
 *     sudo ./guide_rk --model /home/cat/guide_rknn_test/models/yolov5n_int8.rknn \
 *                     --anchors /home/cat/guide_rknn_test/anchors_yolov5.txt
 *
 * Offline math check on any host with gcc:
 *     gcc -O2 -DSELFTEST guide_rk.c -o t -lm && ./t
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

/* big-endian store, done by hand so the self-test needs no socket headers and
 * so it cannot collide with a libc htonl() pulled in indirectly */
static uint32_t be32(uint32_t v)
{
    return ((v & 0x000000FFu) << 24) | ((v & 0x0000FF00u) << 8) |
           ((v & 0x00FF0000u) >> 8)  | ((v & 0xFF000000u) >> 24);
}

#ifndef SELFTEST
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "rknn_api.h"
#endif

#define W            800
#define H            480
#define FRAME_BYTES  (W * H * 3)
#define NET          640
#define NET_CH       3
#define NET_BYTES    (NET * NET * NET_CH)
#define TOTAL_PKTS   827
#define SHM_PATH     "/dev/shm/rxfast"
#define SHM_MAGIC    0x52584654u
#define MAX_BOXES    20
#define NMS_THRESH   0.45f
#define OBJ_THRESH   0.25f
#define MAX_CAND     1024

/* reply layout, identical to rk_detect.py build_reply() */
#define REPLY_MAGIC  0x47524431u          /* "GRD1" */
#define REPLY_PORT   1235
#define FPGA_IP      "10.212.211.3"

/* shm offsets -- must match struct shm_hdr in rxfast.c */
#define OFF_MAGIC       0
#define OFF_SEQ         4
#define OFF_CUR         8
#define OFF_ACK        12
#define OFF_WANT       14
#define OFF_PKTS       16
#define OFF_FRAMES     20
#define OFF_RAW        24
#define OFF_BADMAC     28
#define OFF_BADLEN     32
#define OFF_BADTOTAL   36
#define OFF_TOTALPKT   40
#define OFF_FRAMEB     44
#define OFF_FID        56
#define OFF_DATA       64

struct box {
    int   cls;
    float score;
    float x0, y0, x1, y1;
};

/* ------------------------------------------------------------------ maths */

/* Letterbox 800x480 BGR -> 640x640 RGB, pad 114, PIL-compatible sampling.
 * Returns the scale factor r; dw/dh are the pads (dw is always 0 here). */
static float letterbox(const uint8_t *src, uint8_t *dst, int *pdw, int *pdh)
{
    const float r  = (NET / (float)H < NET / (float)W) ? (NET / (float)H)
                                                       : (NET / (float)W);
    const int   nw = (int)(W * r + 0.5f);
    const int   nh = (int)(H * r + 0.5f);
    const int   dw = (NET - nw) / 2;
    const int   dh = (NET - nh) / 2;
    const float sx = nw / (float)W;
    const float sy = nh / (float)H;
    int x, y;

    if (pdw) *pdw = dw;
    if (pdh) *pdh = dh;

    for (y = 0; y < NET; y++) {
        uint8_t *row = dst + (size_t)y * NET * NET_CH;
        if (y < dh || y >= dh + nh) {
            for (x = 0; x < NET; x++) {
                row[x * 3 + 0] = 114;
                row[x * 3 + 1] = 114;
                row[x * 3 + 2] = 114;
            }
            continue;
        }
        for (x = 0; x < NET; x++) {
            uint8_t *px = row + x * 3;
            float fx, fy, ax, ay, v0, v1, v2;
            int x0, x1, y0, y1, o00, o10, o01, o11;
            uint8_t *f00, *f10, *f01, *f11;

            if (x < dw || x >= dw + nw) {
                px[0] = px[1] = px[2] = 114;
                continue;
            }
            /* pixel-centre mapping, same convention PIL uses */
            fx = (x - dw + 0.5f) / sx - 0.5f;
            fy = (y - dh + 0.5f) / sy - 0.5f;
            if (fx < 0) fx = 0;
            if (fy < 0) fy = 0;
            x0 = (int)fx;
            y0 = (int)fy;
            if (x0 > W - 2) x0 = W - 2;
            if (y0 > H - 2) y0 = H - 2;
            x1 = x0 + 1;
            y1 = y0 + 1;
            ax = fx - x0;
            ay = fy - y0;

            o00 = (y0 * W + x0) * 3;
            o10 = (y0 * W + x1) * 3;
            o01 = (y1 * W + x0) * 3;
            o11 = (y1 * W + x1) * 3;
            f00 = (uint8_t *)src + o00;
            f10 = (uint8_t *)src + o10;
            f01 = (uint8_t *)src + o01;
            f11 = (uint8_t *)src + o11;

            /* BGR in, RGB out: sample channel c from source, store as 2-c */
            v0 = (1 - ax) * (1 - ay) * f00[2] + ax * (1 - ay) * f10[2] +
                 (1 - ax) * ay * f01[2] + ax * ay * f11[2];
            v1 = (1 - ax) * (1 - ay) * f00[1] + ax * (1 - ay) * f10[1] +
                 (1 - ax) * ay * f01[1] + ax * ay * f11[1];
            v2 = (1 - ax) * (1 - ay) * f00[0] + ax * (1 - ay) * f10[0] +
                 (1 - ax) * ay * f01[0] + ax * ay * f11[0];
            px[0] = (uint8_t)(v0 + 0.5f);
            px[1] = (uint8_t)(v1 + 0.5f);
            px[2] = (uint8_t)(v2 + 0.5f);
        }
    }
    return r;
}

/* One yolov5 head: data is [3][85][gh][gw] (channels-first per anchor).
 * Mirrors box_process()/confidence handling in rk_detect.py. */
static int decode_head(const float *d, int gh, int gw,
                       const float anchors[3][2], float thr,
                       struct box *out, int cap)
{
    const int   stride = NET / gh;
    const int   plane  = 85 * gh * gw;      /* floats per anchor */
    const int   area   = gh * gw;
    int a, i, j, n = 0;

    for (a = 0; a < 3; a++) {
        const float *base = d + a * plane;
        const float *px = base;
        const float *py = base + area;
        const float *pw = base + 2 * area;
        const float *ph = base + 3 * area;
        const float *po = base + 4 * area;
        const float *pc = base + 5 * area;  /* 80 class scores */

        for (i = 0; i < gh; i++) {
            for (j = 0; j < gw; j++) {
                int k = i * gw + j, c, best = -1;
                float bestv = 0.0f;
                float obj = po[k];
                float bx, by, bw, bh;

                if (obj <= 0.0f)
                    continue;
                for (c = 0; c < 80; c++) {
                    float v = pc[c * area + k];
                    if (v > bestv) { bestv = v; best = c; }
                }
                if (best < 0 || bestv * obj < thr)
                    continue;

                bx = (px[k] * 2 - 0.5f + j) * stride;
                by = (py[k] * 2 - 0.5f + i) * stride;
                bw = (pw[k] * 2) * (pw[k] * 2) * anchors[a][0];
                bh = (ph[k] * 2) * (ph[k] * 2) * anchors[a][1];
                if (bw <= 0.0f || bh <= 0.0f)
                    continue;
                if (n >= cap)
                    return n;
                out[n].cls   = best;
                out[n].score = bestv * obj;
                out[n].x0 = bx - bw * 0.5f;
                out[n].y0 = by - bh * 0.5f;
                out[n].x1 = bx + bw * 0.5f;
                out[n].y1 = by + bh * 0.5f;
                n++;
            }
        }
    }
    return n;
}

/* Same head, NHWC layout: data is [gh][gw][3][85], the three anchors inline.
 * Which of the two layouts the runtime hands us depends on attr.fmt, and a
 * wrong guess would not crash -- it would silently shift every box -- so
 * main() reads the real dims and picks; see layout_of(). */
static int decode_head_nhwc(const float *d, int gh, int gw,
                            const float anchors[3][2], float thr,
                            struct box *out, int cap)
{
    const int stride = NET / gh;
    int i, j, a, n = 0;

    for (i = 0; i < gh; i++) {
        for (j = 0; j < gw; j++) {
            const int cell = (i * gw + j) * 255;   /* 3 * 85 */
            for (a = 0; a < 3; a++) {
                const float *e = d + cell + a * 85;
                float obj = e[4], bestv = 0.0f, bx, by, bw, bh;
                int c, best = -1;

                if (obj <= 0.0f)
                    continue;
                for (c = 0; c < 80; c++)
                    if (e[5 + c] > bestv) { bestv = e[5 + c]; best = c; }
                if (best < 0 || bestv * obj < thr)
                    continue;
                bx = (e[0] * 2 - 0.5f + j) * stride;
                by = (e[1] * 2 - 0.5f + i) * stride;
                bw = (e[2] * 2) * (e[2] * 2) * anchors[a][0];
                bh = (e[3] * 2) * (e[3] * 2) * anchors[a][1];
                if (bw <= 0.0f || bh <= 0.0f)
                    continue;
                if (n >= cap)
                    return n;
                out[n].cls   = best;
                out[n].score = bestv * obj;
                out[n].x0 = bx - bw * 0.5f;
                out[n].y0 = by - bh * 0.5f;
                out[n].x1 = bx + bw * 0.5f;
                out[n].y1 = by + bh * 0.5f;
                n++;
            }
        }
    }
    return n;
}

static int cmp_score(const void *a, const void *b)
{
    float sa = ((const struct box *)a)->score;
    float sb = ((const struct box *)b)->score;
    return (sa < sb) - (sa > sb);
}

static float iou(const struct box *a, const struct box *b)
{
    float x0 = a->x0 > b->x0 ? a->x0 : b->x0;
    float y0 = a->y0 > b->y0 ? a->y0 : b->y0;
    float x1 = a->x1 < b->x1 ? a->x1 : b->x1;
    float y1 = a->y1 < b->y1 ? a->y1 : b->y1;
    float iw = x1 - x0, ih = y1 - y0, inter, ua;
    if (iw <= 0 || ih <= 0)
        return 0.0f;
    inter = iw * ih;
    ua = (a->x1 - a->x0) * (a->y1 - a->y0) +
         (b->x1 - b->x0) * (b->y1 - b->y0) - inter;
    return ua > 0 ? inter / ua : 0.0f;
}

/* Per-class greedy NMS in network space, then back to source pixels, clamp
 * and drop boxes too small to range.  NMS must run before the scale-back:
 * comparing a scaled box against an unscaled one gives a meaningless IoU. */
static int post_process(struct box *cand, int n, float r, int dw, int dh,
                        struct box *out, int cap)
{
    int i, j, m = 0, kept = 0;

    qsort(cand, (size_t)n, sizeof(struct box), cmp_score);
    for (i = 0; i < n && m < cap; i++) {
        int keep = 1;
        for (j = 0; j < m; j++) {
            if (out[j].cls != cand[i].cls)
                continue;
            if (iou(&out[j], &cand[i]) > NMS_THRESH) { keep = 0; break; }
        }
        if (!keep)
            continue;
        out[m++] = cand[i];
    }

    for (i = 0; i < m; i++) {
        struct box b = out[i];
        b.x0 = (b.x0 - dw) / r;
        b.x1 = (b.x1 - dw) / r;
        b.y0 = (b.y0 - dh) / r;
        b.y1 = (b.y1 - dh) / r;
        if (b.x0 < 0) b.x0 = 0;
        if (b.y0 < 0) b.y0 = 0;
        if (b.x1 > W - 1) b.x1 = W - 1;
        if (b.y1 > H - 1) b.y1 = H - 1;
        if (b.x1 - b.x0 < 8 || b.y1 - b.y0 < 8)
            continue;
        out[kept++] = b;
    }
    return kept;
}

/* ------------------------------------------------------------------ reply */
static int build_reply(uint8_t *buf, int fid, const struct box *b, int n)
{
    uint32_t magic = be32(REPLY_MAGIC);
    int i, off = 0;

    memcpy(buf, &magic, 4);
    buf[4] = (uint8_t)(fid >> 8);
    buf[5] = (uint8_t)(fid & 0xFF);
    buf[6] = (uint8_t)n;
    buf[7] = 0;
    off = 8;
    for (i = 0; i < n; i++) {
        uint16_t x0 = (uint16_t)b[i].x0, y0 = (uint16_t)b[i].y0;
        uint16_t x1 = (uint16_t)b[i].x1, y1 = (uint16_t)b[i].y1;
        buf[off + 0] = (uint8_t)b[i].cls;
        buf[off + 1] = (uint8_t)(int)(b[i].score * 100.0f + 0.5f);
        buf[off + 2] = (uint8_t)(x0 >> 8); buf[off + 3] = (uint8_t)x0;
        buf[off + 4] = (uint8_t)(y0 >> 8); buf[off + 5] = (uint8_t)y0;
        buf[off + 6] = (uint8_t)(x1 >> 8); buf[off + 7] = (uint8_t)x1;
        buf[off + 8] = (uint8_t)(y1 >> 8); buf[off + 9] = (uint8_t)y1;
        memset(buf + off + 10, 0, 6);
        off += 16;
    }
    return off;
}

const char *class_name(int c)
{
    static const char *N[] = {
        "person","bicycle","car","motorbike","aeroplane","bus","train","truck",
        "boat","traffic light","fire hydrant","stop sign","parking meter","bench",
        "bird","cat","dog","horse","sheep","cow","elephant","bear","zebra",
        "giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee",
        "skis","snowboard","sports ball","kite","baseball bat","baseball glove",
        "skateboard","surfboard","tennis racket","bottle","wine glass","cup",
        "fork","knife","spoon","bowl","banana","apple","sandwich","orange",
        "broccoli","carrot","hot dog","pizza","donut","cake","chair","sofa",
        "pottedplant","bed","diningtable","toilet","tvmonitor","laptop","mouse",
        "remote","keyboard","cell phone","microwave","oven","toaster","sink",
        "refrigerator","book","clock","vase","scissors","teddy bear",
        "hair drier","toothbrush"
    };
    return (c >= 0 && c < 80) ? N[c] : "?";
}

/* --------------------------------------------------------------- selftest */
#ifdef SELFTEST
int main(void)
{
    static uint8_t src[FRAME_BYTES], dst[NET_BYTES];
    int dw = -1, dh = -1, i;
    float r;

    /* constant BGR(10,20,30): bilinear of a constant is the constant, so the
     * image area must come out exactly RGB(30,20,10) and the pads 114. */
    for (i = 0; i < FRAME_BYTES; i += 3) {
        src[i + 0] = 10;
        src[i + 1] = 20;
        src[i + 2] = 30;
    }

    r = letterbox(src, dst, &dw, &dh);
    printf("letterbox r=%.4f dw=%d dh=%d\n", r, dw, dh);
    if (dw != 0 || dh != 128) { printf("FAIL pad\n"); return 1; }
    if (fabsf(r - 0.8f) > 1e-4) { printf("FAIL r\n"); return 1; }

    for (i = 0; i < NET * 3; i++)
        if (dst[i] != 114) { printf("FAIL pad fill at %d\n", i); return 1; }
    for (i = (NET - 1) * NET * 3; i < NET * NET * 3; i++)
        if (dst[i] != 114) { printf("FAIL bottom pad at %d\n", i); return 1; }

    {
        const uint8_t *top = dst + (128 * NET + 0) * 3;
        const uint8_t *bot = dst + ((128 + 384 - 1) * NET + 639) * 3;
        if (top[0] != 30 || top[1] != 20 || top[2] != 10) {
            printf("FAIL bgr->rgb top: %d %d %d\n", top[0], top[1], top[2]);
            return 1;
        }
        if (bot[0] != 30 || bot[1] != 20 || bot[2] != 10) {
            printf("FAIL bgr->rgb bottom: %d %d %d\n", bot[0], bot[1], bot[2]);
            return 1;
        }
    }

    /* decode: single hot cell at grid (40,40), 80x80 head, anchors[0]=(10,13) */
    {
        enum { GH = 80 };
        enum { AREA = GH * GH, PLANE = 85 * GH * GH };
        static float head[3 * PLANE];
        struct box cand[MAX_CAND], out[MAX_BOXES];
        float anchors[3][2] = {{10, 13}, {16, 30}, {33, 23}};
        int n, m, k;
        float cx, cy, bw, bh;

        memset(head, 0, sizeof(head));
        k = (40 * GH + 40);                   /* cell under test            */
        head[0 * AREA + k] = 0.75f;           /* (0.75*2-0.5)=1.0 -> col+41 */
        head[1 * AREA + k] = 0.75f;
        head[2 * AREA + k] = 0.90f;           /* (1.8)^2*10 = 32.4          */
        head[3 * AREA + k] = 0.90f;           /* (1.8)^2*13 = 42.12         */
        head[4 * AREA + k] = 0.90f;           /* obj                        */
        head[5 * AREA + k] = 0.80f;           /* class 0                    */

        n = decode_head(head, GH, GH, anchors, OBJ_THRESH, cand, MAX_CAND);
        if (n != 1) { printf("FAIL decode count %d\n", n); return 1; }
        cx = (cand[0].x0 + cand[0].x1) * 0.5f;
        cy = (cand[0].y0 + cand[0].y1) * 0.5f;
        bw = cand[0].x1 - cand[0].x0;
        bh = cand[0].y1 - cand[0].y0;
        printf("decode score=%.3f centre=(%.2f,%.2f) wh=(%.2f,%.2f)\n",
               cand[0].score, cx, cy, bw, bh);
        if (fabsf(cand[0].score - 0.72f) > 0.005f) { printf("FAIL score\n"); return 1; }
        if (fabsf(cx - 328.f) > 0.01f || fabsf(cy - 328.f) > 0.01f) {
            printf("FAIL centre\n"); return 1;
        }
        if (fabsf(bw - 32.4f) > 0.02f || fabsf(bh - 42.12f) > 0.02f) {
            printf("FAIL wh\n"); return 1;
        }

        /* the same cell expressed channels-last: [gh][gw][3][85].  Both
         * decoders must agree, otherwise picking the wrong one at runtime
         * would pass silently and just shift every box. */
        {
            enum { NC = 80 * 80 * 255 };      /* 3 * 85 per cell */
            static float nl[NC];
            int cell = (40 * 80 + 40) * 255;
            int nn;

            memset(nl, 0, sizeof(nl));
            nl[cell + 0] = 0.75f;
            nl[cell + 1] = 0.75f;
            nl[cell + 2] = 0.90f;
            nl[cell + 3] = 0.90f;
            nl[cell + 4] = 0.90f;
            nl[cell + 5] = 0.80f;
            nn = decode_head_nhwc(nl, 80, 80, anchors, OBJ_THRESH, cand, MAX_CAND);
            if (nn != 1) { printf("FAIL nhwc count %d\n", nn); return 1; }
            if (fabsf(cand[0].score - 0.72f) > 0.005f) {
                printf("FAIL nhwc score\n"); return 1;
            }
            if (fabsf((cand[0].x0 + cand[0].x1) * 0.5f - 328.f) > 0.01f ||
                fabsf((cand[0].y0 + cand[0].y1) * 0.5f - 328.f) > 0.01f) {
                printf("FAIL nhwc centre\n"); return 1;
            }
            if (fabsf(cand[0].x1 - cand[0].x0 - 32.4f) > 0.02f ||
                fabsf(cand[0].y1 - cand[0].y0 - 42.12f) > 0.02f) {
                printf("FAIL nhwc wh\n"); return 1;
            }
            printf("nhwc decode agrees: n=%d score=%.3f\n", nn, cand[0].score);
        }

        /* NMS: same class overlapping -> one survives; other class -> kept */
        cand[0].score = 0.90f; cand[0].cls = 0;
        cand[0].x0 = 100; cand[0].y0 = 100; cand[0].x1 = 300; cand[0].y1 = 400;
        cand[1] = cand[0];
        cand[1].score = 0.80f;
        cand[1].x0 += 5; cand[1].y0 += 2; cand[1].x1 -= 2; cand[1].y1 -= 4;
        cand[2] = cand[0];
        cand[2].score = 0.70f;
        cand[2].cls = 56;
        m = post_process(cand, 3, 1.0f, 0, 0, out, MAX_BOXES);
        printf("post n=%d (expect 2: person + chair)\n", m);
        if (m != 2) { printf("FAIL nms\n"); return 1; }
        if (out[0].cls != 0 || out[1].cls != 56) { printf("FAIL nms order\n"); return 1; }

        /* scale-back: r=0.8, dh=128 -> y (0..639) maps to the 480-line frame */
        cand[0].x0 = 0; cand[0].y0 = 128; cand[0].x1 = 640; cand[0].y1 = 511;
        m = post_process(cand, 1, 0.8f, 0, 128, out, MAX_BOXES);
        printf("scaleback box=(%.1f,%.1f)-(%.1f,%.1f)\n",
               out[0].x0, out[0].y0, out[0].x1, out[0].y1);
        if (m != 1) { printf("FAIL scaleback count\n"); return 1; }
        if (fabsf(out[0].x1 - 799.f) > 0.6f) { printf("FAIL scaleback x1\n"); return 1; }
        if (fabsf(out[0].y0 - 0.f) > 0.6f) { printf("FAIL scaleback y0\n"); return 1; }
        if (fabsf(out[0].y1 - 478.75f) > 0.05f) { printf("FAIL scaleback y1\n"); return 1; }
    }

    {
        uint8_t reply[256];
        int len = build_reply(reply, 0x1234, (struct box[]){{3, 0.75f, 1, 2, 3, 4}}, 1);
        printf("reply len=%d magic=%02x%02x%02x%02x fid=%02x%02x n=%d\n",
               len, reply[0], reply[1], reply[2], reply[3], reply[4], reply[5], reply[6]);
        if (len != 8 + 16) { printf("FAIL reply len\n"); return 1; }
        if (memcmp(reply, "GRD1", 4) != 0) { printf("FAIL reply magic\n"); return 1; }
        if (reply[4] != 0x12 || reply[5] != 0x34) { printf("FAIL reply fid\n"); return 1; }
        if (reply[8] != 3 || reply[9] != 75) { printf("FAIL reply box\n"); return 1; }
    }

    printf("SELFTEST OK\n");
    return 0;
}
#else
/* ------------------------------------------------------------- live path */
static volatile sig_atomic_t stop_flag;

static void on_sig(int sig) { (void)sig; stop_flag = 1; }

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static uint32_t rd32(const uint8_t *p, int off)
{
    uint32_t v;
    memcpy(&v, p + off, 4);
    return v;
}

int main(int argc, char **argv)
{
    const char *model = "/home/cat/guide_rknn_test/models/yolov5n_int8.rknn";
    const char *anchors_path = "/home/cat/guide_rknn_test/anchors_yolov5.txt";
    const char *shm_path = SHM_PATH;
    static uint8_t net_in[NET_BYTES];
    static uint8_t frame[FRAME_BYTES];
    static struct box cand[MAX_CAND], out[MAX_BOXES];
    float anchors[3][3][2];
    uint8_t *shm = NULL, reply[8 + MAX_BOXES * 16];
    rknn_context ctx = 0;
    int shmfd, sock, i, last_seq = 0, fid = 0, attrs_dumped = 0, nout = 0;
    uint32_t seen;

    setvbuf(stdout, NULL, _IOLBF, 0);

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--model") && i + 1 < argc) model = argv[++i];
        else if (!strcmp(argv[i], "--anchors") && i + 1 < argc) anchors_path = argv[++i];
        else if (!strcmp(argv[i], "--shm") && i + 1 < argc) shm_path = argv[++i];
        else { fprintf(stderr, "unknown arg %s\n", argv[i]); return 1; }
    }

    /* anchors: 18 floats, [head][anchor][w,h] */
    {
        FILE *f = fopen(anchors_path, "r");
        if (!f) { perror(anchors_path); return 1; }
        for (i = 0; i < 18; i++)
            if (fscanf(f, "%f", &anchors[i / 6][(i % 6) / 2][i % 2]) != 1) {
                fprintf(stderr, "%s: bad float at %d\n", anchors_path, i);
                return 1;
            }
        fclose(f);
    }

    /* load model into memory, then let RKNN own it */
    {
        FILE *f = fopen(model, "rb");
        long len;
        void *buf;
        if (!f) { perror(model); return 1; }
        fseek(f, 0, SEEK_END);
        len = ftell(f);
        fseek(f, 0, SEEK_SET);
        buf = malloc((size_t)len);
        if (!buf || fread(buf, 1, (size_t)len, f) != (size_t)len) {
            fprintf(stderr, "%s: short read\n", model);
            return 1;
        }
        fclose(f);
        if (rknn_init(&ctx, buf, (uint32_t)len, 0, NULL) != 0) {
            fprintf(stderr, "rknn_init failed\n");
            return 1;
        }
        free(buf);
        printf("model %s\n", model);
    }

    {
        rknn_sdk_version ver;
        if (rknn_query(ctx, RKNN_QUERY_SDK_VERSION, &ver, sizeof(ver)) == 0)
            printf("rknn sdk %s driver %s\n", ver.api_version, ver.drv_version);
        else
            printf("rknn sdk version query failed (header/runtime mismatch?)\n");
    }
    {
        rknn_input_output_num io;
        if (rknn_query(ctx, RKNN_QUERY_IN_OUT_NUM, &io, sizeof(io)) != 0) {
            fprintf(stderr, "rknn_query IO_NUM failed\n");
            return 1;
        }
        if (io.n_input != 1) {
            fprintf(stderr, "expected one input, model has %u\n", io.n_input);
            return 1;
        }
        nout = (int)io.n_output;
        if (nout > 8) nout = 8;
        printf("io: in=%u out=%u (decoding %d)\n", io.n_input, io.n_output, nout);
        if (nout < 3)
            fprintf(stderr, "WARN: only %d output(s); a yolov5 model has 3 heads\n",
                    nout);
    }

    /* Wait for rxfast to publish rather than requiring a fixed start order:
     * the file may exist with the header not yet written, so retry the whole
     * open/mmap/magic sequence, not just open(). */
    shm = NULL;
    for (i = 0; i < 50 && !shm; i++) {
        struct stat st;
        void *m;
        shmfd = open(shm_path, O_RDWR);
        if (shmfd < 0) { usleep(100000); continue; }
        if (fstat(shmfd, &st) != 0 ||
            st.st_size < (off_t)(OFF_DATA + 2 * FRAME_BYTES)) {
            close(shmfd);
            usleep(100000);
            continue;
        }
        m = mmap(NULL, (size_t)st.st_size, PROT_READ | PROT_WRITE,
                 MAP_SHARED, shmfd, 0);
        if (m == MAP_FAILED) {
            close(shmfd);
            usleep(100000);
            continue;
        }
        if (rd32((const uint8_t *)m, OFF_MAGIC) == SHM_MAGIC)
            shm = (uint8_t *)m;
        else {
            munmap(m, (size_t)st.st_size);
            close(shmfd);
            usleep(100000);
        }
    }
    if (!shm) {
        fprintf(stderr, "%s: rxfast is not publishing (waited 5 s)\n", shm_path);
        return 1;
    }
    if ((int)rd32(shm, OFF_FRAMEB) != FRAME_BYTES ||
        (int)rd32(shm, OFF_TOTALPKT) != TOTAL_PKTS) {
        fprintf(stderr, "%s: geometry mismatch (frame=%u pkts=%u, want %d/%d)\n",
                shm_path, rd32(shm, OFF_FRAMEB), rd32(shm, OFF_TOTALPKT),
                FRAME_BYTES, TOTAL_PKTS);
        return 1;
    }
    /* gate on completed frames, not on raw packets: raw climbs 827 times per
     * frame, which would spin this loop hot between publishes */
    seen = rd32(shm, OFF_FRAMES);

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { perror("socket"); return 1; }
    {
        struct sockaddr_in dst;
        memset(&dst, 0, sizeof(dst));
        dst.sin_family = AF_INET;
        dst.sin_port = htons(REPLY_PORT);
        if (inet_pton(AF_INET, FPGA_IP, &dst.sin_addr) != 1) {
            fprintf(stderr, "bad FPGA_IP\n");
            return 1;
        }
        if (connect(sock, (struct sockaddr *)&dst, sizeof(dst)) != 0)
            perror("connect (continuing)");
    }

    signal(SIGINT, on_sig);
    signal(SIGTERM, on_sig);

    printf("guide_rk: waiting for frames from %s (already %u)\n",
           shm_path, rd32(shm, OFF_FRAMES));

    while (!stop_flag) {
        double t0 = 0, t1 = 0, t2 = 0, t2b = 0, t3 = 0;
        int sidx;
        uint32_t seq, nframes;
        int nb, rc;
        rknn_input inputs[1];
        rknn_output outputs[8];

        nframes = rd32(shm, OFF_FRAMES);
        if (nframes < seen)
            seen = nframes;             /* rxfast restarted and zeroed the shm */
        if (nframes == seen) { usleep(2000); continue; }
        /* seen is bumped only once the frame is actually in hand: updating it
         * here would drop the frame for good if we hit the writer mid-publish */

        t0 = now_ms();
        seq = rd32(shm, OFF_SEQ);
        if (seq & 1u) { usleep(500); continue; }    /* producer writing; retry */
        if ((int)seq == last_seq) { seen = nframes; continue; }
        sidx = (int)rd32(shm, OFF_CUR);
        if (sidx < 0 || sidx > 1) { seen = nframes; continue; }
        fid = (int)rd32(shm, OFF_FID + 4 * sidx);
        memcpy(frame, shm + OFF_DATA + (size_t)sidx * FRAME_BYTES, FRAME_BYTES);
        if (rd32(shm, OFF_SEQ) != seq)
            continue;                       /* torn read, drop this round */
        last_seq = (int)seq;
        seen = nframes;

        {
            int dw, dh;
            float r = letterbox(frame, net_in, &dw, &dh);
            t1 = now_ms();

            memset(inputs, 0, sizeof(inputs));
            inputs[0].index = 0;
            inputs[0].type = RKNN_TENSOR_UINT8;
            inputs[0].fmt = RKNN_TENSOR_NHWC;
            inputs[0].size = NET_BYTES;
            inputs[0].buf = net_in;
            inputs[0].pass_through = 0;
            if (rknn_inputs_set(ctx, 1, inputs) != 0) { fprintf(stderr, "inputs_set failed\n"); break; }
            if (rknn_run(ctx, NULL) != 0) { fprintf(stderr, "rknn_run failed\n"); break; }
            t2 = now_ms();

            memset(outputs, 0, sizeof(outputs));
            for (i = 0; i < nout; i++) {
                outputs[i].index = i;
                outputs[i].want_float = 1;
            }
            rc = rknn_outputs_get(ctx, (uint32_t)nout, outputs, NULL);
            if (rc != 0) { fprintf(stderr, "outputs_get failed %d\n", rc); break; }
            t2b = now_ms();

            nb = 0;
            for (i = 0; i < nout; i++) {
                rknn_tensor_attr attr;
                uint32_t d1, d2, d3, d4;
                int gh = 0, gw = 0, nhwc = -1, n, hidx, k;

                memset(&attr, 0, sizeof(attr));
                attr.index = (uint32_t)i;
                if (rknn_query(ctx, RKNN_QUERY_OUTPUT_ATTR, &attr, sizeof(attr)) != 0)
                    continue;

                d1 = (attr.n_dims > 1) ? attr.dims[1] : 0;
                d2 = (attr.n_dims > 2) ? attr.dims[2] : 0;
                d3 = (attr.n_dims > 3) ? attr.dims[3] : 0;
                d4 = (attr.n_dims > 4) ? attr.dims[4] : 0;

                /* The converter decides this, so read it back instead of
                 * assuming: [1,3,85,gh,gw] / [1,255,gh,gw] are channels-first,
                 * [1,gh,gw,3,85] / [1,gh,gw,255] are channels-last.  Guessing
                 * wrong would not crash, it would shift every box. */
                if (d1 == 3 && d2 == 85)      { gh = (int)d3; gw = (int)d4; nhwc = 0; }
                else if (d1 == 255)           { gh = (int)d2; gw = (int)d3; nhwc = 0; }
                else if (d3 == 3 && d4 == 85) { gh = (int)d1; gw = (int)d2; nhwc = 1; }
                else if (d3 == 255)           { gh = (int)d1; gw = (int)d2; nhwc = 1; }

                /* dump every head once, so a wrong layout is obvious on line 1 */
                if (attrs_dumped < nout) {
                    printf("out[%d] dims=", i);
                    for (k = 0; k < (int)attr.n_dims; k++)
                        printf("%s%u", k ? "," : "", attr.dims[k]);
                    printf(" fmt=%d type=%d n_elems=%u -> ",
                           (int)attr.fmt, (int)attr.type, attr.n_elems);
                    if (gh > 0)
                        printf("gh=%d gw=%d %s\n", gh, gw, nhwc ? "NHWC" : "NCHW");
                    else
                        printf("UNRECOGNISED (skipped)\n");
                    attrs_dumped++;
                }
                if (gh <= 0)
                    continue;

                /* pick the anchor set by grid size, not by output order --
                 * the converter is free to reorder the three heads */
                hidx = (gh == 80) ? 0 : (gh == 40) ? 1 : (gh == 20) ? 2 : -1;
                if (hidx < 0)
                    continue;
                if (attr.n_elems < (uint32_t)(85 * gh * gw) * 3u)
                    continue;

                if (nhwc)
                    n = decode_head_nhwc((const float *)outputs[i].buf, gh, gw,
                                         (const float (*)[2])anchors[hidx],
                                         OBJ_THRESH, cand + nb, MAX_CAND - nb);
                else
                    n = decode_head((const float *)outputs[i].buf, gh, gw,
                                    (const float (*)[2])anchors[hidx],
                                    OBJ_THRESH, cand + nb, MAX_CAND - nb);
                nb += n;
                if (nb >= MAX_CAND) break;
            }
            rknn_outputs_release(ctx, (uint32_t)nout, outputs);

            nb = post_process(cand, nb, r, dw, dh, out, MAX_BOXES);
            t3 = now_ms();
        }

        {
            int len = build_reply(reply, fid, out, nb);
            if (send(sock, reply, (size_t)len, 0) < 0)
                perror("send");
            printf("fid=%-6d det=%-2d prep=%.1f infer=%.1f getout=%.1f "
                   "post=%.1f loop=%.1fms ",
                   fid, nb, t1 - t0, t2 - t1, t2b - t2, t3 - t2b, t3 - t0);
            for (i = 0; i < nb && i < 6; i++)
                printf("%s %.2f (%d,%d)-(%d,%d) ", class_name(out[i].cls),
                       out[i].score, (int)out[i].x0, (int)out[i].y0,
                       (int)out[i].x1, (int)out[i].y1);
            printf("\n");
        }
    }

    rknn_destroy(ctx);
    close(sock);
    return 0;
}
#endif
