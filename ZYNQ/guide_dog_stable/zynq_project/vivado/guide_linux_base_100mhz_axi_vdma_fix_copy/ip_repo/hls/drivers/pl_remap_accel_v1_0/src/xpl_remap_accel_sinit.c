// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2024.1 (64-bit)
// Tool Version Limit: 2024.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef __linux__

#include "xstatus.h"
#ifdef SDT
#include "xparameters.h"
#endif
#include "xpl_remap_accel.h"

extern XPl_remap_accel_Config XPl_remap_accel_ConfigTable[];

#ifdef SDT
XPl_remap_accel_Config *XPl_remap_accel_LookupConfig(UINTPTR BaseAddress) {
	XPl_remap_accel_Config *ConfigPtr = NULL;

	int Index;

	for (Index = (u32)0x0; XPl_remap_accel_ConfigTable[Index].Name != NULL; Index++) {
		if (!BaseAddress || XPl_remap_accel_ConfigTable[Index].Control_BaseAddress == BaseAddress) {
			ConfigPtr = &XPl_remap_accel_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XPl_remap_accel_Initialize(XPl_remap_accel *InstancePtr, UINTPTR BaseAddress) {
	XPl_remap_accel_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XPl_remap_accel_LookupConfig(BaseAddress);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XPl_remap_accel_CfgInitialize(InstancePtr, ConfigPtr);
}
#else
XPl_remap_accel_Config *XPl_remap_accel_LookupConfig(u16 DeviceId) {
	XPl_remap_accel_Config *ConfigPtr = NULL;

	int Index;

	for (Index = 0; Index < XPAR_XPL_REMAP_ACCEL_NUM_INSTANCES; Index++) {
		if (XPl_remap_accel_ConfigTable[Index].DeviceId == DeviceId) {
			ConfigPtr = &XPl_remap_accel_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XPl_remap_accel_Initialize(XPl_remap_accel *InstancePtr, u16 DeviceId) {
	XPl_remap_accel_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XPl_remap_accel_LookupConfig(DeviceId);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XPl_remap_accel_CfgInitialize(InstancePtr, ConfigPtr);
}
#endif

#endif

