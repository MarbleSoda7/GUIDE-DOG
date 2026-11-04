# Owner-camera baseline acceptance — 2026-10-01

Build identity:

- build ID: `20261001T062420Z_owner_camera_baseline_v1`
- bit SHA-256: `3B702CA5F73DB5E4F86820448A95B654FE4C2813E4148DC170105DCD885664F8`
- ELF SHA-256: `0C00FBAAF83E2B7EDA5EC487874084C13F0D97E485A2CF8EA23A4DA1005F7B13`

Board evidence:

- XSDB downloaded the matching ELF and reported CPU running.
- RK `tcpdump` capture: `owner_accept_20261001_retry3.pcap`, SHA-256 `3D8B8F2981DB7372B231CBD1F93F40B3B012BF5119D64C633FFC064AAAB98DEF`, 281,492,072 bytes.
- FPGA-source packets: 192,672 captured; kernel drops: 0.
- Complete frames: 232, each `827/827`; FIDs `1675..1906`, no duplicate packet indices.
- Terminal frame: `808/827`, truncated by the 15 s capture timeout.
- Measured frame rate: `15.56 fps`; RK receiver log: `15.5--15.6 fps`, `dropped=0`.
- Post-run MM2S status: `0x00011000`; `pkt_start=udp_done=0x0039B1B4`.

Result: end-to-end functional PASS at the restored OV5640 timing. The camera timing currently limits the rate to about 15.6 fps; 40--50 fps is a separate timing revision. S2MM `0x00015090` is retained as a sticky startup diagnostic and is not claimed clean.
