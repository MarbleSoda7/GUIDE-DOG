# success_third Build Notes

## Design

- Vivado 2024.1 target: Zynq-7020, xc7z020clg400-2.
- Two OV5640 capture paths write independent three-frame rings in the reserved DDR range at 0x30000000 (16 MiB total). Camera 1 is RGB888 and uses the existing RGB24-to-32 bridge and UDP transmitter. Camera 2 is a separate RGB888-to-VDMA path and is not transmitted.
- The Ethernet sender source is byte-identical to the successful source project. The 800x480 RGB888 frame size and UDP packetization remain unchanged.
- The top-level wrapper has no HDMI or LCD output ports. Copied correction HLS sources, drivers, application code, and unused HDMI/display IP repositories were removed. `remap_hp_smc` is retained only as the DDR HP SmartConnect; it is not a distortion/remap accelerator.

## Validation

- Vivado synthesis, routed implementation, and XSA export completed. DRC has 0 errors; routed setup has 0 failing endpoints and 0.179 ns worst slack. The final timing report says all specified constraints are met; bus-skew report is generated. PCLK ports require non-dedicated routing.
- The Linux application passed Python syntax and the final generated-HWH contract check. The reserved-DDR layout remains configured at 0x30000000 (16 MiB). PetaLinux built the rootfs and FIT image successfully; no physical boot or camera runtime test has been performed.
- PetaLinux rebuilt successfully from the final XSA. `BOOT.BIN` was repackaged from the new FSBL, adapter bitstream, U-Boot and system DTB; `image.ub` and `boot.scr` were regenerated. The three SD files in `sd_card/` are the outputs of this build.
- Vivado reports non-dedicated routing warnings for the two J25 camera PCLK pins and RAMB36 asynchronous-control warnings in the existing UDP FIFO. External camera input delays are not modeled in the XDC. PetaLinux emitted only the expected warning that /tftpboot is unavailable; SD files were copied directly.

## Board Validation Still Required

The Wildfire module schematic at `D:\ebf_camera_ov5640_20240517` shows one Y1 24 MHz oscillator feeding the shared XCLK net through R5/R26. The success_third block design removes FPGA XCLK and exposes one shared RST and one shared PWDN. The user J25 table is encoded in `dual_camera_j25.xdc`; both sensor data/PCLK/VSYNC/HREF/SCCB groups remain independent. No physical capture or Ethernet reception test has been performed.

Verify that the module oscillator and R5/R26 links are fitted, then scope XCLK at both sensor pins and check shared RST/PWDN polarity. The adapter J25 mapping was transcribed from the user-provided wiring table and board package-pin map; physical adapter orientation and pin numbering still require board verification.

Deploy the three files in `sd_card/` together to the SD card boot partition: `BOOT.BIN`, `image.ub`, and `boot.scr`.
