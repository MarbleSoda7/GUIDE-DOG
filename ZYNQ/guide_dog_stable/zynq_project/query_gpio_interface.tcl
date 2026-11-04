open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
open_bd_design {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
foreach o [list [get_bd_intf_ports cam_sccb] [get_bd_intf_pins processing_system7_0/GPIO_0]] {puts "OBJECT=$o"; puts "PROPS=[list_property $o]"; foreach q [list_property $o] {if {[string match *WIDTH* $q] || [string match *LEFT* $q] || [string match *RIGHT* $q] || [string match *CONFIG* $q]} {puts "$q=[get_property $q $o]"}}}
close_project
exit
