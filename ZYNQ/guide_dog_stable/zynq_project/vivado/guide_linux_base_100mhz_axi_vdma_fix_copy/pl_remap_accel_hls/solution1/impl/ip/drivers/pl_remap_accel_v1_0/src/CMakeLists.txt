# ==============================================================
# Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2024.1 (64-bit)
# Tool Version Limit: 2024.05
# Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
# Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
# 
# ==============================================================
cmake_minimum_required(VERSION 3.15)
project(pl_remap_accel)
find_package(common)
collector_create (PROJECT_LIB_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}")
collect (PROJECT_LIB_SOURCES xpl_remap_accel.c)
collect (PROJECT_LIB_SOURCES xpl_remap_accel_sinit.c)
collect (PROJECT_LIB_SOURCES xpl_remap_accel_linux.c)
collect (PROJECT_LIB_SOURCES xpl_remap_accel_g.c)
collector_list (_sources PROJECT_LIB_SOURCES)
collector_create (PROJECT_LIB_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}")
collect (PROJECT_LIB_HEADERS xpl_remap_accel.h)
collect (PROJECT_LIB_HEADERS xpl_remap_accel_hw.h)
collector_list (_headers PROJECT_LIB_HEADERS)
file(COPY ${_headers} DESTINATION ${CMAKE_BINARY_DIR}/include)
include_directories(${CMAKE_BINARY_DIR}/include)
add_library(pl_remap_accel STATIC ${_sources})
set_target_properties(pl_remap_accel PROPERTIES LINKER_LANGUAGE C)

