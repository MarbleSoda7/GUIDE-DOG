// frame_recv.cpp v6 - stereo UDP receiver for ZYNQ dual-camera stream
//
// Wire format v1 (12-byte metadata header, then raw RGB888 image bytes):
//   [D2][C2][ver=01][camera_id][pair_id BE16][total=827 BE16]
//   [packet_index BE16][payload_len BE16][image bytes]
// camera_id is 1 or 2; packets 0..825 carry 1394 image bytes, packet 826
// carries the remaining 556.  Both eyes of one stereo pair share a pair_id.
//
// The receiver keeps two independent reassembly state machines, publishes the
// newest complete frame per eye, draws them side by side in one 1600x480
// window and optionally overlays detections from the local gd_server
// (TCP 127.0.0.1:9527, [4B BE jpeg length][jpeg] -> [4B BE json length][json]).
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netpacket/packet.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <string>
#include <algorithm>
#include <vector>
#include <ctime>
#include <atomic>
#include <mutex>
#include <thread>
#include <chrono>

static const int W = 800, H = 480;
static const int FRAME_BYTES = W * H * 3;
static const int DATA_PER_PKT = 1394;
static const int TOTAL_PKTS = 827;
static const int HDR_BYTES = 12;
static const uint8_t PKT_MAGIC0 = 0xD2, PKT_MAGIC1 = 0xC2;
static const int PKT_VERSION = 1;
// Legacy v0 header [4B zero][frame_id BE16][total BE16][packet_index BE16].
// The old single-camera bitstream still emits this, and it only ever carries
// camera 1, so the receiver stays usable until the stereo bitstream is booted.
static const int LEGACY_HDR = 10;

