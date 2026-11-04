# Three-slot cyclic SG baseline

This directory preserves the high-throughput, **flashback-prone** camera-to-RK
design before the later ownership/genlock experiments. The original cyclic
mode remains available for comparison; the new `-SafeCyclic` build mode adds
an explicit per-frame slot handoff and is the candidate flashback fix. It
starts from commit `253361f`.

## Project and sources

Open `phase_b_project.xpr` in Vivado 2026.1. The target is
`xc7z020clg400-1`. The project file is directly in `guide_dog_main`; there
is no second nested Vivado project to open.

- `phase_b_project.srcs/`: block design, IP configurations, and constraints
- `ip_repo/`, `eth_rtl/`, `rtl/`: custom IP and PL source
- `sw/`, `led_src/`, `bsp/`: Zynq application and standalone build inputs
- `RK/src/rk_frame_recv.cpp` at repository root: matching RK receiver source
- `docs/development_log/FIX_LEDGER.md`: chronological board evidence

Vivado-generated `.gen`, `.runs`, `.cache`, and `.Xil` directories are not
versioned. After a fresh clone, regenerate BD output products and the HDL
wrapper in Vivado before building; a missing generated
`phase_b_project.gen/sources_1/bd/zynq/hdl/zynq_wrapper.v` is expected.
Historical diagnostic Tcl files are retained for provenance and are not the
entry point for this baseline.

## Data path

`OV5640 -> video AXIS -> VDMA S2MM -> DDR slots 0/1/2 -> AXI DMA MM2S
cyclic SG -> async AXIS FIFO -> UDP packetizer -> RGMII -> RK Ethernet`

The original `-Cyclic` mode initializes one cyclic descriptor ring and reads
all three DDR slots in fixed order without per-frame PS commands. The RK
application may discard old complete network frames while processing. Neither
operation gives the DDR slots mutual exclusion: VDMA can overwrite a slot
while DMA is reading it. This is the reproduced mechanism for flashback and
tearing in the baseline.

`-Cyclic -SafeCyclic` keeps the same camera and Ethernet path but sends one
complete frame at a time. Before each frame it waits until S2MM's write slot
reaches the slot just read, then selects the oldest completed slot (`writer-1`)
and only then starts MM2S. This gives the selected slot two camera periods
before S2MM can overwrite it. If a frame read ever takes two or more camera
periods, the scheduler must be extended with a backpressure/drop state; the
simulation below explicitly checks that limit.

## Retained board-test pair

| Artifact | MD5 | SHA-256 |
| --- | --- | --- |
| `test_artifacts/stage3b_sg_udp.bit` | `D03FE682203CD5A4D27DDE949BBDA8A7` | `C746361C146DEA3B1D46439E09B8AD832AFFF9F3CDF91774617ECA8A66862620` |
| `test_artifacts/stage5_camera_cyclic_sg_udp.elf` | `27CD81A55050084642E92EA27C8657A9` | `4D129DB69826F6BB93FDDFEFFC343E60927C0C5A8F52C17F981E41BA6AB19F2F` |

The ledger records a cold-start test of this exact MD5 pair: a 20,000-packet
RK capture contained 23 complete network frames at approximately 49.76 fps.
This measures transport, not unique camera frames or absence of flashback.
The user subsequently observed flashback/tearing. The retained bitstream is
a historical artifact; a fresh build must receive its own hash and validation
and must not be assumed byte-identical.

To rebuild only the cyclic PS application on the original Windows toolchain:

```powershell
.\build_stage5_camera_continuous_elf.ps1 -Cyclic
```

Build the candidate flashback fix with:

```powershell
.\build_stage5_camera_continuous_elf.ps1 -Cyclic -SafeCyclic
```

The resulting ELF is `test_artifacts/stage5_camera_safe_cyclic_sg_udp.elf`.
Run the offline ownership check with:

```powershell
python sim\verify_slot_ownership.py
```

That command overwrites the local cyclic ELF; record its hash first if the
historical pair is needed for comparison. Do not mix a newly built ELF with
the retained bit and call it the documented board-test pair.

## Next design step

Provide real read/write slot exclusion or a verified VDMA genlock equivalent,
then validate frame identity, DDR slot overlap, RK content freshness, and
visible tearing on hardware. A complete UDP frame alone does not establish
that its pixels came from one camera exposure.
