set root "D:/distortion_correction/vivado/guide_linux_base"
set files [list \
 $root/eth_rtl/eth_stream_stage3_diag.v $root/eth_rtl/eth_stream.v \
 $root/eth_rtl/gmii_to_rgmii_phase_sweep.v $root/eth_rtl/rgmii_tx_phase_sweep.v \
 $root/eth_rtl/gmii_to_rgmii/rgmii_rx.v $root/eth_rtl/gmii_to_rgmii/rgmii_tx.v $root/eth_rtl/gmii_to_rgmii/gmii_to_rgmii.v \
 $root/eth_rtl/udp/udp.v $root/eth_rtl/udp/udp_tx.v $root/eth_rtl/udp/udp_rx.v $root/eth_rtl/udp/crc32_d8.v \
 $root/rtl/dma_udp_packetizer.v $root/rtl/axis_flow_monitor.v ]
read_verilog $files
set rc [catch {synth_design -rtl -top eth_stream_stage3_diag -part xc7z020clg400-2} msg]
puts "ELAB_RC=$rc"
if {$rc} { puts "ELAB_MSG=$msg" }
exit
