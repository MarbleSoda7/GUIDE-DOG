# Latest-complete-frame PL scheduler

The historical `phase_b_project.xpr` and its cyclic bit/ELF pair remain intact.
The candidate is the isolated `latest_frame_project/latest_frame_project.xpr`.
Its custom RTL and firmware source live in this directory's `rtl/` and `sw/`.

## Data path

OV5640 -> video AXIS (RGB888) -> 24-to-32 byte packer -> AXI VDMA S2MM
-> three DDR stores -> AXI VDMA MM2S -> latest-generation frame gate ->
32-to-64 packer -> existing asynchronous AXIS FIFO / UDP packetizer ->
RGMII -> RK receiver.

The S2MM AXI **monitor** observes accepted AW addresses and final successful
DDR B responses without breaking the bus. It publishes a slot generation only
after all 1,152,000 contiguous bytes are acknowledged. A second AXI monitor
decodes the MM2S slot from its actual DDR AR address; it does not interpret
VDMA's six-bit Gray-coded frame pointer as a binary slot number.

The PL pacer issues one external MM2S FSYNC for a new generation. The gate
passes a complete read frame only when its actual slot still holds the newest
committed generation and is not being written. It drops stale frames and
never deliberately repeats a transmitted generation. A writer/reader collision,
address discontinuity, AXI range violation or incomplete-frame timeout latches
a fail-closed fault. Dynamic VDMA genlock is configured with S2MM master and
MM2S slave; both channels are started once by the PS ELF. There is no per-frame
PS polling, descriptor edit or GIMME dependency.

The 24-to-32 packer is necessary because this VDMA configuration exposes a
32-bit video stream port. It preserves contiguous RGB888 bytes (2400 bytes per
line); simply wiring 24 bits into that port would insert an unwanted padding
byte per pixel. The packetizer sends 826 full packets and a 556-byte final
payload. The matching `RK/src/rk_frame_recv.cpp` accepts that short packet.

## Build and debug

1. Run `integrate_latest_frame.tcl` with Vivado 2026.1 in batch mode to
   reconstruct the isolated BD and its generated output products.
2. Run `preflight_latest_frame.tcl`; it checks BD validation, expected
   interfaces, top module, five-probe ILA limit and IP freshness.
3. Run `build_latest_frame_elf.ps1` and `build_latest_frame_bit.tcl`.

The delivery artifacts are `test_artifacts/stage5_latest_frame_pl_owner.bit`,
`.ltx`, and `.elf` after successful implementation. Do not mix them with the
historical cyclic ELF or bitstream. For board testing, capture RK packets
before programming the bit and starting the ELF on a clean ZYNQ power cycle.

`ila_latest_frame` has exactly five probes: DDR commit generation, newest
generation, last sent generation, dropped read frames, and latched fault.
The serial ELF reports camera ID/timing, both VDMA statuses, PARKPTR, and UDP
packet counter deltas every five seconds. A UDP-frame count alone is not proof
of unique camera images; verify image hashes, tears, and rate on RK.

The camera retains the baseline OV5640 timing (HTS 2570, VTS 1800). This design
removes artificial repeated sends; it does **not** prove 40-50 unique camera
frames per second. Raising sensor rate requires separate camera-timing and
board validation. The RTL/BD simulations and implementation are necessary
offline gates, not a substitute for RK capture and image inspection.

## Offline build result (2026-09-28)

The final build uses `vdma_frame_commit_axi.v` with a 21-bit byte counter and
a one-cycle B-response metadata stage. Vivado 2026.1 implementation completed
at 100%. Post-route timing is setup WNS `+0.463 ns`, hold WHS `+0.014 ns`, with
zero failing endpoints. Route status reports 38,062/38,062 routable nets fully
routed and zero routing errors; DRC reports zero errors (warnings remain for
the existing camera clock placement/constraint environment).

Offline xsim passes include the latest-frame gate, RGB packers, short final
packet, two full 1,152,000-byte frames (563 AXI bursts each), and back-to-back
B responses. The delivery pair is:

- `test_artifacts/stage5_latest_frame_pl_owner.bit` SHA-256
  `B982022757622AAF8868F3C27355A8F1CA2A5C8F077B9FEC16BA5B0657BE88FA`
- `test_artifacts/stage5_latest_frame_pl_owner.ltx` SHA-256
  `58FC8A298CA16C5086A9720C5BFF8328149001C0AB85FE922F7068559D5F7E6F`
- `test_artifacts/stage5_latest_frame_pl_owner.elf` SHA-256
  `17C7D0798378E882E752F1190C6623ACC89E3E3FB38CBE9629402DFDF0217D6C`

No board or RK capture was available in this run. Therefore packet reception,
image freshness, visual tearing, and measured camera/RK frame rate remain
hardware acceptance tests, not claims made by this offline build.

## Historical-regression audit (2026-09-28)

The following offline regressions passed after the final build: the unsafe
three-slot collision model reproduces the old overlap while the ownership
schedule has zero collisions for read times up to 39 simulation units; the
MM2S slot monitor rejects out-of-range reads; the RGB24-to-32 and 32-to-64
packers preserve byte order; the packetizer emits the short final packet;
the commit monitor handles two complete 1,152,000-byte frames, 563 bursts per
frame, and back-to-back B responses; and the Vivado BD/IP preflight reports
all required interfaces connected with exactly five ILA probes and no stale
IP status.

This audit rules out the previously observed software/RTL failure classes:
826/827 final-packet loss, sparse-TKEEP boundary loss, repeated stale-slot
transmission in the PL scheduler, invalid MM2S slot decoding, DMA frame-length
truncation in the commit monitor, and six-probe BASIC-license failure. It does
not rule out board-only camera clock placement, PHY/RGMII electrical timing,
DDR signal integrity, or RK kernel packet loss; those require the matching
bit/LTX/ELF to be programmed and captured on hardware.
