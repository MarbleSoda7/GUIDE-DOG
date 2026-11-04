set BASE [file normalize [file dirname [info script]]]
set XML [file join $BASE ip_repo ov5640_to_lcd_1.0 component.xml]
set PROJ [file join $BASE latest_frame_project latest_frame_project.xpr]
set core [ipx::open_core $XML]
set rev [get_property CORE_REVISION $core]
set_property CORE_REVISION [expr {$rev + 1}] $core
ipx::update_checksums $core
ipx::save_core $core
ipx::unload_core $core
puts "LATEST_CAMERA_CORE_REVISION=[expr {$rev + 1}]"
open_project $PROJ
update_ip_catalog -rebuild
set ip [get_ips -quiet zynq_ov5640_to_lcd_0_0]
if {[llength $ip] != 1} { error "LATEST_CAMERA_IP_NOT_UNIQUE=$ip" }
upgrade_ip $ip
set bd [get_files -quiet */zynq.bd]
if {[llength $bd] != 1} { error "LATEST_CAMERA_BD_NOT_UNIQUE=$bd" }
reset_target all $bd
generate_target all $bd
update_compile_order -fileset sources_1
puts "LATEST_CAMERA_IP_REFRESH_DONE"
close_project
exit