// GIMME is the L2 keep-alive that tells the FPGA a receiver is present.
static const uint8_t GIMME[60] = {
    0x12,0x34,0x56,0x78,0x9a,0xbc,
    0xa2,0xd8,0xbf,0xa8,0x6d,0xb5,
    0x08,0x00,
    0x45,0x00,0x00,0x1d,0x00,0x1c,0x40,0x00,
    0x40,0x11,0x7f,0x06,
    0x0a,0xd4,0xd3,0x02,
    0x0a,0xd4,0xd3,0x03,
    0x9c,0x40,0x04,0xd2,0x00,0x09,0x00,0x00,
    0x47,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

static double now_s() {
    timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void configure_receive_buffer(int fd) {
    const int requested = 64 * 1024 * 1024;   // two eyes share one socket
    bool configured = false;
#ifdef SO_RCVBUFFORCE
    if (setsockopt(fd, SOL_SOCKET, SO_RCVBUFFORCE,
                   &requested, sizeof(requested)) == 0) {
        configured = true;
    }
#endif
    if (!configured && setsockopt(fd, SOL_SOCKET, SO_RCVBUF,
                                  &requested, sizeof(requested)) < 0) {
        perror("SO_RCVBUF");
    }
    int actual = 0;
    socklen_t len = sizeof(actual);
    if (getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &actual, &len) == 0)
        printf("udp receive buffer requested=%d actual=%d%s\n",
               requested, actual, configured ? " (forced)" : "");
}

static bool link_up() {
    FILE* f = fopen("/sys/class/net/eth0/carrier", "r");
    if (!f) return false;
    char c = 0;
    size_t n = fread(&c, 1, 1, f);
    fclose(f);
    return n == 1 && c == '1';
}

// ---------------------------------------------------------------- detections
struct Detection {
    std::string cls;
    double score = 0.0;
    double angle_deg = 0.0;
    bool has_box = false;
    double x = 0, y = 0, w = 0, h = 0;   // normalised 0..1 when present
    double x1 = 0, y1 = 0, x2 = 0, y2 = 0; // model-space bbox (640x640)
    int risk = 0;
};

struct InferResult {
    std::vector<Detection> dets;
    double infer_ms = 0.0;
    int count = 0;
    bool valid = false;
};

// Minimal JSON helpers: the server response shape is fixed and small, so a
// full parser would add risk without adding value.
static bool json_number_after(const std::string& s, size_t from, const char* key,
                              double* out, size_t* at = nullptr) {
    std::string pat = std::string("\"") + key + "\"";
    size_t p = s.find(pat, from);
    if (p == std::string::npos) return false;
    p = s.find(':', p + pat.size());
    if (p == std::string::npos) return false;
    p++;
    while (p < s.size() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n')) p++;
    char* end = nullptr;
    double v = strtod(s.c_str() + p, &end);
    if (end == s.c_str() + p) return false;
    *out = v;
    if (at) *at = (size_t)(end - s.c_str());
    return true;
}

static std::string json_string_after(const std::string& s, const char* key) {
    std::string pat = std::string("\"") + key + "\"";
    size_t p = s.find(pat);
    if (p == std::string::npos) return std::string();
    p = s.find(':', p + pat.size());
    if (p == std::string::npos) return std::string();
    p = s.find('"', p);
    if (p == std::string::npos) return std::string();
    size_t q = s.find('"', p + 1);
    if (q == std::string::npos) return std::string();
    return s.substr(p + 1, q - p - 1);
}

static InferResult parse_result(const std::string& js) {
    InferResult r;
    double v = 0.0;
    if (json_number_after(js, 0, "infer_ms", &v)) r.infer_ms = v;
    if (json_number_after(js, 0, "count", &v)) r.count = (int)v;

    size_t arr = js.find("\"detections\"");
    if (arr != std::string::npos) {
        arr = js.find('[', arr);
        if (arr != std::string::npos) {
            size_t i = arr + 1;
            while (i < js.size()) {
                size_t ob = js.find('{', i);
                if (ob == std::string::npos) break;
                size_t cb = js.find('}', ob);
                if (cb == std::string::npos) break;
                std::string obj = js.substr(ob, cb - ob + 1);
                Detection d;
                d.cls = json_string_after(obj, "class");
                if (json_number_after(obj, 0, "score", &v)) d.score = v;
                if (json_number_after(obj, 0, "angle_deg", &v)) d.angle_deg = v;
                if (json_number_after(obj, 0, "risk_level", &v)) d.risk = (int)v;
                // gd_server reports "bbox": [x1, y1, x2, y2] in the 640x640
                // letterboxed model space.
                size_t bp = obj.find("\"bbox\"");
                if (bp != std::string::npos) {
                    bp = obj.find('[', bp);
                    if (bp != std::string::npos) {
                        double q[4];
                        bool ok = true;
                        size_t cur = bp + 1;
                        for (int k = 0; k < 4; k++) {
                            char* endp = nullptr;
                            q[k] = strtod(obj.c_str() + cur, &endp);
                            if (endp == obj.c_str() + cur) { ok = false; break; }
                            cur = (size_t)(endp - obj.c_str());
                            while (cur < obj.size() && (obj[cur] == ',' || obj[cur] == ' ')) cur++;
                        }
                        if (ok) {
                            d.has_box = true;
                            d.x1 = q[0]; d.y1 = q[1]; d.x2 = q[2]; d.y2 = q[3];
                            d.x = q[0]; d.y = q[1];
                            d.w = q[2] - q[0]; d.h = q[3] - q[1];
                        }
                    }
                }
                r.dets.push_back(d);
                i = cb + 1;
                size_t nx = js.find('{', i);
                size_t close = js.find(']', i);
                if (close != std::string::npos && (nx == std::string::npos || close < nx))
                    break;
            }
        }
    }
    r.valid = true;
    return r;
}

// ------------------------------------------------------------ stream state
struct Stream {
    int camera_id = 0;
    int pair_lock = -1;
    int gotCnt = 0;
    std::vector<uint8_t> work;
    std::vector<uint8_t> latest;
    std::vector<uint8_t> got;
    std::mutex mtx;
    std::atomic<uint64_t> published{0};
    std::atomic<uint64_t> completed{0};
    // Identifies the frame currently in latest, never an in-progress work frame.
    // It is advanced only inside the same mutex critical section as latest.swap.
    std::atomic<uint32_t> pair_id{0};

    void init(int cam) {
        camera_id = cam;
        work.assign(FRAME_BYTES, 0);
        latest.assign(FRAME_BYTES, 0);
        got.assign(TOTAL_PKTS, 0);
    }
    void reset_frame() {
        std::fill(got.begin(), got.end(), 0);
        gotCnt = 0;
    }
};

// ------------------------------------------------------------- inference IO
class InferClient {
public:
    InferClient(std::string host, int port) : host_(std::move(host)), port_(port) {}
    ~InferClient() { close(); }

    bool ensure() {
        if (fd_ >= 0) return true;
        int fd = ::socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return false;
        sockaddr_in sa{};
        sa.sin_family = AF_INET;
        sa.sin_port = htons((uint16_t)port_);
        if (inet_pton(AF_INET, host_.c_str(), &sa.sin_addr) != 1) {
            ::close(fd);
            return false;
        }
        if (::connect(fd, (sockaddr*)&sa, sizeof(sa)) < 0) {
            ::close(fd);
            return false;
        }
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        fd_ = fd;
        printf("[infer] connected to %s:%d\n", host_.c_str(), port_);
        return true;
    }

    bool call(const std::vector<uint8_t>& jpeg, InferResult* out) {
        if (!ensure()) return false;
        uint8_t hdr[4];
        uint32_t n = htonl((uint32_t)jpeg.size());
        memcpy(hdr, &n, 4);
        if (!send_all(hdr, 4)) { close(); return false; }
        if (!send_all(jpeg.data(), jpeg.size())) { close(); return false; }
        uint32_t rn = 0;
        if (!recv_all((uint8_t*)&rn, 4)) { close(); return false; }
        rn = ntohl(rn);
        if (rn == 0 || rn > 4u * 1024u * 1024u) { close(); return false; }
        std::string body(rn, '\0');
        if (!recv_all((uint8_t*)&body[0], rn)) { close(); return false; }
        *out = parse_result(body);
        return out->valid;
    }

    void close() {
        if (fd_ >= 0) { ::close(fd_); fd_ = -1; }
    }

private:
    bool send_all(const uint8_t* p, size_t n) {
        while (n) {
            ssize_t k = ::send(fd_, p, n, MSG_NOSIGNAL);
            if (k <= 0) { if (errno == EINTR) continue; return false; }
            p += k; n -= (size_t)k;
        }
        return true;
    }
    bool recv_all(uint8_t* p, size_t n) {
        while (n) {
            ssize_t k = ::recv(fd_, p, n, 0);
            if (k <= 0) { if (k < 0 && errno == EINTR) continue; return false; }
            p += k; n -= (size_t)k;
        }
        return true;
    }
    std::string host_;
    int port_ = 9527;
    int fd_ = -1;
};

// ------------------------------------------------------------------- main
int main(int argc, char** argv) {
    std::string infer_host = "127.0.0.1";
    int infer_port = 9527;
    bool do_infer = true;
    bool headless = false;
    int udp_port = 1234;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--no-infer")) do_infer = false;
        else if (!strcmp(argv[i], "--headless")) headless = true;
        else if (!strcmp(argv[i], "--host") && i + 1 < argc) infer_host = argv[++i];
        else if (!strcmp(argv[i], "--port") && i + 1 < argc) infer_port = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--udp-port") && i + 1 < argc) udp_port = atoi(argv[++i]);
    }

    int gimme_fd = socket(AF_PACKET, SOCK_RAW, htons(0x0003));
    if (gimme_fd < 0) { perror("gimme socket"); return 1; }
    ifreq ifr{};
    strncpy(ifr.ifr_name, "eth0", IFNAMSIZ - 1);
    if (ioctl(gimme_fd, SIOCGIFINDEX, &ifr) < 0) { perror("ioctl"); return 1; }
    sockaddr_ll sa{};
    sa.sll_family = AF_PACKET;
    sa.sll_protocol = htons(0x0003);
    sa.sll_ifindex = ifr.ifr_ifindex;
    if (bind(gimme_fd, (sockaddr*)&sa, sizeof(sa)) < 0) { perror("gimme bind"); return 1; }

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { perror("udp socket"); return 1; }
    sockaddr_in udp_sa{};
    udp_sa.sin_family = AF_INET;
    udp_sa.sin_addr.s_addr = htonl(INADDR_ANY);
    udp_sa.sin_port = htons((uint16_t)udp_port);
    if (bind(fd, (sockaddr*)&udp_sa, sizeof(udp_sa)) < 0) { perror("udp bind"); return 1; }
    configure_receive_buffer(fd);
    timeval tv{0, 200000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    printf("waiting for link...\n");
    for (int i = 0; i < 20 && !link_up(); i++) sleep(1);
    printf("link %s\n", link_up() ? "up" : "DOWN");
    sleep(2);

    int drained = 0;
    while (true) {
        uint8_t tmp[65535];
        ssize_t n = recv(fd, tmp, sizeof(tmp), MSG_DONTWAIT);
        if (n <= 0) break;
        drained++;
    }
    printf("udp receiver bound to 0.0.0.0:%d; drained %d stale datagrams\n", udp_port, drained);
    printf("stereo receiver: %dx%d per eye, %d pkts/eye, 12B header v%d\n",
           W, H, TOTAL_PKTS, PKT_VERSION);
    fflush(stdout);

    Stream cam[2];
    cam[0].init(1);
    cam[1].init(2);

    std::atomic<bool> stop{false};
    // Latest detections per eye, produced by the inference thread.
    std::mutex res_mtx;
    InferResult results[2];
    std::atomic<uint64_t> infer_done{0};
    std::atomic<double> infer_fps{0.0};

    std::thread receiver([&]() {
        unsigned udp = 0, accepted = 0, drops = 0;
        unsigned long long legacy = 0;
        double report_t0 = now_s();
        uint64_t reported[2] = {0, 0};
        double last_gimme = report_t0 - 0.5;
        uint8_t buf[2048];

        while (!stop.load()) {
            double now = now_s();
            if (now - last_gimme >= 0.5) {
                if (send(gimme_fd, GIMME, 60, 0) < 0 && errno != EINTR)
                    perror("send gimme");
                last_gimme = now;
            }

            ssize_t n = recv(fd, buf, sizeof(buf), 0);
            if (n <= 0) continue;
            udp++;
            const int plen = (int)n;

            int hdrlen = HDR_BYTES;
            int cam_id = 0;
            uint32_t pair = 0;
            int tot = 0, idx = 0, paylen = 0;

            if (plen >= HDR_BYTES && buf[0] == PKT_MAGIC0 && buf[1] == PKT_MAGIC1) {
                if (buf[2] != PKT_VERSION) { drops++; continue; }
                cam_id = buf[3];
                pair = ((uint32_t)buf[4] << 8) | buf[5];
                tot = (buf[6] << 8) | buf[7];
                idx = (buf[8] << 8) | buf[9];
                paylen = (buf[10] << 8) | buf[11];
            } else if (plen >= LEGACY_HDR && buf[0] == 0 && buf[1] == 0 &&
                       buf[2] == 0 && buf[3] == 0) {
                // v0 stream from the still-flashed single-camera bitstream.
                hdrlen = LEGACY_HDR;
                cam_id = 1;
                pair = ((uint32_t)buf[4] << 8) | buf[5];
                tot = (buf[6] << 8) | buf[7];
                idx = (buf[8] << 8) | buf[9];
                paylen = plen - LEGACY_HDR;
                legacy++;
            } else {
                drops++;
                continue;
            }

            if (cam_id != 1 && cam_id != 2) { drops++; continue; }
            Stream& s = cam[cam_id - 1];

            if (tot != TOTAL_PKTS || idx < 0 || idx >= TOTAL_PKTS) { drops++; continue; }
            const int expected = std::min(DATA_PER_PKT, FRAME_BYTES - idx * DATA_PER_PKT);
            if (paylen != expected || plen - hdrlen != paylen) { drops++; continue; }

            // A different pair_id means the previous frame is unrecoverable.
            if ((int)pair != s.pair_lock) {
                s.pair_lock = (int)pair;
                // pair_id is deliberately not changed here: this pair is only
                // pending and must not be visible until all packets arrive.
                s.reset_frame();
            }
            // Retransmission/duplicate packets are idempotent: do not reset a
            // partially assembled immutable frame merely because idx==0.
            if (s.got[idx]) { drops++; continue; }

            memcpy(&s.work[(size_t)idx * DATA_PER_PKT], buf + hdrlen, (size_t)paylen);
            s.got[idx] = 1;
            s.gotCnt++;
            accepted++;

            if (s.gotCnt == TOTAL_PKTS) {
                {
                    std::lock_guard<std::mutex> lock(s.mtx);
                    // Publish pixels and their pair id as one immutable snapshot.
                    // Do not expose a newly arriving pair while work is partial.
                    s.latest.swap(s.work);
                    s.pair_id.store(pair, std::memory_order_release);
                }
                s.published.fetch_add(1);
                s.completed.fetch_add(1);
                s.reset_frame();
            }

            if (now - report_t0 >= 1.0) {
                double el = now - report_t0;
                printf("[rx] cam1=%.1f fps cam2=%.1f fps udp=%u accepted=%u dropped=%u"
                       " legacy=%llu\n",
                       (cam[0].completed.load() - reported[0]) / el,
                       (cam[1].completed.load() - reported[1]) / el,
                       udp, accepted, drops, legacy);
                fflush(stdout);
                reported[0] = cam[0].completed.load();
                reported[1] = cam[1].completed.load();
                report_t0 = now;
                udp = accepted = drops = 0;
            }
        }
    });

    // Inference runs on its own thread and only ever consumes the newest frame,
    // so a slow NPU degrades the overlay rate instead of stalling reception.
    std::thread infer([&]() {
        if (!do_infer) return;
        InferClient client(infer_host, infer_port);
        uint64_t seen[2] = {0, 0};
        int turn = 0;
        double t0 = now_s();
        uint64_t done = 0;
        while (!stop.load()) {
            uint64_t cur = cam[turn].published.load();
            if (cur == seen[turn] || cur == 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                turn ^= 1;
                continue;
            }
            seen[turn] = cur;
            cv::Mat img(H, W, CV_8UC3);
            {
                std::lock_guard<std::mutex> lock(cam[turn].mtx);
                memcpy(img.data, cam[turn].latest.data(), (size_t)FRAME_BYTES);
            }
            std::vector<uint8_t> jpg;
            std::vector<int> params{cv::IMWRITE_JPEG_QUALITY, 80};
            if (!cv::imencode(".jpg", img, jpg, params)) {
                turn ^= 1;
                continue;
            }
            InferResult r;
            if (client.call(jpg, &r)) {
                {
                    std::lock_guard<std::mutex> lock(res_mtx);
                    results[turn] = r;
                }
                done++;
                infer_done.store(done);
                printf("[yolo] cam%d det=%d infer_ms=%.1f total=%llu\n",
                       turn + 1, r.count, r.infer_ms, (unsigned long long)done);
                fflush(stdout);
            } else {
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
            }
            double el = now_s() - t0;
            if (el > 1e-6) infer_fps.store(done / el);
            turn ^= 1;
        }
        client.close();
    });

    if (!headless) cv::namedWindow("ZYNQ STEREO", cv::WINDOW_AUTOSIZE);
    cv::Mat canvas(H, W * 2, CV_8UC3);
    // Each eye is staged on its own and the window is only refreshed once the
    // two eyes carry the same pair_id. The PL sends all 827 cam1 packets and
    // then all 827 cam2 packets, so the halves of one pair land ~10 ms apart;
    // drawing them on arrival tears the pair and flickers "STALE PAIR".
    cv::Mat staged[2] = {cv::Mat(H, W, CV_8UC3), cv::Mat(H, W, CV_8UC3)};
    bool haveStaged[2] = {false, false};
    uint32_t stagedPair[2] = {0, 0};
    uint64_t shown[2] = {0, 0};
    uint64_t shownCount[2] = {0, 0};
    uint32_t composedPair = 0;
    bool haveComposed = false;
    double lastCompose = now_s();
    double display_t0 = now_s();
    double last_save = now_s();
    bool savedFirst = false;

    while (!stop.load()) {
        for (int i = 0; i < 2; i++) {
            uint64_t seq = cam[i].published.load();
            if (seq == 0 || seq == shown[i]) continue;
            {
                std::lock_guard<std::mutex> lock(cam[i].mtx);
                memcpy(staged[i].data, cam[i].latest.data(), (size_t)FRAME_BYTES);
                stagedPair[i] = cam[i].pair_id.load();
            }
            shown[i] = seq;
            shownCount[i]++;
            haveStaged[i] = true;
        }
        bool fresh = false;
        if (haveStaged[0] && haveStaged[1]) {
            const bool matched = (stagedPair[0] == stagedPair[1]);
            const bool unseen = !haveComposed || composedPair != stagedPair[0];
            // 1.0 s without a composed pair means one eye stopped advancing;
            // show the stale halves rather than freezing the window.
            if ((matched && unseen) || now_s() - lastCompose > 1.0) {
                for (int i = 0; i < 2; i++) {
                    for (int y = 0; y < H; y++) {
                        memcpy(canvas.ptr<uint8_t>(y) + (size_t)i * W * 3,
                               staged[i].ptr<uint8_t>(y), (size_t)W * 3);
                    }
                }
                composedPair = stagedPair[0];
                haveComposed = true;
                fresh = true;
            }
        } else if (haveStaged[0] || haveStaged[1]) {
            // Single-camera stream (the still-flashed v0 bitstream): draw the
            // one eye that exists, exactly as the single-camera build did.
            const int i = haveStaged[0] ? 0 : 1;
            for (int y = 0; y < H; y++) {
                memcpy(canvas.ptr<uint8_t>(y) + (size_t)i * W * 3,
                       staged[i].ptr<uint8_t>(y), (size_t)W * 3);
            }
            fresh = true;
        }
        if (fresh) {
            lastCompose = now_s();
            std::lock_guard<std::mutex> lock(res_mtx);
            for (int i = 0; i < 2; i++) {
                cv::Mat roi = canvas(cv::Rect(i * W, 0, W, H));
                const uint32_t pair = cam[i].pair_id.load();
                char hud[192];
                const InferResult& r = results[i];
                if (cam[i].published.load() == 0) {
                    // Never invent a frame rate for an eye that has not delivered.
                    snprintf(hud, sizeof(hud), "cam%d pair=-- rx=0.0 fps | waiting for data",
                             i + 1);
                } else {
                    snprintf(hud, sizeof(hud), "cam%d pair=%u rx=%.1f fps | yolo %.1f fps %s",
                             i + 1, pair,
                             shownCount[i] / std::max(1e-3, now_s() - display_t0),
                             infer_fps.load(),
                             r.valid ? "on" : "n/a");
                }
                cv::putText(roi, hud, cv::Point(8, 22), cv::FONT_HERSHEY_SIMPLEX,
                            0.55, cv::Scalar(0, 255, 255), 2);
                if (r.valid) {
                    for (const Detection& d : r.dets) {
                        if (!d.has_box) continue;
                        // gd_server letterboxes the frame into 640x640, so map
                        // model-space boxes back through the same transform.
                        const double s = std::min(640.0 / W, 640.0 / H);
                        const double padx = (640.0 - W * s) * 0.5;
                        const double pady = (640.0 - H * s) * 0.5;
                        double bx = (d.x1 - padx) / s, by = (d.y1 - pady) / s;
                        double bw = (d.x2 - d.x1) / s, bh = (d.y2 - d.y1) / s;
                        bx = std::max(0.0, std::min((double)W - 1, bx));
                        by = std::max(0.0, std::min((double)H - 1, by));
                        bw = std::min((double)W - bx, bw);
                        bh = std::min((double)H - by, bh);
                        cv::Scalar col = d.risk >= 3 ? cv::Scalar(0, 0, 255)
                                       : d.risk == 2 ? cv::Scalar(0, 165, 255)
                                                     : cv::Scalar(0, 255, 0);
                        cv::rectangle(roi, cv::Rect((int)bx, (int)by, (int)bw, (int)bh), col, 2);
                    }
                    // A compact detection list is always readable, and works
                    // even when the server reports no bounding boxes.
                    int y = H - 16;
                    int shown_dets = 0;
                    for (const Detection& d : r.dets) {
                        if (shown_dets >= 6) break;
                        char lab[128];
                        snprintf(lab, sizeof(lab), "%s %.2f %.0fdeg",
                                 d.cls.c_str(), d.score, d.angle_deg);
                        cv::putText(roi, lab, cv::Point(8, y), cv::FONT_HERSHEY_SIMPLEX,
                                    0.5, cv::Scalar(0, 255, 0), 1);
                        y -= 18;
                        shown_dets++;
                    }
                }
            }
            // If only the legacy stream is present the right half stays black;
            // say so instead of leaving the field guessing.
            if (cam[1].published.load() == 0) {
                cv::putText(canvas, "cam2: no data (v0 single-cam stream?)",
                            cv::Point(W + 12, H / 2), cv::FONT_HERSHEY_SIMPLEX,
                            0.6, cv::Scalar(140, 140, 140), 2);
            }
            // Stale pair: the two eyes came from different capture instants.
            // Only meaningful once both eyes have actually delivered frames.
            if (cam[0].published.load() && cam[1].published.load() &&
                cam[0].pair_id.load() != cam[1].pair_id.load()) {
                cv::putText(canvas, "STALE PAIR", cv::Point(W - 130, H - 12),
                            cv::FONT_HERSHEY_SIMPLEX, 0.7, cv::Scalar(0, 215, 255), 2);
            }
            if (!headless) cv::imshow("ZYNQ STEREO", canvas);
            if (!savedFirst) {
                savedFirst = true;
                cv::imwrite("/home/cat/eth_recv/stereo_0.png", canvas);
            }
            // Headless proof-of-life: refresh a still so the stereo pair and the
            // detection overlay can be inspected without an X server.
            if (now_s() - last_save >= 2.0) {
                last_save = now_s();
                cv::imwrite("/home/cat/eth_recv/stereo_latest.png", canvas);
            }
        }
        if (headless) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        } else if ((cv::waitKey(1) & 0xFF) == 'q') break;
    }

    stop.store(true);
    shutdown(fd, SHUT_RDWR);
    receiver.join();
    infer.join();
    cv::destroyAllWindows();
    close(fd);
    close(gimme_fd);
    return 0;
}
