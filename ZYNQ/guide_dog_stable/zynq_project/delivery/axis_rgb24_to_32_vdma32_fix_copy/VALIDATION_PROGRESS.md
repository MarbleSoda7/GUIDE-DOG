# AXI camera / VDMA repair validation — work in progress

Protected output left untouched: D:/distortion_correction/petalinux/round_outputs/axis_rgb24_to_32_vdma32. No new SD writes.

Independent Vivado project: D:/distortion_correction/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy
Independent actual PetaLinux project: /home/caitlyn/workdir/plnx_prj_2024_1/camremap_plnx_100mhz_axi_vdma_fix_copy (WSL Ubuntu-22.04).
The E:/petalinux/Petalinux安装文件_axi_vdma_fix_copy directory is a separate broad resource copy, not the actual Linux build project.

## Current source changes

RTL collects only lines with exactly 800 accepted RGB24 pixels and EOL at pixel 799, then emits 600 packed 32-bit words (2400 bytes). Waits for SOF after reset or malformed line; unexpected SOF restarts the partial line at that SOF pixel. Stops accepting frame lines after HEIGHT=480 until next SOF. Sticky fault flags report malformed markers internally. Line RAM writes are synchronous and separate from asynchronously reset control to remove synthesis set/reset inference concerns. Production defaults RGB888 byte packing, not padded 32-bit pixels.

Application rejects halted/error status, including observed SR 0x15890. Requires observed active writer transition after startup/reset. Writer field remains WrFrmStore bits[28:24]; proposed >>8 change was incorrect (park reference) and was reverted. Snapshot at reserved offset 0x00800000 (PA 0x30800000) preserves all existing capture/output/map addresses; Remap reads private snapshot. Initial writer must exactly equal selection writer, capture register geometry is checked, and pre-check/copy/post-check elapsed must be strictly less than 6ms or frame is dropped before processing/transmission. See software_stage/camremap/CAPTURE_VALIDITY.md for the conditional timing argument and limits. SCCB and UDP contract unchanged.

## Passed checks on latest synchronous-RAM RTL

- tb_ram.log: two small frames, all four byte lanes, SOF/EOL and stalled-valid stability.
- tb_full_ram.log: two complete 800x480 frames, all 2,304,000 bytes checked, 600 words/line.
- tb_recovery_ram.log: unsynchronized startup, early/missing EOL, midline SOF, height bound, 100-cycle output stall.
- tb_axis_live_ram.log: 36 Mpixel/s unthrottled source, zero blanking, 100MHz AXI, behavioral 4096-entry FIFO, 200 stalled cycles every 1600 cycles; 768000 input pixels, 576000 output beats, 2 SOF, 960 EOL, max_queue 290/4096, overflow=0, all bytes/diagnostics checked. Explicit PASS markers confirmed (xsim fatal can return exit0).
- Staged application: 23 mock tests pass, including capture errors, uninitialized slots, copy time limit, exact initial writer match, snapshot Remap source, bypass, geometry and HWH checks.

## Build status and remaining work

A copied Linux build completed, but its generated configuration still referred to original hardware inputs, so it is NOT a valid final paired output. XSA, bitstream and config input paths have now been redirected to the copied project. Silentconfig confirms copied HDF_PATH, SYSCONFIG_DIR and EXTRA_FILESLIST. Read-only uninative URL was regenerated pointing at original resource; a persistent meta-user override now selects the copied archive instead. Camera package build pwsh-27 completed with exit0 using copied standard layers and copied hardware inputs. Global TFTP copying disabled.

The earlier Vivado build passed timing (WNS 0.460ns), but predates final framing/RAM changes and cannot validate them. Rebuild with strict recovery generated line RAM set/reset inference warnings; that build was cancelled. Final synchronous-RAM hardware rebuild is running as pwsh-24 (rebuild_ram.log). The converter runme.log appends sessions: latest session starts at line167 (12:30:40), and has no Synth8-7137 warning; earlier session warnings remain above line167. Latest session has Synth8-4767: byte array becomes registers due multiple write ports. Resource/timing acceptance is still pending. Collect it, inspect warnings/timing/DRC, extract matching bit/HWH from final XSA, import this final hardware into copied PetaLinux, rebuild, verify actual app/rootfs and hardware hashes, then package in a NEW output folder. Do not deliver copied images as if newly built.

Kernel fetch issue was traced to a partially copied git pack; copied damaged cache removed and existing offline archive used successfully. No changes to the original download archive were required.

## Evidence limits / board acceptance still required

Behavioral FIFO simulation does not test actual Xilinx FIFO CDC/reset or electrical camera sampling. Camera XDC has a 72MHz PCLK assumption but no input-delay constraints. Current PCLK reset deassertion lacks a demonstrated local-domain synchronization guarantee. Video bridge overflow and converter fault/diagnostic outputs are not wired to software-visible registers. A finite FIFO cannot guarantee arbitrary downstream stalls or detect all lost full lines/frames silently. Partial frame data already in DDR must be rejected by error checks/recovery.

Snapshot minimum-frame bound is conditional on paired serial bridge at 100MHz and VDMA current-writer / outstanding DDR transaction semantics; HWH and mock tests do not establish memory completion or CPU-to-HLS visibility. Board checks must verify copy durations, sequential writer transitions, no persistent SOF/EOL errors, no repeated recovery, complete stable raw frames and Remap/UDP output. Keep board commands to at most two per round. No claim of live-camera resolution or task completion yet.
