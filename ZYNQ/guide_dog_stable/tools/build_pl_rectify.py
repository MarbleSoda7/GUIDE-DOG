#!/usr/bin/env python3
"""Read-only, short preflight for the PL rectify copy.
This tool never opens Vivado/HLS and never modifies either project.
"""
from __future__ import annotations
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = ROOT / "zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy"

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def forbidden_match(text: str):
    """Match only old roots and the old unqualified VLNV."""
    return re.search(r"(?i)(?:D:/latest_project/|D:/distortion_correction/|xilinx[.]com:hls:remap_accel:1[.]0(?![A-Za-z0-9_]))", text.replace(chr(92), "/"))

def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)

def main() -> int:
    if not ROOT.is_dir() or not COPY.is_dir():
        fail(f"missing copy: {COPY}")
    required = [
        COPY / "run_pl_remap_hls.tcl",
        COPY / "integrate_pl_remap.tcl",
        COPY / "prepare_project.tcl",
        COPY / "register_hls_ip.tcl",
        COPY / "guide_linux_base.xpr",
        COPY / "guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd",
        COPY / "pl_remap_accel.cpp",
        COPY / "rtl/remap_axi_guard.v",
        ROOT / "BUILD_PL_RECTIFY.ps1",
        ROOT / "tools/launch_pl_rectify_build.tcl",
        ROOT / "rtl/remap_axi_guard.v",
    ]
    for path in required:
        if not path.is_file():
            fail(f"missing required file: {path}")
    scan = required
    for path in scan:
        text = path.read_text(encoding="utf-8", errors="ignore")
        match = forbidden_match(text)
        if match:
            fail(f"stale/forbidden token {match.group(0)!r} in {path}")
    guard_root = ROOT / "rtl/remap_axi_guard.v"
    guard_copy = COPY / "rtl/remap_axi_guard.v"
    if sha256(guard_root) != sha256(guard_copy):
        fail("canonical guard and project mirror differ")
    guard = guard_root.read_text(encoding="utf-8")
    guard_tokens = (
        "module remap_axi_guard", "REG_FLAGS", "6'h04", "REG_W1C", "6'h14",
        "32'h524d5032", "REG_ABI", "32'd1", "rvalid", "rready", "rresp",
        "bvalid", "bready", "bresp", "wstrb_hold[0]",
    )
    for token in guard_tokens:
        if token not in guard:
            fail(f"guard ABI token absent: {token}")
    kernel = (COPY / "pl_remap_accel.cpp").read_text(encoding="utf-8")
    offsets = {"0x10", "0x1c", "0x28", "0x34", "0x40", "0x50", "0x60", "0x70", "0x80"}
    if not offsets.issubset(set(re.findall(r"0x[0-9a-f]+", kernel, re.I))):
        fail("HLS register offsets incomplete")
    integ = (COPY / "integrate_pl_remap.tcl").read_text(encoding="utf-8")
    for token in (
        "pl_remap_accel_0", "remap_axi_guard_0", "M07_AXI", "M08_AXI",
        "S03_AXI", "0x40000000", "0x40020000", "NUM_MI {9}",
        "FCLK_CLK0", "peripheral_aresetn", "validate_bd_design",
    ):
        if token not in integ:
            fail(f"integration contract absent: {token}")
    if re.search(r"(?i)\b(csynth_design|synth_design|launch_runs|impl_1)\b", integ):
        fail("integration script contains a build command")
    launcher = (ROOT / "tools/launch_pl_rectify_build.tcl").read_text(encoding="utf-8")
    for token in ("led_test_wrapper.bit", "led_test_wrapper.hwh", "led_test_wrapper.xsa", "hw_handoff led_test.hwh", "open_run $impl", "write_hw_platform"):
        if token not in launcher:
            fail(f"launcher artifact contract absent: {token}")
    if "write_hwdef" in launcher:
        fail("launcher must not rename write_hwdef output as HWH")
    hls = (COPY / "run_pl_remap_hls.tcl").read_text(encoding="utf-8")
    for token in ("PL_RECTIFY_BUILD", "create_clock -period 10.0", "export_design -format ip_catalog"):
        if token not in hls:
            fail(f"HLS opt-in/export contract absent: {token}")
    prep = (COPY / "prepare_project.tcl").read_text(encoding="utf-8")
    if re.search(r"(?i)(?:^|[\s\[])glob\s+-|D:/distortion_correction", prep):
        fail("prepare_project.tcl uses a broad glob or stale source root")
    from build_pl_manifest import source_paths
    print('ACTIVE_COPY_LOCAL_SOURCES=' + str(len(source_paths())))
    print("PASS: PL rectify copy static checks")
    print(f"COPY={COPY}")
    print(f"GUARD_SHA256={sha256(guard_root)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
