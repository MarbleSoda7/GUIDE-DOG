# Board acceptance procedure

This procedure is required before claiming live OV5640 correctness. It does not write an SD card, configure the FPGA, or reset VDMA.

## Round A: read-only VDMA contract

Run one command on the target:

    python3 board_capture_probe.py --hwh /usr/share/camremap/led_test_wrapper.hwh --seconds 10

Accept only if the initial registers show running circular S2MM, VSIZE 480, HSIZE 2400, stride low16 2400, and the three capture addresses 0x30000000, 0x30119400, and 0x30232800. During the sample, status must never contain the software fault mask, writer slots must advance sequentially modulo three, and all three slots must be observed. A polling sample can miss transitions, so repeat the probe if no transition is observed.

## Round B: application evidence

Run the installed application in its normal controlled test mode and collect its periodic log. Accept only if accepted snapshot timing stays below 6ms, dropped frames do not increase after startup, recovery is not repeated, and VDMA status remains healthy. Confirm complete stable raw frames, Remap output, and the existing UDP packet count/length contract at the receiver.

## Limits

These checks still do not prove OV5640 setup/hold timing, PCLK input delay, Xilinx FIFO CDC behavior, or absence of an unobserved late DDR write. Any failure leaves the delivery unaccepted and must be recorded with the raw status and application log.
