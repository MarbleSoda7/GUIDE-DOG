open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
puts "CELLS=[get_bd_cells *]"
puts "INTR_PINS=[get_bd_pins -hier -filter {NAME =~ *introut* || NAME =~ *irq*}]"
puts "PS_IRQ=[get_bd_pins processing_system7_0/IRQ_F2P]"
foreach p [get_bd_pins -hier -filter {NAME =~ *introut*}] { puts "PIN $p NETS=[get_bd_nets -of_objects $p]" }
close_project
exit
