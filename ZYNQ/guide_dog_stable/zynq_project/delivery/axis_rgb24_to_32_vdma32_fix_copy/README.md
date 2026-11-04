# OV5640 AXI/VDMA repair delivery

This directory is generated from the independent copied projects:

- Vivado: D:/distortion_correction/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy
- PetaLinux: /home/caitlyn/workdir/plnx_prj_2024_1/camremap_plnx_100mhz_axi_vdma_fix_copy

## SD image files

The boot files are BOOT.BIN, image.ub, boot.scr, and system.bit. Use them only after board-specific review.

The hardware and Linux inputs were hash-checked as a matched set. The installed application uses 800x480 RGB888, 2400-byte stride, three VDMA frame stores, and active S2MM writer field bits 28:24.

## Board validation

No SD write or live-camera claim is included. After boot, run the read-only probe from the Vivado copy:

python3 board_capture_probe.py --hwh /usr/share/camremap/led_test_wrapper.hwh --seconds 10

Record VDMA status, geometry, sequential writer transitions, accepted snapshot timing, repeated recovery count, complete raw frames, Remap output, and UDP counters. The probe cannot prove physical PCLK timing or memory completion by itself.

The routed Vivado report meets user timing constraints, but it contains implementation warnings for the OV5640 clock route, RAM controls, and DSP pipelining. These remain engineering review items.
