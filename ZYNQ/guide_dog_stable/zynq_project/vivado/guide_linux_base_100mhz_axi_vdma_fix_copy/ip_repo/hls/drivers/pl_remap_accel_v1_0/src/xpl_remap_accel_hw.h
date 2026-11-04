// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2024.1 (64-bit)
// Tool Version Limit: 2024.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
// control
// 0x00 : Control signals
//        bit 0  - ap_start (Read/Write/COH)
//        bit 1  - ap_done (Read/COR)
//        bit 2  - ap_idle (Read)
//        bit 3  - ap_ready (Read/COR)
//        bit 7  - auto_restart (Read/Write)
//        bit 9  - interrupt (Read)
//        others - reserved
// 0x04 : Global Interrupt Enable Register
//        bit 0  - Global Interrupt Enable (Read/Write)
//        others - reserved
// 0x08 : IP Interrupt Enable Register (Read/Write)
//        bit 0 - enable ap_done interrupt (Read/Write)
//        bit 1 - enable ap_ready interrupt (Read/Write)
//        others - reserved
// 0x0c : IP Interrupt Status Register (Read/TOW)
//        bit 0 - ap_done (Read/TOW)
//        bit 1 - ap_ready (Read/TOW)
//        others - reserved
// 0x10 : Data signal of src
//        bit 31~0 - src[31:0] (Read/Write)
// 0x14 : Data signal of src
//        bit 31~0 - src[63:32] (Read/Write)
// 0x18 : reserved
// 0x1c : Data signal of lut
//        bit 31~0 - lut[31:0] (Read/Write)
// 0x20 : Data signal of lut
//        bit 31~0 - lut[63:32] (Read/Write)
// 0x24 : reserved
// 0x28 : Data signal of dst
//        bit 31~0 - dst[31:0] (Read/Write)
// 0x2c : Data signal of dst
//        bit 31~0 - dst[63:32] (Read/Write)
// 0x30 : reserved
// 0x34 : Data signal of step
//        bit 31~0 - step[31:0] (Read/Write)
// 0x38 : reserved
// 0x40 : Data signal of status
//        bit 31~0 - status[31:0] (Read)
// 0x44 : Control signal of status
//        bit 0  - status_ap_vld (Read/COR)
//        others - reserved
// 0x50 : Data signal of invalid_count
//        bit 31~0 - invalid_count[31:0] (Read)
// 0x54 : Control signal of invalid_count
//        bit 0  - invalid_count_ap_vld (Read/COR)
//        others - reserved
// 0x60 : Data signal of cache_miss_count
//        bit 31~0 - cache_miss_count[31:0] (Read)
// 0x64 : Control signal of cache_miss_count
//        bit 0  - cache_miss_count_ap_vld (Read/COR)
//        others - reserved
// 0x70 : Data signal of pixel_count
//        bit 31~0 - pixel_count[31:0] (Read)
// 0x74 : Control signal of pixel_count
//        bit 0  - pixel_count_ap_vld (Read/COR)
//        others - reserved
// 0x80 : Data signal of crc
//        bit 31~0 - crc[31:0] (Read)
// 0x84 : Control signal of crc
//        bit 0  - crc_ap_vld (Read/COR)
//        others - reserved
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

#define XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL               0x00
#define XPL_REMAP_ACCEL_CONTROL_ADDR_GIE                   0x04
#define XPL_REMAP_ACCEL_CONTROL_ADDR_IER                   0x08
#define XPL_REMAP_ACCEL_CONTROL_ADDR_ISR                   0x0c
#define XPL_REMAP_ACCEL_CONTROL_ADDR_SRC_DATA              0x10
#define XPL_REMAP_ACCEL_CONTROL_BITS_SRC_DATA              64
#define XPL_REMAP_ACCEL_CONTROL_ADDR_LUT_DATA              0x1c
#define XPL_REMAP_ACCEL_CONTROL_BITS_LUT_DATA              64
#define XPL_REMAP_ACCEL_CONTROL_ADDR_DST_DATA              0x28
#define XPL_REMAP_ACCEL_CONTROL_BITS_DST_DATA              64
#define XPL_REMAP_ACCEL_CONTROL_ADDR_STEP_DATA             0x34
#define XPL_REMAP_ACCEL_CONTROL_BITS_STEP_DATA             32
#define XPL_REMAP_ACCEL_CONTROL_ADDR_STATUS_DATA           0x40
#define XPL_REMAP_ACCEL_CONTROL_BITS_STATUS_DATA           32
#define XPL_REMAP_ACCEL_CONTROL_ADDR_STATUS_CTRL           0x44
#define XPL_REMAP_ACCEL_CONTROL_ADDR_INVALID_COUNT_DATA    0x50
#define XPL_REMAP_ACCEL_CONTROL_BITS_INVALID_COUNT_DATA    32
#define XPL_REMAP_ACCEL_CONTROL_ADDR_INVALID_COUNT_CTRL    0x54
#define XPL_REMAP_ACCEL_CONTROL_ADDR_CACHE_MISS_COUNT_DATA 0x60
#define XPL_REMAP_ACCEL_CONTROL_BITS_CACHE_MISS_COUNT_DATA 32
#define XPL_REMAP_ACCEL_CONTROL_ADDR_CACHE_MISS_COUNT_CTRL 0x64
#define XPL_REMAP_ACCEL_CONTROL_ADDR_PIXEL_COUNT_DATA      0x70
#define XPL_REMAP_ACCEL_CONTROL_BITS_PIXEL_COUNT_DATA      32
#define XPL_REMAP_ACCEL_CONTROL_ADDR_PIXEL_COUNT_CTRL      0x74
#define XPL_REMAP_ACCEL_CONTROL_ADDR_CRC_DATA              0x80
#define XPL_REMAP_ACCEL_CONTROL_BITS_CRC_DATA              32
#define XPL_REMAP_ACCEL_CONTROL_ADDR_CRC_CTRL              0x84

