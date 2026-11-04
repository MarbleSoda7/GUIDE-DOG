# AXI camera / VDMA repair validation — hardware and Linux artifacts built

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

Final hardware rebuild pwsh-24 completed with exit0. Routed timing summary: WNS +0.148ns, TNS 0, WHS +0.032ns, THS 0; all user timing constraints met. Routed DRC has 0 errors and warnings/advisories only. Placed utilization: 36,860 LUTs (69.29%), 51,893 registers (48.77%), 112/140 BRAM tiles (80%), 30/220 DSPs. Final XSA, bitstream and HWH were extracted from the same XSA and hash-checked. Full copied PetaLinux rebuild pwsh-28 completed all 4,764 tasks, with TFTP copying disabled; BOOT.BIN, image.ub, boot.scr and system.bit were generated. Rootfs tar contains camremap main.py, vdma.py and the installed HWH. Global TFTP copying disabled.

Final export verification reports XSA SHA256 f7778baacc6798642cda4898fb1bc88d83d8bd6b755832357408abffe942a25a, HWH SHA256 58ec35800284b224051922c449788602a10125bd62b021e54d6f4ba3ec840fdf, and bitstream SHA256 a0648ae427fa888abc8789a94e311f759b4af9278409b35105943c16d828f025. The independent delivery folder is D:/distortion_correction/petalinux/round_outputs/axis_rgb24_to_32_vdma32_fix_copy. The converter storage is implemented as synchronous line registers/LUT logic rather than BRAM; final routed timing passed, while routed DRC still reports 77 warnings/advisories including clock-placement, RAM control, and DSP pipelining recommendations. These warnings are recorded and are not silently treated as proof of electrical camera correctness.

Kernel fetch issue was traced to a partially copied git pack; copied damaged cache removed and existing offline archive used successfully. No changes to the original download archive were required.

## Evidence limits / board acceptance still required

Behavioral FIFO simulation does not test actual Xilinx FIFO CDC/reset or electrical camera sampling. Camera XDC has a 72MHz PCLK assumption but no input-delay constraints. Current PCLK reset deassertion lacks a demonstrated local-domain synchronization guarantee. Video bridge overflow and converter fault/diagnostic outputs are not wired to software-visible registers. A finite FIFO cannot guarantee arbitrary downstream stalls or detect all lost full lines/frames silently. Partial frame data already in DDR must be rejected by error checks/recovery.

Snapshot minimum-frame bound is conditional on paired serial bridge at 100MHz and VDMA current-writer / outstanding DDR transaction semantics; HWH and mock tests do not establish memory completion or CPU-to-HLS visibility. Board checks must verify copy durations, sequential writer transitions, no persistent SOF/EOL errors, no repeated recovery, complete stable raw frames and Remap/UDP output. Keep board commands to at most two per round. No claim of live-camera resolution or task completion yet.

Round 4 isolation recheck: generated build/conf/plnxtool.conf had a stale UNINATIVE_URL after the final PetaLinux regeneration. It was corrected to the copied components/yocto/downloads/uninative path and a targeted scan now reports ISOLATED_CONFIG_OK. No image contents or protected output were changed by this configuration-only correction.
Round 4: incremental camremap rebuild pwsh-29 completed with all 3467 tasks satisfied from the copied project; post-build plnxtool.conf still points to the copied uninative directory and targeted scan reports ISOLATED_CONFIG_OK.
Round 5 final reproducibility checks: 23 capture-validity unit tests passed; verify_artifacts.py passed against the final XSA and copied PetaLinux project; rootfs main.py and vdma.py hashes match reviewed source hashes; saved RTL logs contain PASS for small, full, recovery, and LIVE_PASS regressions.
Round 6: packaged BOARD_ACCEPTANCE.md, board_capture_probe.py, and verify_artifacts.py in the independent delivery directory. Both packaged Python tools compile successfully. Board acceptance criteria remain explicitly separate from simulation and static build evidence.
Round 7: board_capture_probe.py now exits with code 2 when initial VDMA geometry/circular mode, status, writer range, sequential transitions, or all-three-slot observation fails; it remains read-only and does not configure hardware. Packaged copy compiles successfully.
Round 8: generated SHA256SUMS.txt for every independent delivery file, removed generated Python bytecode from the delivery folder, and scanned delivery documentation for stale original-project paths; DELIVERY_PATH_SCAN_OK.
Round 9: SD card F: was backed up successfully to D:/distortion_correction/sd_backups/PETALINUX_before_fix_20261007_133747 (27 files, 376.35MB, zero robocopy failures/mismatches). Final BOOT.BIN, image.ub, boot.scr, and system.bit were copied to F: and source/SD SHA-256 hashes matched. No protected round_outputs/axis_rgb24_to_32_vdma32 files were used as write targets.
