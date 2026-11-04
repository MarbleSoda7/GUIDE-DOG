// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2024.1 (64-bit)
// Tool Version Limit: 2024.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
/***************************** Include Files *********************************/
#include "xpl_remap_accel.h"

/************************** Function Implementation *************************/
#ifndef __linux__
int XPl_remap_accel_CfgInitialize(XPl_remap_accel *InstancePtr, XPl_remap_accel_Config *ConfigPtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(ConfigPtr != NULL);

    InstancePtr->Control_BaseAddress = ConfigPtr->Control_BaseAddress;
    InstancePtr->IsReady = XIL_COMPONENT_IS_READY;

    return XST_SUCCESS;
}
#endif

void XPl_remap_accel_Start(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL) & 0x80;
    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL, Data | 0x01);
}

u32 XPl_remap_accel_IsDone(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL);
    return (Data >> 1) & 0x1;
}

u32 XPl_remap_accel_IsIdle(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL);
    return (Data >> 2) & 0x1;
}

u32 XPl_remap_accel_IsReady(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL);
    // check ap_start to see if the pcore is ready for next input
    return !(Data & 0x1);
}

void XPl_remap_accel_EnableAutoRestart(XPl_remap_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL, 0x80);
}

void XPl_remap_accel_DisableAutoRestart(XPl_remap_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_AP_CTRL, 0);
}

void XPl_remap_accel_Set_src(XPl_remap_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_SRC_DATA, (u32)(Data));
    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_SRC_DATA + 4, (u32)(Data >> 32));
}

u64 XPl_remap_accel_Get_src(XPl_remap_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_SRC_DATA);
    Data += (u64)XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_SRC_DATA + 4) << 32;
    return Data;
}

void XPl_remap_accel_Set_lut(XPl_remap_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_LUT_DATA, (u32)(Data));
    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_LUT_DATA + 4, (u32)(Data >> 32));
}

u64 XPl_remap_accel_Get_lut(XPl_remap_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_LUT_DATA);
    Data += (u64)XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_LUT_DATA + 4) << 32;
    return Data;
}

void XPl_remap_accel_Set_dst(XPl_remap_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_DST_DATA, (u32)(Data));
    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_DST_DATA + 4, (u32)(Data >> 32));
}

u64 XPl_remap_accel_Get_dst(XPl_remap_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_DST_DATA);
    Data += (u64)XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_DST_DATA + 4) << 32;
    return Data;
}

void XPl_remap_accel_Set_step(XPl_remap_accel *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_STEP_DATA, Data);
}

u32 XPl_remap_accel_Get_step(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_STEP_DATA);
    return Data;
}

u32 XPl_remap_accel_Get_status(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_STATUS_DATA);
    return Data;
}

u32 XPl_remap_accel_Get_status_vld(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_STATUS_CTRL);
    return Data & 0x1;
}

u32 XPl_remap_accel_Get_invalid_count(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_INVALID_COUNT_DATA);
    return Data;
}

u32 XPl_remap_accel_Get_invalid_count_vld(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_INVALID_COUNT_CTRL);
    return Data & 0x1;
}

u32 XPl_remap_accel_Get_cache_miss_count(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_CACHE_MISS_COUNT_DATA);
    return Data;
}

u32 XPl_remap_accel_Get_cache_miss_count_vld(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_CACHE_MISS_COUNT_CTRL);
    return Data & 0x1;
}

u32 XPl_remap_accel_Get_pixel_count(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_PIXEL_COUNT_DATA);
    return Data;
}

u32 XPl_remap_accel_Get_pixel_count_vld(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_PIXEL_COUNT_CTRL);
    return Data & 0x1;
}

u32 XPl_remap_accel_Get_crc(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_CRC_DATA);
    return Data;
}

u32 XPl_remap_accel_Get_crc_vld(XPl_remap_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_CRC_CTRL);
    return Data & 0x1;
}

void XPl_remap_accel_InterruptGlobalEnable(XPl_remap_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_GIE, 1);
}

void XPl_remap_accel_InterruptGlobalDisable(XPl_remap_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_GIE, 0);
}

void XPl_remap_accel_InterruptEnable(XPl_remap_accel *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_IER);
    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_IER, Register | Mask);
}

void XPl_remap_accel_InterruptDisable(XPl_remap_accel *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_IER);
    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_IER, Register & (~Mask));
}

void XPl_remap_accel_InterruptClear(XPl_remap_accel *InstancePtr, u32 Mask) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XPl_remap_accel_WriteReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_ISR, Mask);
}

u32 XPl_remap_accel_InterruptGetEnabled(XPl_remap_accel *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_IER);
}

u32 XPl_remap_accel_InterruptGetStatus(XPl_remap_accel *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XPl_remap_accel_ReadReg(InstancePtr->Control_BaseAddress, XPL_REMAP_ACCEL_CONTROL_ADDR_ISR);
}

