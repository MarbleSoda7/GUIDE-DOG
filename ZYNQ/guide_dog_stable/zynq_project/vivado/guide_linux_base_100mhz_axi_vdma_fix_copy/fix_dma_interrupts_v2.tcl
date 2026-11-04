open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
set ps [get_bd_cells processing_system7_0]
set_property -dict [list CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1} CONFIG.PCW_IRQ_F2P_MODE {DIRECT}] $ps
update_bd_ip [get_bd_cells processing_system7_0]
set psirq [get_bd_pins processing_system7_0/IRQ_F2P]
if {[llength $psirq] == 0} { error "PS IRQ_F2P pin was not enabled" }
set concat [get_bd_cells pl_irq_concat]
if {[llength $concat] == 0} {
  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 pl_irq_concat
  set concat [get_bd_cells pl_irq_concat]
}
set_property CONFIG.NUM_PORTS {2} $concat
set vdma_irq [get_bd_pins axi_vdma_0/s2mm_introut]
set dma_irq [get_bd_pins axi_dma_udp_0/mm2s_introut]
set c0 [get_bd_pins pl_irq_concat/In0]
set c1 [get_bd_pins pl_irq_concat/In1]
set cd [get_bd_pins pl_irq_concat/dout]
foreach p [list $vdma_irq $dma_irq $c0 $c1 $cd $psirq] {
  foreach n [get_bd_nets -of_objects $p] { disconnect_bd_net $n $p }
}
connect_bd_net $vdma_irq $c0
connect_bd_net $dma_irq $c1
connect_bd_net $cd $psirq
validate_bd_design
save_bd_design
generate_target all [get_files D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd]
puts "IRQ_PS=[get_bd_nets -of_objects $psirq]"
puts "IRQ_VDMA=[get_bd_nets -of_objects $vdma_irq]"
puts "IRQ_DMA=[get_bd_nets -of_objects $dma_irq]"
close_project
exit
