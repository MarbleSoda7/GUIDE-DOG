open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
open_bd_design {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
puts "INTF_PORTS=[get_bd_intf_ports]"
foreach p [get_bd_intf_ports] {puts "PORT=$p IFACE=[get_property VLNV $p]"}
puts "PSGPIO=[get_bd_intf_pins processing_system7_0/GPIO_0]"
close_project
exit
