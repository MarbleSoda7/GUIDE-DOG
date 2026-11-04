/*
 * rxfast -- reassemble the 800x480 BGR frames that the Zynq PL streams over
 * UDP (827 packets of 1394 payload bytes each) and publish the newest one to
 * a shared-memory slot that the Python detector mmaps.
 *
 * Why this exists: at 15 fps the wire carries ~12.7k packets/s.  Doing that
 * in pure Python costs four copies per packet plus interpreter overhead per
 * field, and the loop collapses to well under one frame per second.  Here the
 * hot path is recvmmsg() in batches of 64 plus one memcpy of the payload --
 * no allocation, no syscall per packet.
 *
 * Build:
 *     gcc -O2 -o rxfast rxfast.c
 * Run (root, AF_PACKET):
 *     sudo ./rxfast eth0
 *
 * Shared memory layout (/dev/shm/rxfast), little endian, offsets in bytes:
 *     0   u32 magic        0x52584654 "RXFT"
 *     4   u32 seq          even = stable, odd = producer is writing
 *     8   u32 cur          index of the slot holding the newest frame
 *     12  u16 ack          frame id the FPGA already accepted
 *     14  u16 want         frame id the FPGA is asking to re-send
 *     16  u32 pkts         packets accepted into a frame
 *     20  u32 frames       frames completed
 *     24  u32 raw          packets read from the socket
 *     28  u32 bad_mac
 *     32  u32 bad_len      short/ethertype/IP-proto/length rejects
 *     36  u32 bad_total
 *     40  u32 total_pkts   827
 *     44  u32 frame_bytes  1152000
 *     48  u32 w            800
 *     52  u32 h            480
 *     56  u32 fid[2]
 *     64  u8  data[2][frame_bytes]
 *
 * The producer publishes with a seqlock (seq odd while writing); the reader
 * copies the slot out and re-checks seq, retrying on a torn read.  A frame is
 * ~1.15 MB, so the copy costs ~0.2 ms while the producer only touches a slot
 * every ~65 ms -- collisions are rare and always detected.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>

#define W            800
#define H            480
#define FRAME_BYTES  (W * H * 3)
#define TOTAL_PKTS   827
#define DATA_PER_PKT 1394
#define HDR          10
#define NSLOT        2
#define NBUF         4          /* frames in flight */
#define BATCH        64         /* recvmmsg batch */
#define PKT_BUF      2048
#define SHM_PATH     "/dev/shm/rxfast"
#define MAGIC        0x52584654u

static const uint8_t FPGA_MAC[6] = {0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc};

struct shm_hdr {
    volatile uint32_t magic;
    volatile uint32_t seq;
    volatile uint32_t cur;
    volatile uint16_t ack;
    volatile uint16_t want;
    volatile uint32_t pkts;
    volatile uint32_t frames;
    volatile uint32_t raw;
    volatile uint32_t bad_mac;
    volatile uint32_t bad_len;
    volatile uint32_t bad_total;
    volatile uint32_t total_pkts;
    volatile uint32_t frame_bytes;
    volatile uint32_t w;
    volatile uint32_t h;
    volatile uint32_t fid[NSLOT];
    uint8_t data[NSLOT][FRAME_BYTES];
};

/* Assembly buffer.  NBUF of them is plenty: at most two frames are ever in
 * flight, a frame takes ~65 ms to arrive. */
struct aslot {
    int      used;
    int      fid;
    int      n;
    uint64_t touch;
    uint8_t  got[(TOTAL_PKTS + 7) / 8];
    uint8_t  data[FRAME_BYTES];
};

static struct aslot aslots[NBUF];
static struct shm_hdr *shm;
static volatile sig_atomic_t stop_flag;
static int last_pub = -1;
static uint64_t tick;

static void on_sig(int sig)
{
    (void)sig;
    stop_flag = 1;
}

static void publish(struct aslot *s)
{
    int d = (last_pub < 0) ? 0 : (1 - last_pub);

    shm->seq++;                 /* odd: writing            */
    __sync_synchronize();
    memcpy(shm->data[d], s->data, FRAME_BYTES);
    shm->fid[d] = (uint32_t)s->fid;
    shm->cur = (uint32_t)d;
    __sync_synchronize();
    shm->seq++;                 /* even: stable            */
    shm->frames++;
    last_pub = d;
}

static struct aslot *slot_for(int fid)
{
    int i, victim = 0;

    for (i = 0; i < NBUF; i++)
        if (aslots[i].used && aslots[i].fid == fid)
            return &aslots[i];
    for (i = 0; i < NBUF; i++) {
        if (!aslots[i].used) {
            victim = i;
            goto take;
        }
        if (aslots[i].touch < aslots[victim].touch)
            victim = i;
    }
take:
    aslots[victim].used = 1;
    aslots[victim].fid = fid;
    aslots[victim].n = 0;
    memset(aslots[victim].got, 0, sizeof(aslots[victim].got));
    return &aslots[victim];
}

