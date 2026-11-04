# UDP loop probe: one-shot physical-link test

## Purpose

This test excludes the camera, DDR, VDMA, AXI DMA, packetizer, and RK receiver
program. The FPGA emits exactly one fixed 32-byte UDP payload (`TEST` repeated
eight times) using the known-good UDP loop implementation and the current board
IP/MAC parameters. The UDP source and destination ports are both `1234`.

## Run

1. Keep the RK Ethernet link connected and run on RK:

   `sudo tcpdump -ni eth0 -e -xx -c 1 'udp and dst host 10.212.211.2 and dst port 1234'`

2. On the Windows host, from this directory, run:

   `Set-ExecutionPolicy -Scope Process Bypass`

   `.\run_udp_loop_probe.ps1`

3. Observe the four LEDs. The probe sends one frame after the PS clock is
   initialized, then holds its terminal state.

## Unambiguous result

| LED | Meaning | Conclusion |
|---|---|---|
| `0000` | reset not released | PS reset/init did not reach the probe |
| `0001` or `0010` | clock is running, waiting before launch | RGMII RXC/phase clock works; no TX conclusion yet |
| `0011` | TX start pulse issued, no GMII activity before timeout | UDP TX engine did not produce a frame |
| `0100` | GMII activity observed, no `udp_tx_done` before timeout | frame generation/termination failed inside UDP TX |
| `0101` | one `udp_tx_done` observed; state is held | FPGA UDP engine completed one frame |
| `0111` | terminal timeout | use the preceding stable state as the failed boundary |

If LED is `0101` and tcpdump captures one UDP frame containing `TEST`, the
physical FPGA-to-RK path is proven. If LED is `0101` and tcpdump captures zero,
the remaining boundary is exclusively between the UDP engine's GMII completion
and RK's Ethernet input (RGMII TX pins, PHY, cable, or link partner); no camera
or DMA test is relevant yet.
