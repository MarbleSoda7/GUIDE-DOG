open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
set ps [get_bd_cells processing_system7_0]
puts "fabric=[get_property CONFIG.PCW_USE_FABRIC_INTERRUPT $ps]"
puts "all_irq_props=[list_property $ps CONFIG.*IRQ*]"
puts "all_pcw=[list_property $ps CONFIG.PCW_*]"
close_project
exit