static void handle_packet(const uint8_t *r, int len)
{
    const uint8_t *p;
    struct aslot *s;
    int iplen, plen, fid, total, idx, off, cnt;

    shm->raw++;
    if (len < 42)                { shm->bad_len++;   return; }
    if (memcmp(r + 6, FPGA_MAC, 6)) { shm->bad_mac++; return; }
    if (r[12] != 0x08 || r[13] != 0x00) { shm->bad_len++; return; }   /* IPv4 */
    if (r[23] != 17)             { shm->bad_len++;   return; }        /* UDP  */

    iplen = (r[16] << 8) | r[17];
    plen  = iplen - 28;                       /* minus IP + UDP header */
    if (plen < HDR || 42 + plen > len) { shm->bad_len++; return; }

    p     = r + 42;
    shm->ack  = (uint16_t)((p[0] << 8) | p[1]);
    shm->want = (uint16_t)((p[2] << 8) | p[3]);
    fid   = (p[4] << 8) | p[5];
    total = (p[6] << 8) | p[7];
    idx   = (p[8] << 8) | p[9];

    if (total != TOTAL_PKTS || idx >= TOTAL_PKTS) { shm->bad_total++; return; }

    s = slot_for(fid);
    s->touch = ++tick;

    if (s->got[idx >> 3] & (1u << (idx & 7)))
        return;                               /* duplicate */
    s->got[idx >> 3] |= (uint8_t)(1u << (idx & 7));
    shm->pkts++;                              /* distinct packets stored */

    off = idx * DATA_PER_PKT;
    cnt = plen - HDR;
    if (cnt > FRAME_BYTES - off)
        cnt = FRAME_BYTES - off;
    memcpy(s->data + off, p + HDR, (size_t)cnt);
    s->n++;

    if (s->n == TOTAL_PKTS) {
        publish(s);
        s->used = 0;
    }
}

int main(int argc, char **argv)
{
    const char *ifname = (argc > 1) ? argv[1] : "eth0";
    struct sockaddr_ll sll;
    struct mmsghdr mmsg[BATCH];
    struct iovec iov[BATCH];
    uint8_t *bufs[BATCH];
    int fd, shmfd, i, rcvbuf = 32 * 1024 * 1024;
    size_t shm_size = sizeof(struct shm_hdr);

    setvbuf(stdout, NULL, _IOLBF, 0);

    shmfd = open(SHM_PATH, O_RDWR | O_CREAT | O_TRUNC, 0666);
    if (shmfd < 0) { perror("open " SHM_PATH); return 1; }
    if (ftruncate(shmfd, (off_t)shm_size) != 0) { perror("ftruncate"); return 1; }
    shm = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);
    if (shm == MAP_FAILED) { perror("mmap"); return 1; }
    memset((void *)shm, 0, shm_size);
    shm->total_pkts  = TOTAL_PKTS;
    shm->frame_bytes = FRAME_BYTES;
    shm->w = W;
    shm->h = H;
    __sync_synchronize();
    shm->magic = MAGIC;

    fd = socket(AF_PACKET, SOCK_RAW | SOCK_CLOEXEC, htons(ETH_P_ALL));
    if (fd < 0) { perror("socket(AF_PACKET)"); return 1; }
    if (setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf)) != 0)
        perror("SO_RCVBUF (continuing)");

    memset(&sll, 0, sizeof(sll));
    sll.sll_family   = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex  = (int)if_nametoindex(ifname);
    if (sll.sll_ifindex == 0) { fprintf(stderr, "no such iface: %s\n", ifname); return 1; }
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) != 0) { perror("bind"); return 1; }

    for (i = 0; i < BATCH; i++) {
        bufs[i] = malloc(PKT_BUF);
        if (!bufs[i]) { perror("malloc"); return 1; }
        iov[i].iov_base = bufs[i];
        iov[i].iov_len  = PKT_BUF;
    }

    signal(SIGINT, on_sig);
    signal(SIGTERM, on_sig);

    printf("rxfast: %s -> %s  frame=%d B  %d pkt/frame  shm=%zu B\n",
           ifname, SHM_PATH, FRAME_BYTES, TOTAL_PKTS, shm_size);

    while (!stop_flag) {
        struct pollfd pfd;
        int n;

        for (i = 0; i < BATCH; i++) {
            mmsg[i].msg_hdr.msg_iov     = &iov[i];
            mmsg[i].msg_hdr.msg_iovlen  = 1;
            mmsg[i].msg_hdr.msg_name    = NULL;
            mmsg[i].msg_hdr.msg_namelen = 0;
            mmsg[i].msg_hdr.msg_control = NULL;
            mmsg[i].msg_hdr.msg_controllen = 0;
            mmsg[i].msg_hdr.msg_flags   = 0;
            mmsg[i].msg_len = 0;
            iov[i].iov_len = PKT_BUF;
        }

        n = recvmmsg(fd, mmsg, BATCH, MSG_DONTWAIT, NULL);
        if (n > 0) {
            for (i = 0; i < n; i++)
                handle_packet(bufs[i], (int)mmsg[i].msg_len);
            continue;
        }
        if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            perror("recvmmsg");
            break;
        }
        pfd.fd = fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        poll(&pfd, 1, 50);
    }

    printf("rxfast: exit raw=%u pkts=%u frames=%u rej[mac=%u len=%u total=%u]\n",
           shm->raw, shm->pkts, shm->frames,
           shm->bad_mac, shm->bad_len, shm->bad_total);
    close(fd);
    return 0;
}
