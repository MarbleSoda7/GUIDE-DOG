# Commit-stop root cause and recovery validation

## Board evidence

Parent build: `20261001T062420Z_owner_camera_baseline_v1`.
Observational ECO: `20261001T081800Z_commit_ila_eco`.
The ECO changes only the five existing ILA probes and their sample clock.
The original camera-baseline ELF is reused unchanged.

Trace: `20261001T081800Z_commit_ila_eco/20261001T083305Z_board/commit_fault.csv`.

- Sample 3071: AWVALID=AWREADY=1, AWADDR=`0x11232800` (slot 2 base), AWLEN=`0x3f`, AWSIZE=3, outstanding queue=0, fault=0.
- Sample 3072: fault=1; the accepted AW is queued. No B handshake occurred at the fault edge.
- Sample 3171: first new-slot B response is successful (BRESP=0).
- At sample 3546, response-end=`0x0af520`; subtracting the new 512-byte burst gives the preceding partial frame's completed count `0x0af320`=717600=299*2400 bytes.
- Slot 2 base and this burst are in range and do not cross the slot end. Queue overflow and B-underflow are excluded by these same edge samples. Thus the first AW was rejected by the old address-continuity predicate, which allows a slot-base restart only after exactly FRAME_BYTES.
- The global sticky fault then prevents every future commit via `if (!fault && ...)`, even after subsequent DDR frames are complete. Live DDR write-start count continues growing while commit and UDP counters freeze.
- Live S2MM status after failure is `0x15090`, including FSZ_LESS. Its upstream cause is not established by this write-side trace; it must not be labeled an OV5640 hardware root cause. The demonstrated permanent-stop cause is the observer's lack of a short-frame restart boundary.

The former "S2MM stopped and camera counters froze" interpretation is withdrawn: two read-only snapshots showed write-start count advancing from `0x6526` to `0x66b8` with commit fixed at `0x11dd`. Camera registers here retain per-frame latched totals, not monotonic frame counts.

## Capture before the fault

RK `/tmp/commit_ila_20261001.pcap`: 559150 packets, 0 invalid format packets, 0 duplicate indices, FIDs 1..677 without gaps, 673 complete frames with 673 distinct image hashes, start-to-start 15.564 fps.
Three interior incomplete frames (FIDs 37,529,539) remain; the terminal partial frame is capture-boundary truncation. tcpdump kernel drops=0. This is not loss-free acceptance.

## Scoped correction

Only `rtl/vdma_frame_commit_axi.v` functional behavior changes:

1. An in-range slot base is a legal frame restart even if the preceding capture was short.
2. Every AW FIFO entry carries a first-burst marker.
3. The accumulator and per-frame BRESP error state reset when that marker reaches the ordered B-response processing stage, not when AW arrives.
4. A short frame is discarded and counted. No commit is emitted until one new frame has complete contiguous address coverage and successful responses for FRAME_BYTES.
5. True noncontiguous mid-frame addresses, out-of-range bursts, queue overflow/underflow and response-byte overrun remain fatal protections.

The revision-specific `vdma_frame_commit_axi_restart_v1` module reference prevents old OOC reuse. Camera initialization/timing, video input IP, VDMA configuration, packetizer, RGMII, and RK receiver remain unchanged.

## Verification status

- Old RTL reproduction: `SHORT_FRAME_RESULT generation=1 errors=3 fault=1`; later full frames permanently suppressed.
- Fixed RTL reproduction: `generation=3 errors=1 fault=0`; incomplete frame skipped and later complete frames published.
- Extended outstanding-response case passes; old partial responses cannot be mixed with the new frame.
- Existing five path regressions pass (`20261001T084010Z_rtl_regression`).
- Functional build `20261001T084500Z_commit_restart_v1` completed. New bit SHA-256 `C16B5261200629DD30B6BEF998B7D77CBC8D3DD824DB3A86317B6787F56A9EA2`; LTX SHA-256 `4304D7CD503C8759C7D6A2CDEB022FB868CCD40FE53F17E1231B9715191E4507`. All 60 snapshotted source hashes match after build. Fresh observer OOC log resolves both current RTL files; setup +0.410 ns, hold +0.019 ns, routing errors=0, DRC errors=0, all ten bus-skew constraints met.
- `build_manifest.json` explicitly records reuse of the unchanged camera-baseline ELF (`0C00FBAAF83E2B7EDA5EC487874084C13F0D97E485A2CF8EA23A4DA1005F7B13`), not a same-revision ELF compilation.
- First download attempt (`20261001T085827Z_board`) failed before programming: sourcing PS initialization inside a Tcl procedure made its variable initialization local. `uplevel #0` fixes that host-script error. XSDB still returned process exit code zero, so the acceptance gate now requires the explicit preparation-success marker and rejects error markers. Logs from this attempt are INVALID, not repair-board evidence.
- Second attempt also failed before programming, with DAP `0x30000021` and no A9 targets. After the user cold-cycled again, `20261001T090222Z_board/prepare.log` records A9 reset, PS init/postconfig, new bit programming, ELF download, and CPU stopped. The initial owner counters were zero. Receiver capture starts before CPU run. Ten-minute acceptance is in progress; short-frame recovery has not yet been observed in this run.
- No 40--50 fps or loss-free-delivery claim is made.

## Long board run result

Evidence: `20261001T084500Z_commit_restart_v1/20261001T090222Z_board`.
The 610-second RK capture received 7,814,148 valid packets and observed FIDs
1..9449 with no FID gaps and no duplicate packet indices. It reconstructed
9447 complete frames, with 9447 distinct SHA-256 image hashes (application
header/FID excluded). Frame-start rate was 15.564121 fps. One interior frame,
FID 5381, missed 18 consecutive packets, indices 662..679. The final frame was
truncated by capture timeout. tcpdump reported zero kernel drops. Thus this
is continuous-stream acceptance, NOT loss-free acceptance or the 40--50 fps
target. The cause of the 18 missing packets is not established.

All 120 independent JTAG samples had S2MM status `0x11000`, zero observer/
owner fault bits, and forward commit/TX progress. Final write/commit counters
were `0x251c`/`0x251b` (one write in progress), UDP_DONE `0x77de39`.
No short-frame event was observed, so hardware recovery after a short frame
is NOT claimed; that branch remains verified by old-failing/new-passing
simulation. The former permanent stop did not recur during this long run.

After the user requested local viewing, capture and CPU monitoring were
already finished; the existing RK `frame_recv` process was stopped, with no
replacement viewer launched remotely. FPGA autonomous streaming remains
running for the user's local HDMI test. No further board test or timing
change was started. A copy of the routed DCP is preserved as
`commit_restart_v1_routed.dcp`, SHA-256
`BFB6E0051B18CD9A4B3E9010436C515D52149FF558D1E600F1B603DEA873CB57`.
