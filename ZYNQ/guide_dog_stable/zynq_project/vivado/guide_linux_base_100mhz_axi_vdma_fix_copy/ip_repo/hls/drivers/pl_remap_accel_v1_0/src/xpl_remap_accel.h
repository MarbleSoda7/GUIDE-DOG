// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2024.1 (64-bit)
// Tool Version Limit: 2024.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef XPL_REMAP_ACCEL_H
#define XPL_REMAP_ACCEL_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#ifndef __linux__
#include "xil_types.h"
#include "xil_assert.h"
#include "xstatus.h"
#include "xil_io.h"
#else
#include <stdint.h>
#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stddef.h>
#endif
#include "xpl_remap_accel_hw.h"

/**************************** Type Definitions ******************************/
#ifdef __linux__
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
#else
typedef struct {
#ifdef SDT
    char *Name;
#else
    u16 DeviceId;
#endif
    u64 Control_BaseAddress;
} XPl_remap_accel_Config;
#endif

typedef struct {
    u64 Control_BaseAddress;
    u32 IsReady;
} XPl_remap_accel;

typedef u32 word_type;

/***************** Macros (Inline Functions) Definitions *********************/
#ifndef __linux__
#define XPl_remap_accel_WriteReg(BaseAddress, RegOffset, Data) \
    Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))
#define XPl_remap_accel_ReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))
#else
#define XPl_remap_accel_WriteReg(BaseAddress, RegOffset, Data) \
    *(volatile u32*)((BaseAddress) + (RegOffset)) = (u32)(Data)
#define XPl_remap_accel_ReadReg(BaseAddress, RegOffset) \
    *(volatile u32*)((BaseAddress) + (RegOffset))

#define Xil_AssertVoid(expr)    assert(expr)
#define Xil_AssertNonvoid(expr) assert(expr)

#define XST_SUCCESS             0
#define XST_DEVICE_NOT_FOUND    2
#define XST_OPEN_DEVICE_FAILED  3
#define XIL_COMPONENT_IS_READY  1
#endif

/************************** Function Prototypes *****************************/
#ifndef __linux__
#ifdef SDT
int XPl_remap_accel_Initialize(XPl_remap_accel *InstancePtr, UINTPTR BaseAddress);
XPl_remap_accel_Config* XPl_remap_accel_LookupConfig(UINTPTR BaseAddress);
#else
int XPl_remap_accel_Initialize(XPl_remap_accel *InstancePtr, u16 DeviceId);
XPl_remap_accel_Config* XPl_remap_accel_LookupConfig(u16 DeviceId);
#endif
int XPl_remap_accel_CfgInitialize(XPl_remap_accel *InstancePtr, XPl_remap_accel_Config *ConfigPtr);
#else
int XPl_remap_accel_Initialize(XPl_remap_accel *InstancePtr, const char* InstanceName);
int XPl_remap_accel_Release(XPl_remap_accel *InstancePtr);
#endif

void XPl_remap_accel_Start(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_IsDone(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_IsIdle(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_IsReady(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_EnableAutoRestart(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_DisableAutoRestart(XPl_remap_accel *InstancePtr);

void XPl_remap_accel_Set_src(XPl_remap_accel *InstancePtr, u64 Data);
u64 XPl_remap_accel_Get_src(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_Set_lut(XPl_remap_accel *InstancePtr, u64 Data);
u64 XPl_remap_accel_Get_lut(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_Set_dst(XPl_remap_accel *InstancePtr, u64 Data);
u64 XPl_remap_accel_Get_dst(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_Set_step(XPl_remap_accel *InstancePtr, u32 Data);
u32 XPl_remap_accel_Get_step(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_status(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_status_vld(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_invalid_count(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_invalid_count_vld(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_cache_miss_count(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_cache_miss_count_vld(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_pixel_count(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_pixel_count_vld(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_crc(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_Get_crc_vld(XPl_remap_accel *InstancePtr);

void XPl_remap_accel_InterruptGlobalEnable(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_InterruptGlobalDisable(XPl_remap_accel *InstancePtr);
void XPl_remap_accel_InterruptEnable(XPl_remap_accel *InstancePtr, u32 Mask);
void XPl_remap_accel_InterruptDisable(XPl_remap_accel *InstancePtr, u32 Mask);
void XPl_remap_accel_InterruptClear(XPl_remap_accel *InstancePtr, u32 Mask);
u32 XPl_remap_accel_InterruptGetEnabled(XPl_remap_accel *InstancePtr);
u32 XPl_remap_accel_InterruptGetStatus(XPl_remap_accel *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif
